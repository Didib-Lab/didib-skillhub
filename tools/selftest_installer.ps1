#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test the Windows installer over real HTTP without touching GitHub or the
    real ~/.agents/skills directory.

.DESCRIPTION
    Serves a fake release archive from a loopback HTTP listener whose URL shape
    matches codeload.github.com exactly, then drives scripts/install.ps1 against
    it.

    Two details matter, and both were learned the hard way:

    * The URL shape. codeload serves a branch archive at
      /<owner>/<repo>/zip/refs/heads/<ref> with no file extension, and the
      archive holds a single top-level directory named "<ref>". An earlier
      installer appended ".zip" to that URL; a fixture that had been built to
      match the bug hid it. The assertions below pin the shape of the URL the
      installer builds, so a wrong assumption cannot pass.

    * Real HTTP. Reaching the fixture through file:// works in Windows
      PowerShell but throws "The 'file' scheme is not supported" in PowerShell 7,
      which is what GitHub Actions runs. A loopback listener behaves identically
      on both, so the test is not silently version-specific.

.PARAMETER Ref
    Ref name to simulate. Defaults to a random one, so a cached archive can
    never be mistaken for a fresh download.

.EXAMPLE
    ./tools/selftest_installer.ps1

.EXAMPLE
    ./tools/selftest_installer.ps1 -KeepTemp
#>
[CmdletBinding()]
param(
    [string]$Ref,
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Continue'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "    PASS  $Message" -ForegroundColor Green }
function Write-Bad { param([string]$Message) Write-Host "    FAIL  $Message" -ForegroundColor Red }

if (-not $Ref) { $Ref = 'vtest-' + [guid]::NewGuid().ToString('N').Substring(0, 12) }

$repoRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot 'scripts\install.ps1'
if (-not (Test-Path $installer)) { Write-Error "cannot find $installer"; exit 1 }

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ('installer-selftest-' + [guid]::NewGuid().ToString('N'))
$results = @()

function Assert {
    param([string]$Label, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { Write-Ok $Label; $script:results += $true }
    else { Write-Bad "$Label $Detail"; $script:results += $false }
}

$runspace = $null
$powerShell = $null
$listener = $null

try {
    # ----------------------------------------------------------------------
    # Build an archive shaped exactly like codeload's
    # ----------------------------------------------------------------------

    Write-Step "Building a fake release archive for ref '$Ref'"
    New-Item -ItemType Directory -Force -Path $sandbox | Out-Null

    $stage = Join-Path $sandbox "stage\$Ref"
    Copy-Item -Path (Join-Path $repoRoot 'skills') -Destination (Join-Path $stage 'skills') -Recurse -Force
    Get-ChildItem -Path $stage -Recurse -Directory -Filter '__pycache__' |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = Join-Path $sandbox $Ref
    # Entries are written by hand rather than with CreateFromDirectory, which
    # omits the root directory name and uses backslashes on Windows.
    $fileStream = [System.IO.File]::Open($archive, [System.IO.FileMode]::CreateNew)
    try {
        $zip = [System.IO.Compression.ZipArchive]::new(
            $fileStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $stageFull = (Resolve-Path $stage).Path
            foreach ($file in Get-ChildItem -Path $stage -Recurse -File) {
                $relative = $file.FullName.Substring($stageFull.Length).TrimStart('\', '/')
                $entry = $zip.CreateEntry("$Ref/" + ($relative -replace '\\', '/'),
                    [System.IO.Compression.CompressionLevel]::Optimal)
                $entryStream = $entry.Open()
                try {
                    $source = [System.IO.File]::OpenRead($file.FullName)
                    try { $source.CopyTo($entryStream) } finally { $source.Dispose() }
                } finally { $entryStream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fileStream.Dispose() }

    $readBack = [System.IO.Compression.ZipFile]::OpenRead($archive)
    try { $entries = @($readBack.Entries | ForEach-Object { $_.FullName }) }
    finally { $readBack.Dispose() }

    $topLevels = @($entries | ForEach-Object { ($_ -split '/')[0] } | Select-Object -Unique)
    Assert 'fixture archive has exactly one top-level directory' ($topLevels.Count -eq 1) "got: $($topLevels -join ', ')"
    Assert 'the top-level directory is named after the ref' ($topLevels[0] -eq $Ref) "got: $($topLevels[0])"
    Assert 'the archive carries the skill files' (
        @($entries | Where-Object { $_ -like "$Ref/skills/*/SKILL.md" }).Count -ge 2)
    Assert 'entry names use forward slashes' (-not ($entries -match '\\'))

    # ----------------------------------------------------------------------
    # Serve it over loopback HTTP, at codeload's path shape
    # ----------------------------------------------------------------------

    $port = Get-Random -Minimum 45000 -Maximum 46000
    $basePath = '/testowner/testrepo/zip/refs/heads'

    $serverSource = @'
param([int]$Port, [string]$Archive, [string]$BasePath, [hashtable]$Flags)

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try { $listener.Start() } catch { $Flags.Error = $_.Exception.Message; return }
$Flags.Ready = $true

while (-not $Flags.Stop) {
    $context = $null
    try { $context = $listener.GetContext() } catch { break }

    $path = $context.Request.Url.AbsolutePath
    $Flags.Requests.Enqueue($path)

    if ($path -eq $BasePath -or $path.StartsWith("$BasePath/")) {
        $bytes = [System.IO.File]::ReadAllBytes($Archive)
        $context.Response.StatusCode = 200
        $context.Response.ContentType = 'application/zip'
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $context.Response.StatusCode = 404
        $payload = [System.Text.Encoding]::UTF8.GetBytes('not found')
        $context.Response.OutputStream.Write($payload, 0, $payload.Length)
    }
    $context.Response.OutputStream.Close()
}

$listener.Stop()
'@

    $flags = @{
        Ready    = $false
        Stop     = $false
        Error    = $null
        Requests = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    }

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powerShell = [powershell]::Create()
    $powerShell.Runspace = $runspace
    [void]$powerShell.AddScript($serverSource).AddArgument($port).AddArgument($archive).AddArgument($basePath).AddArgument($flags)
    $handle = $powerShell.BeginInvoke()

    Write-Step "Serving the archive on http://127.0.0.1:$port"
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        Start-Sleep -Milliseconds 50
        if ($flags.Ready -or $flags.Error -or $handle.IsCompleted) { break }
    }
    if ($flags.Error) { Write-Error "listener failed: $($flags.Error)"; exit 1 }
    Assert 'the fixture server is listening' $flags.Ready

    # Prove the server answers at the exact path the installer will request.
    $probeUrl = "http://127.0.0.1:$port$basePath/$Ref"
    try {
        $probe = Invoke-WebRequest -Uri $probeUrl -UseBasicParsing -TimeoutSec 20
        Assert 'the archive is served at codeload''s path shape' ($probe.StatusCode -eq 200 -and $probe.RawContentLength -gt 0) "status $($probe.StatusCode)"
    } catch {
        Assert 'the archive is served at codeload''s path shape' $false $_.Exception.Message
    }

    # ----------------------------------------------------------------------
    # Point the installer at the fixture server
    # ----------------------------------------------------------------------

    $dest = Join-Path $sandbox 'installed'
    $env:DDB_SKILLHUB_DEST = $dest
    $env:DDB_SKILLHUB_REF = $Ref
    $env:DDB_SKILLHUB_REPO = 'testowner/testrepo'

    $patched = (Get-Content $installer -Raw).Replace(
        'https://codeload.github.com',
        "http://127.0.0.1:$port"
    )
    $driver = Join-Path $sandbox 'install.ps1'
    [System.IO.File]::WriteAllText($driver, $patched)

    Write-Step 'Checking the download URL shape'
    Assert 'installer builds a URL ending in the bare ref' (
        $patched -match '\$url\s*=\s*"[^"]*\$RepoSlug/zip/refs/heads/\$Ref"'
    )

    # ----------------------------------------------------------------------
    # Drive the installer
    # ----------------------------------------------------------------------

    Write-Step 'Installing a skill with a single file'
    & $driver install hello-world *> $null
    Assert 'hello-world installs' (Test-Path (Join-Path $dest 'hello-world\SKILL.md'))

    Write-Step 'Installing a skill with nested directories'
    & $driver install conventional-commits *> $null
    Assert 'nested scripts/ files are copied' (Test-Path (Join-Path $dest 'conventional-commits\scripts\commit_lint.py'))
    Assert 'nested references/ files are copied' (Test-Path (Join-Path $dest 'conventional-commits\references\spec.md'))
    Assert 'no build output is copied' (-not (Test-Path (Join-Path $dest 'conventional-commits\scripts\__pycache__')))

    Write-Step 'Refusing invalid input'
    & $driver install hello-world *> $null
    Assert 'a duplicate install is refused' ($LASTEXITCODE -ne 0)

    & $driver install 'Bad_Name' *> $null
    Assert 'a non-kebab-case name is refused' ($LASTEXITCODE -ne 0)

    & $driver install no-such-skill *> $null
    Assert 'a missing skill is refused' ($LASTEXITCODE -ne 0)

    Write-Step 'Doctor and uninstall'
    $doctor = & $driver doctor *>&1 | Out-String
    Assert 'doctor reports installed skills' ($doctor -match 'conventional-commits')

    & $driver uninstall hello-world *> $null
    Assert 'uninstall removes the directory' (-not (Test-Path (Join-Path $dest 'hello-world')))
    Assert 'uninstall leaves other skills alone' (Test-Path (Join-Path $dest 'conventional-commits'))

    Write-Step 'Dot-sourcing must not kill the caller'
    . $driver doctor *> $null
    Assert 'the caller survives dot-sourcing' $true

    Assert 'every download hit the expected path' (
        @($flags.Requests | Where-Object { $_ -notlike "$basePath/*" }).Count -eq 0
    ) "unexpected: $(@($flags.Requests | Where-Object { $_ -notlike "$basePath/*" }) -join ', ')"
}
finally {
    if ($flags) { $flags.Stop = $true }
    if ($powerShell) { try { $powerShell.Stop() } catch { }; try { $powerShell.Dispose() } catch { } }
    if ($runspace) { try { $runspace.Close() } catch { } }

    Remove-Item Env:DDB_SKILLHUB_DEST, Env:DDB_SKILLHUB_REF, Env:DDB_SKILLHUB_REPO -ErrorAction SilentlyContinue

    if ($KeepTemp) { Write-Host "`nkept: $sandbox" }
    else { Remove-Item -Recurse -Force $sandbox -ErrorAction SilentlyContinue }
}

$passed = @($results | Where-Object { $_ }).Count
$failed = @($results | Where-Object { -not $_ }).Count
Write-Host ''
Write-Host "$passed passed, $failed failed"
exit $(if ($failed -gt 0) { 1 } else { 0 })
