#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Publish the local repository to GitHub using the GitHub API instead of git push.

.DESCRIPTION
    On this machine git's HTTPS transport cannot complete a TLS handshake with
    github.com, while the GitHub CLI can. This script therefore rebuilds the
    local commit on the remote through the Git data API: it uploads every file
    as a blob, recreates the directory structure as a tree, creates one commit,
    and moves the branch ref to it.

    The result is an ordinary GitHub commit. Cloning and pulling work normally;
    only the transport used to publish it is unusual.

    Use -DryRun first to see exactly what would be uploaded.

.PARAMETER Repo
    Target repository as owner/name. Defaults to the origin remote of the local
    repository when it is a github.com URL.

.PARAMETER RepoPath
    Local repository to publish. Defaults to the parent of this script's folder.

.PARAMETER Branch
    Branch to create or update on the remote.

.PARAMETER CommitMessage
    Message for the commit. Defaults to the current HEAD commit's message.

.PARAMETER Force
    Update the branch even if it already exists on the remote.

.PARAMETER Parent
    Commit sha to use as the parent of the new commit. Defaults to the current
    tip of the remote branch, which keeps the published history linear. Pass
    'none' to create a root commit.

.EXAMPLE
    ./tools/push-via-api.ps1 -Repo Didib-Lab/didib-skillhub -Branch main -DryRun

.EXAMPLE
    ./tools/push-via-api.ps1 -Repo Didib-Lab/didib-skillhub -Branch main
#>
[CmdletBinding()]
param(
    [string]$Repo,
    [string]$RepoPath,
    [string]$Branch = 'main',
    [string]$CommitMessage,
    [string]$Parent,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Detail { param([string]$Message) Write-Host "    $Message" }
function Write-Note { param([string]$Message) Write-Host "    note  $Message" -ForegroundColor Yellow }
function Die { param([string]$Message) [Console]::Error.WriteLine("error: $Message"); exit 1 }

if (-not $RepoPath) { $RepoPath = Split-Path -Parent $PSScriptRoot }
$RepoPath = (Resolve-Path $RepoPath).Path

# Start-Process joins -ArgumentList with spaces and quotes nothing itself, so
# arguments containing spaces must be quoted here.
function ConvertTo-ArgumentString {
    param([string[]]$Arguments)
    $quoted = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') { '"' + ($argument -replace '"', '\"') + '"' } else { $argument }
    }
    return ($quoted -join ' ')
}

function Invoke-Gh {
    <#
        Calls the GitHub API through gh and returns the parsed response.
        Retries transient failures, and reports the API's own error message.
    #>
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body,
        [int]$MaxAttempts = 4
    )

    $arguments = @('api', '--method', $Method, $Path, '-H', 'Accept: application/vnd.github+json')
    $tempFile = $null

    if ($null -ne $Body) {
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ghbody-" + [guid]::NewGuid().ToString('N') + ".json")
        $json = $Body | ConvertTo-Json -Depth 40 -Compress
        [System.IO.File]::WriteAllText($tempFile, $json, [System.Text.UTF8Encoding]::new($false))
        $arguments += @('--input', $tempFile)
    }

    try {
        $attempt = 0
        while ($true) {
            $attempt++
            # Output is captured through files rather than a pipeline so that the
            # API's error message survives, and binary/UTF-8 content is untouched.
            $outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ghout-" + [guid]::NewGuid().ToString('N') + ".json")
            $errFile = "$outFile.err"

            try {
                $process = Start-Process -FilePath 'gh' -ArgumentList (ConvertTo-ArgumentString $arguments) `
                    -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput $outFile -RedirectStandardError $errFile

                $stdout = if (Test-Path $outFile) { [System.IO.File]::ReadAllText($outFile) } else { '' }
                $stderr = if (Test-Path $errFile) { [System.IO.File]::ReadAllText($errFile) } else { '' }
            } finally {
                Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
            }

            if ($process.ExitCode -eq 0) {
                if ([string]::IsNullOrWhiteSpace($stdout)) { return $null }
                return ($stdout | ConvertFrom-Json)
            }

            $detail = if ($stderr.Trim()) { $stderr.Trim() } else { $stdout.Trim() }
            $transient = $detail -match 'HTTP (429|5\d\d)|timeout|timed out|connection|EOF|temporarily'

            if ($transient -and $attempt -lt $MaxAttempts) {
                $wait = [math]::Pow(2, $attempt)
                Write-Warning "gh api $Method $Path failed (attempt $attempt/$MaxAttempts); retrying in ${wait}s: $detail"
                Start-Sleep -Seconds $wait
                continue
            }

            throw "gh api $Method $Path failed (exit $($process.ExitCode)): $detail"
        }
    } finally {
        if ($tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

# --------------------------------------------------------------------------
# Resolve the target repository
# --------------------------------------------------------------------------

if (-not $Repo) {
    $remoteUrl = (& git -C $RepoPath remote get-url origin 2>$null)
    if ($remoteUrl -match 'github\.com[:/](?<owner>[^/]+)/(?<name>[^/]+?)(\.git)?$') {
        $Repo = "$($Matches['owner'])/$($Matches['name'])"
    } else {
        Die 'cannot infer the target repository; pass -Repo owner/name'
    }
}
Write-Step "Target: $Repo"
Write-Step "Source: $RepoPath"

# --------------------------------------------------------------------------
# Collect the files to publish, straight from the local commit
# --------------------------------------------------------------------------

$treeOutput = & git -C $RepoPath ls-tree -r -z HEAD
if ($LASTEXITCODE -ne 0) { Die 'cannot read HEAD; is the repository committed?' }

$entries = @()
foreach ($record in ($treeOutput -split "`0")) {
    if (-not $record) { continue }
    # "<mode> <type> <sha>`t<path>"
    $match = [regex]::Match($record, '^(?<mode>\d+) (?<type>\w+) (?<sha>[0-9a-f]+)\t(?<path>.+)$')
    if (-not $match.Success) { continue }
    $entries += [pscustomobject]@{
        Mode = $match.Groups['mode'].Value
        Sha  = $match.Groups['sha'].Value
        Path = $match.Groups['path'].Value
    }
}

if ($entries.Count -eq 0) { Die 'HEAD contains no files' }
Write-Step "Files to publish: $($entries.Count)"

if (-not $CommitMessage) {
    $CommitMessage = (& git -C $RepoPath log -1 --pretty=%B HEAD) -join "`n"
    $CommitMessage = $CommitMessage.Trim()
}
if (-not $CommitMessage) { $CommitMessage = 'chore: publish the repository' }

$authorName = (& git -C $RepoPath log -1 --pretty=%an HEAD).Trim()
$authorEmail = (& git -C $RepoPath log -1 --pretty=%ae HEAD).Trim()
$commitTitle = ($CommitMessage -split "`n")[0]

Write-Step 'Commit'
Write-Detail "title  : $commitTitle"
Write-Detail "author : $authorName <$authorEmail>"

if ($DryRun) {
    Write-Host ''
    Write-Step 'Dry run: nothing was uploaded. Files that would be created:'
    foreach ($entry in $entries) { Write-Detail "$($entry.Mode) $($entry.Path)" }
    exit 0
}

# --------------------------------------------------------------------------
# Initialise an empty repository
#
# GitHub refuses every other call with HTTP 409 "Git Repository is empty" until
# the repository holds a commit, so an empty repository is seeded with one real
# file through the Contents API. The full tree is committed on top of it below.
# --------------------------------------------------------------------------

$branchRef = $null
try {
    $branchRef = Invoke-Gh -Method GET -Path "/repos/$Repo/git/ref/heads/$Branch"
} catch {
    $branchRef = $null
}

if (-not $branchRef) {
    Write-Step 'Repository is empty; seeding an initial commit'
    $seed = $entries | Where-Object { $_.Path -eq 'README.md' } | Select-Object -First 1
    if (-not $seed) { $seed = $entries[0] }

    $seedTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("ghseed-" + [guid]::NewGuid().ToString('N') + ".bin")
    try {
        $process = Start-Process -FilePath 'git' -ArgumentList @('-C', "`"$RepoPath`"", 'cat-file', 'blob', $seed.Sha) `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $seedTemp
        if ($process.ExitCode -ne 0) { Die "cannot read blob for $($seed.Path)" }

        $seedBody = @{
            message = "chore: initialise the repository`n`nPlaceholder commit so the Git data API can be used; replaced by the next commit."
            content = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($seedTemp))
            branch  = $Branch
        }
        $put = Invoke-Gh -Method PUT -Path "/repos/$Repo/contents/$($seed.Path)" -Body $seedBody
        if (-not $put -or -not $put.commit) { Die 'could not seed the initial commit' }
        Write-Detail "seed commit $($put.commit.sha)"
    } finally {
        Remove-Item $seedTemp -Force -ErrorAction SilentlyContinue
    }

    $branchRef = Invoke-Gh -Method GET -Path "/repos/$Repo/git/ref/heads/$Branch"
}

if ($branchRef) {
    if ($branchRef.object.sha -and -not $Force -and -not $Parent) {
        Write-Note "branch '$Branch' is at $($branchRef.object.sha); the new commit will be its child"
    }
    if (-not $branchRef.object.sha -and -not $Force) {
        Die "branch '$Branch' exists but has no commit; re-run with -Force"
    }
}

# --------------------------------------------------------------------------
# Upload blobs
# --------------------------------------------------------------------------

Write-Step 'Uploading blobs'
$treeItems = @()
$index = 0

foreach ($entry in $entries) {
    $index++
    # Ask git for the raw bytes of the file as committed, so that line-ending
    # normalisation and encoding are identical to the local commit. Redirected
    # through Start-Process because a pipeline would corrupt binary content.
    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ghblob-" + [guid]::NewGuid().ToString('N') + ".bin")

    try {
        $process = Start-Process -FilePath 'git' -ArgumentList @('-C', "`"$RepoPath`"", 'cat-file', 'blob', $entry.Sha) `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tempFile
        if ($process.ExitCode -ne 0) { Die "cannot read blob for $($entry.Path)" }

        $blobBytes = [System.IO.File]::ReadAllBytes($tempFile)
        $content = [Convert]::ToBase64String($blobBytes)

        $blob = Invoke-Gh -Method POST -Path "/repos/$Repo/git/blobs" -Body @{
            content  = $content
            encoding = 'base64'
        }
        if (-not $blob -or -not $blob.sha) { Die "blob upload failed for $($entry.Path)" }

        $treeItems += @{
            path = $entry.Path
            mode = if ($entry.Mode -eq '100755') { '100755' } else { '100644' }
            type = 'blob'
            sha  = $blob.sha
        }
        Write-Detail "[$index/$($entries.Count)] $($entry.Path)"
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------------------------------------
# Build the tree, the commit, and move the ref
# --------------------------------------------------------------------------

Write-Step 'Creating the tree'
$tree = Invoke-Gh -Method POST -Path "/repos/$Repo/git/trees" -Body @{ tree = $treeItems }
if (-not $tree -or -not $tree.sha) { Die 'tree creation failed' }
Write-Detail "tree $($tree.sha)"

# The parent keeps the published history linear with what is already on the
# remote, so this is a normal follow-up commit rather than a history rewrite.
$parentSha = $null
if ($Parent -eq 'none') {
    Write-Note 'creating a root commit on request'
} elseif ($Parent) {
    $parentSha = $Parent
} elseif ($branchRef -and $branchRef.object.sha) {
    $parentSha = $branchRef.object.sha
}

$commitBody = @{
    message = $CommitMessage
    tree    = $tree.sha
    parents = @()
}
if ($parentSha) {
    $commitBody.parents = @($parentSha)
    Write-Detail "parent $parentSha"
}

Write-Step 'Creating the commit'
$commit = Invoke-Gh -Method POST -Path "/repos/$Repo/git/commits" -Body $commitBody
if (-not $commit -or -not $commit.sha) { Die 'commit creation failed' }
Write-Detail "commit $($commit.sha)"

Write-Step "Moving refs/heads/$Branch"
$null = Invoke-Gh -Method PATCH -Path "/repos/$Repo/git/refs/heads/$Branch" -Body @{
    sha   = $commit.sha
    force = $true
}

Write-Host ''
Write-Step 'Published'
Write-Host "    commit   https://github.com/$Repo/commit/$($commit.sha)"
Write-Host "    repo     https://github.com/$Repo"
exit 0
