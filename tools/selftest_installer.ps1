#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test the Windows installer without touching the network or the real
    ~/.agents/skills directory.

.DESCRIPTION
    Builds a fake release archive whose layout matches codeload.github.com
    exactly, serves it from a local directory, and drives scripts/install.ps1
    against it.

    The archive layout matters. codeload serves a branch archive at

        https://codeload.github.com/<owner>/<repo>/zip/refs/heads/<ref>

    with no file extension, and the archive contains a single top-level directory
    named "<ref>". An earlier version of the installer appended ".zip" to that
    URL and this harness failed to catch it because the fixture was built to
    match the bug instead of the service. The fixture below is deliberately
    derived from the real URL shape, so it cannot validate a wrong assumption.

.PARAMETER Ref
    Ref name to simulate. Defaults to a random one so a cached archive can never
    be mistaken for a fresh download.

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

$sandbox = Join-Path $env:LOCALAPPDATA ('installer-selftest-' + [guid]::NewGuid().ToString('N'))
$results = @()

function Assert {
    param([string]$Label, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { Write-Ok $Label; $script:results += $true }
    else { Write-Bad "$Label $Detail"; $script:results += $false }
}

try {
    # ----------------------------------------------------------------------
    # Build an archive shaped exactly like codeload's, at the exact path the
    # installer derives from its URL template.
    # ----------------------------------------------------------------------

    Write-Step "Building a fake release archive for ref '$Ref'"

    $served = Join-Path $sandbox 'served\testowner\testrepo\zip\refs\heads'
    New-Item -ItemType Directory -Force -Path $served | Out-Null

    # Archive contents: a single top-level directory named after the ref, with
    # forward-slash entry names, which is exactly what codeload produces.
    $stage = Join-Path $sandbox "stage\$Ref"
    Copy-Item -Path (Join-Path $repoRoot 'skills') -Destination (Join-Path $stage 'skills') -Recurse -Force
    Get-ChildItem -Path $stage -Recurse -Directory -Filter '__pycache__' |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = Join-Path $served $Ref
    Remove-Item $archive, "$archive.zip" -Force -ErrorAction SilentlyContinue

    # ZipFile::CreateFromDirectory is deliberately avoided: it omits the root
    # directory name (so no "<ref>/" prefix appears) and writes entries with
    # backslashes on Windows. Either difference would let a broken installer
    # pass. Entries are written by hand instead.
    $stream = [System.IO.File]::Open($archive, [System.IO.FileMode]::CreateNew)
    try {
        $zip = [System.IO.Compression.ZipArchive]::new(
            $stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $stageFull = (Resolve-Path $stage).Path
            foreach ($file in Get-ChildItem -Path $stage -Recurse -File) {
                $relative = $file.FullName.Substring($stageFull.Length).TrimStart('\', '/')
                $entryName = "$Ref/" + ($relative -replace '\\', '/')
                $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
                $entryStream = $entry.Open()
                try {
                    $fileStream = [System.IO.File]::OpenRead($file.FullName)
                    try { $fileStream.CopyTo($entryStream) } finally { $fileStream.Dispose() }
                } finally { $entryStream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
    } finally {
        $zip.Dispose()
    }

    $topLevels = @($entries | ForEach-Object { ($_ -split '/')[0] } | Select-Object -Unique)
    Assert 'fixture archive has exactly one top-level directory' ($topLevels.Count -eq 1) "got: $($topLevels -join ', ')"
    Assert 'the top-level directory is named after the ref' ($topLevels[0] -eq $Ref) "got: $($topLevels[0])"
    Assert 'the archive carries the skill files' (
        @($entries | Where-Object { $_ -like "$Ref/skills/*/SKILL.md" }).Count -ge 2
    )
    Assert 'entry names use forward slashes' (-not ($entries -match '\\'))

    # ----------------------------------------------------------------------
    # Point the installer at the local archive.
    # ----------------------------------------------------------------------

    $dest = Join-Path $sandbox 'installed'
    $env:DDB_SKILLHUB_DEST = $dest
    $env:DDB_SKILLHUB_REF = $Ref
    $env:DDB_SKILLHUB_REPO = 'testowner/testrepo'

    $patched = (Get-Content $installer -Raw).Replace(
        'https://codeload.github.com',
        'file:///' + (($sandbox + '\served') -replace '\\', '/')
    )
    $driver = Join-Path $sandbox 'install.ps1'
    [System.IO.File]::WriteAllText($driver, $patched)

    # ----------------------------------------------------------------------
    # The URL the installer builds must match where the fixture lives.
    # ----------------------------------------------------------------------

    Write-Step 'Checking the download URL shape'
    $urlLine = (Get-Content $driver | Select-String -Pattern 'codeload|served/').Line -join ' '
    Assert 'installer builds a URL ending in the bare ref' (
        $patched -match '\$url\s*=\s*"[^"]*\$RepoSlug/zip/refs/heads/\$Ref"'
    ) -Detail "URL template: $urlLine"

    # ----------------------------------------------------------------------
    # Drive the installer.
    # ----------------------------------------------------------------------

    Write-Step 'Installing a skill with a single file'
    & $driver install hello-world *> $null
    Assert 'hello-world installs' (Test-Path (Join-Path $dest 'hello-world\SKILL.md'))

    Write-Step 'Installing a skill with nested directories'
    & $driver install conventional-commits *> $null
    $nested = Join-Path $dest 'conventional-commits\scripts\commit_lint.py'
    Assert 'nested scripts/ files are copied' (Test-Path $nested)
    Assert 'nested references/ files are copied' (
        Test-Path (Join-Path $dest 'conventional-commits\references\spec.md')
    )

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
    $before = $true
    . $driver doctor *> $null
    Assert 'the caller survives dot-sourcing' $before
}
finally {
    Remove-Item Env:DDB_SKILLHUB_DEST, Env:DDB_SKILLHUB_REF, Env:DDB_SKILLHUB_REPO -ErrorAction SilentlyContinue
    if ($KeepTemp) { Write-Host "`nkept: $sandbox" }
    else { Remove-Item -Recurse -Force $sandbox -ErrorAction SilentlyContinue }
}

$passed = @($results | Where-Object { $_ }).Count
$failed = @($results | Where-Object { -not $_ }).Count
Write-Host ''
Write-Host "$passed passed, $failed failed"
exit $(if ($failed -gt 0) { 1 } else { 0 })
