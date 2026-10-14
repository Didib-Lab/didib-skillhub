#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Diagnose why git's HTTPS transport is failing on a machine where gh works.

.DESCRIPTION
    Written after a real failure: `git push` reported

        fatal: unable to access 'https://github.com/...': Failed to connect to
        github.com port 443 after 21179 ms: Could not connect to server

    while `gh api` and .NET's Invoke-WebRequest reached GitHub without trouble.
    This script separates the layers so the failing one is obvious:

      1. DNS          what github.com resolves to
      2. raw TCP      a socket to each resolved address
      3. TLS          a real handshake through that socket
      4. HTTPS        what Invoke-WebRequest (the .NET stack) does
      5. git          git ls-remote with curl's own diagnostics

    Run it when clone, fetch or push stops working, then act on the first layer
    that fails. If TLS is the failing layer but HTTPS succeeds, the difference is
    the TLS implementation, and `tools/push-via-api.ps1` is the workaround.

.EXAMPLE
    ./tools/diagnose-git-transport.ps1 -RepoPath ..

.EXAMPLE
    ./tools/diagnose-git-transport.ps1 -HostName github.com
#>
[CmdletBinding()]
param(
    [string]$RepoPath,
    [string]$HostName = 'github.com',
    [int]$Port = 443,
    [int]$TimeoutMs = 12000
)

$ErrorActionPreference = 'Continue'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "    OK    $Message" -ForegroundColor Green }
function Write-Bad { param([string]$Message) Write-Host "    FAIL  $Message" -ForegroundColor Red }
function Write-Note { param([string]$Message) Write-Host "    note  $Message" }

if (-not $RepoPath) { $RepoPath = Split-Path -Parent $PSScriptRoot }

$addresses = @()
$verdicts = [ordered]@{}

# --- 1. DNS -----------------------------------------------------------------

Write-Step "1. DNS: $HostName"
try {
    $answers = Resolve-DnsName $HostName -Type A -ErrorAction Stop |
        Where-Object { $_.IPAddress }
    $addresses = @($answers | Select-Object -ExpandProperty IPAddress)
    if ($addresses.Count -eq 0) {
        Write-Bad 'no A records'
        $verdicts['dns'] = $false
    } else {
        Write-Ok ($addresses -join ', ')
        $verdicts['dns'] = $true
    }
} catch {
    Write-Bad "resolution failed: $($_.Exception.Message)"
    $verdicts['dns'] = $false
}

# --- 2. Raw TCP to every address -------------------------------------------

Write-Step "2. Raw TCP: $HostName`:$Port on each address"
$tcpOk = @{}
foreach ($address in $addresses) {
    $client = [System.Net.Sockets.TcpClient]::new()
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $task = $client.ConnectAsync($address, $Port)
        if ($task.Wait($TimeoutMs) -and $client.Connected) {
            Write-Ok "$address connected in $([math]::Round($watch.Elapsed.TotalSeconds, 2))s"
            $tcpOk[$address] = $true
        } else {
            Write-Bad "$address did not connect within ${TimeoutMs}ms"
            $tcpOk[$address] = $false
        }
    } catch {
        Write-Bad "$address $($_.Exception.Message)"
        $tcpOk[$address] = $false
    } finally {
        $client.Close()
    }
}
$verdicts['tcp'] = ($tcpOk.Values -contains $true)

# --- 3. TLS handshake -------------------------------------------------------

Write-Step '3. TLS handshake through each reachable address'
$tlsOk = $false
foreach ($address in $addresses) {
    if (-not $tcpOk[$address]) { Write-Note "$address skipped (TCP failed)"; continue }

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $client.Connect($address, $Port)
        $ssl = [System.Net.Security.SslStream]::new($client.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($HostName)
        Write-Ok "$address TLS $($ssl.SslProtocol), certificate subject '$($ssl.RemoteCertificate.Subject)'"
        $tlsOk = $true
        $ssl.Dispose()
    } catch {
        Write-Bad "$address TLS failed: $($_.Exception.Message)"
    } finally {
        $client.Close()
    }
}
$verdicts['tls'] = $tlsOk

# --- 4. The .NET HTTP stack -------------------------------------------------

Write-Step "4. HTTPS via the .NET stack: https://$HostName/"
try {
    $response = Invoke-WebRequest -Uri "https://$HostName/" -UseBasicParsing -TimeoutSec 25
    Write-Ok "HTTP $($response.StatusCode)"
    $verdicts['https'] = $true
} catch {
    Write-Bad $_.Exception.Message
    $verdicts['https'] = $false
}

# --- 5. curl and git --------------------------------------------------------

Write-Step '5. curl and git (which use their own TLS stacks)'
foreach ($curl in @('curl.exe', 'C:\Program Files\Git\mingw64\bin\curl.exe')) {
    $resolved = Get-Command $curl -ErrorAction SilentlyContinue
    if (-not $resolved) { Write-Note "$curl not found"; continue }
    $output = & $resolved.Source -sS -o NUL -w '%{http_code} %{time_total}s' --max-time 20 "https://$HostName/" 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Ok "$curl HTTP $output" } else { Write-Bad "$curl $output" }
}

if (Test-Path (Join-Path $RepoPath '.git')) {
    $remote = (& git -C $RepoPath remote get-url origin 2>$null)
    Write-Note "git remote: $remote"
    $gitOut = & git -C $RepoPath -c http.version=HTTP/1.1 ls-remote origin 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok 'git ls-remote succeeded'
        $verdicts['git'] = $true
    } else {
        Write-Bad "git ls-remote failed: $(($gitOut | Select-Object -First 3) -join ' ')"
        $verdicts['git'] = $false
    }
} else {
    Write-Note "$RepoPath is not a git repository; skipping the git probe"
}

# --- Verdict ----------------------------------------------------------------

Write-Host ''
Write-Step 'Summary'
foreach ($layer in $verdicts.Keys) {
    $state = if ($verdicts[$layer]) { 'pass' } else { 'FAIL' }
    Write-Host ("    {0,-6} {1}" -f $layer, $state)
}

Write-Host ''
if ($verdicts['dns'] -and $verdicts['tcp'] -and $verdicts['https'] -and -not $verdicts['tls']) {
    Write-Note 'TCP connects and .NET HTTPS works, but the .NET TLS probe failed. Retry it;'
    Write-Note 'this pattern is usually transient.'
} elseif ($verdicts['https'] -and -not $verdicts['git']) {
    Write-Note 'The .NET stack reaches GitHub but git does not, so the difference is the TLS'
    Write-Note 'implementation, not the network. Use tools/push-via-api.ps1 to publish.'
} elseif (-not $verdicts['tcp']) {
    Write-Note 'No address accepted a TCP connection. A proxy, VPN split tunnel, or the'
    Write-Note 'network itself is blocking outbound 443.'
}

exit 0
