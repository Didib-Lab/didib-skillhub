<#
.SYNOPSIS
    DDB Skillhub installer for Windows.

.DESCRIPTION
    Installs skills from the DDB Skillhub into ~/.agents/skills/<name>, which is
    where DeepSeek Harness and other agent runtimes look for skills.

.EXAMPLE
    .\install.ps1 list
    .\install.ps1 install --all
    .\install.ps1 install pdf-table-extract
    .\install.ps1 uninstall pdf-table-extract
    .\install.ps1 doctor
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments = @()
)

$ErrorActionPreference = 'Stop'

$RepoSlug = if ($env:DDB_SKILLHUB_REPO) { $env:DDB_SKILLHUB_REPO } else { 'Didib-Lab/didib-skillhub' }
$Ref      = if ($env:DDB_SKILLHUB_REF)  { $env:DDB_SKILLHUB_REF }  else { 'main' }
$Dest     = if ($env:DDB_SKILLHUB_DEST) { $env:DDB_SKILLHUB_DEST } else { Join-Path $HOME '.agents\skills' }

function Write-Info { param([string]$Message) Write-Host $Message }

# Records a failure without terminating the caller's session, so this script can
# safely be dot-sourced or invoked from another script. Functions report failure
# with $false and their callers stop; the exit code is applied once, at the
# bottom of the file. Errors go to stderr directly rather than through
# Write-Error, which becomes terminating under $ErrorActionPreference = 'Stop'.
$script:ExitCode = 0
function Die {
    param([string]$Message)
    [Console]::Error.WriteLine("error: $Message")
    $script:ExitCode = 1
}

function Get-RemoteNames {
    # Returns $null when the listing could not be fetched.
    $uri = "https://api.github.com/repos/$RepoSlug/contents/skills?ref=$Ref"
    try {
        $items = Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'ddb-skillhub' }
    } catch {
        Die "cannot reach github.com: $($_.Exception.Message)"
        return $null
    }
    return @($items | Where-Object { $_.type -eq 'dir' } | ForEach-Object { $_.name })
}

function Get-RemoteDescription {
    param([string]$Name)

    # The API is used rather than raw.githubusercontent.com because the raw host
    # sits behind a CDN that keeps serving a stale SKILL.md for several minutes
    # after a release, which would leave a freshly published skill looking
    # undescribed. The API has no such lag and needs no authentication here.
    $metadataUri = "https://api.github.com/repos/$RepoSlug/contents/skills/$Name/SKILL.md?ref=$Ref"
    $headers = @{ 'User-Agent' = 'ddb-skillhub' }
    $text = $null

    try {
        $document = Invoke-RestMethod -Uri $metadataUri -Headers $headers -TimeoutSec 20
    } catch {
        # Rate limited, offline, or the skill has no SKILL.md.
        return '(description unavailable)'
    }

    if ($document -is [string]) {
        $text = $document
    } elseif ($document.content) {
        try {
            $text = [System.Text.Encoding]::UTF8.GetString(
                [Convert]::FromBase64String(($document.content -replace '\s', ''))
            )
        } catch {
            $text = $null
        }
    }

    if (-not $text) { return '(description unavailable)' }

    $match = [regex]::Match($text, '(?m)^description:[ \t]*(.+?)[ \t]*$')
    if ($match.Success) {
        $value = $match.Groups[1].Value.Trim()
        if ($value.Length -gt 100) { $value = $value.Substring(0, 100).TrimEnd() + '...' }
        return $value
    }
    return '(no description)'
}

function Invoke-List {
    $names = Get-RemoteNames
    if ($null -eq $names) { return }
    if ($names.Count -eq 0) { Die "no skills found in $RepoSlug@$Ref"; return }

    Write-Info "Available skills in $RepoSlug@$Ref"
    Write-Info ''
    foreach ($name in $names) {
        $desc = Get-RemoteDescription -Name $name
        Write-Host ("  {0,-28} {1}" -f $name, $desc)
    }
}

function Install-One {
    param([string]$Name)

    if ($Name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        Die "invalid skill name '$Name' (kebab-case only)"
        return $false
    }

    $target = Join-Path $Dest $Name
    if (Test-Path $target) {
        Die "$target already exists; uninstall it first"
        return $false
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ddb-skillhub-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    try {
        $zip = Join-Path $tmp 'repo.zip'
        # codeload takes the ref as a path suffix: /zip/refs/heads/<branch>.
        # Appending ".zip" makes GitHub look for a branch literally named
        # "<branch>.zip" and the request 404s.
        $url = "https://codeload.github.com/$RepoSlug/zip/refs/heads/$Ref"
        Write-Info "fetching $RepoSlug@$Ref ..."
        try {
            Invoke-WebRequest -Uri $url -OutFile $zip -Headers @{ 'User-Agent' = 'ddb-skillhub' }
        } catch {
            Die "download failed: $($_.Exception.Message)"
            return $false
        }

        Expand-Archive -Path $zip -DestinationPath $tmp -Force

        # The archive unpacks into a single top-level directory whose name is
        # derived from the repository and ref, so locate it rather than assume.
        $repoRoot = @(Get-ChildItem -Path $tmp -Directory)
        if ($repoRoot.Count -eq 0) {
            Die 'the downloaded archive was empty'
            return $false
        }

        $src = Join-Path $repoRoot[0].FullName "skills\$Name"
        if (-not (Test-Path $src)) {
            Die "skill '$Name' does not exist in $RepoSlug"
            return $false
        }

        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        Copy-Item -Path $src -Destination $target -Recurse -Force
        Write-Info "installed '$Name' -> $target"
        return $true
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

function Invoke-Install {
    param([string[]]$Names)

    if (-not $Names -or $Names.Count -eq 0) { $Names = @('--all') }

    if ($Names[0] -eq '--all') {
        $available = Get-RemoteNames
        if ($null -eq $available) { return }
        if ($available.Count -eq 0) { Die "no skills found in $RepoSlug@$Ref"; return }

        $failed = 0
        foreach ($name in $available) {
            if (-not (Install-One -Name $name)) {
                $failed++
                $script:ExitCode = 0  # one bad skill must not fail the batch
                Write-Warning "skipped '$name'"
            }
        }
        if ($failed -gt 0) { Write-Warning "$failed skill(s) could not be installed" }
    } else {
        foreach ($name in $Names) {
            if (-not (Install-One -Name $name)) { return }
        }
    }
}

function Invoke-Uninstall {
    param([string]$Name)
    if (-not $Name) { Die 'usage: install.ps1 uninstall <skill-name>'; return }
    $target = Join-Path $Dest $Name
    if (-not (Test-Path $target)) { Die "$target does not exist"; return }
    Remove-Item -Recurse -Force $target
    Write-Info "removed $target"
}

function Invoke-Doctor {
    Write-Info "skills directory: $Dest"
    if (-not (Test-Path $Dest)) { Write-Info '  (does not exist yet)'; return }
    $dirs = @(Get-ChildItem -Path $Dest -Directory)
    if ($dirs.Count -eq 0) { Write-Info '  (no skills installed)'; return }
    foreach ($dir in $dirs) {
        if (Test-Path (Join-Path $dir.FullName 'SKILL.md')) {
            Write-Host ("  ok     " + $dir.Name)
        } else {
            Write-Host ("  BROKEN " + $dir.Name + ' (no SKILL.md)')
        }
    }
}

function Show-Usage {
    @'
DDB Skillhub installer

Usage:
  install.ps1 list                  list skills available in the hub
  install.ps1 install <name>        install one skill
  install.ps1 install --all         install every skill
  install.ps1 uninstall <name>      remove an installed skill
  install.ps1 doctor                show what is installed locally

Environment:
  DDB_SKILLHUB_REPO   owner/repo to install from (default Didib-Lab/didib-skillhub)
  DDB_SKILLHUB_REF    git ref to install from   (default main)
  DDB_SKILLHUB_DEST   install target            (default ~/.agents/skills)
'@ | Write-Host
}

switch ($Command.ToLowerInvariant()) {
    'list'                { Invoke-List }
    'install'             { Invoke-Install -Names $Arguments }
    'uninstall'           { Invoke-Uninstall -Name ($Arguments | Select-Object -First 1) }
    'remove'              { Invoke-Uninstall -Name ($Arguments | Select-Object -First 1) }
    'doctor'              { Invoke-Doctor }
    'help'                { Show-Usage }
    '-h'                  { Show-Usage }
    '--help'              { Show-Usage }
    default               { Show-Usage; Die "unknown command '$Command'" }
}

# Report failure through the exit code. Dot-sourcing the script skips this, so
# sourcing it never terminates the caller's session.
if ($MyInvocation.InvocationName -ne '.') {
    exit $script:ExitCode
}
