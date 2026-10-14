#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Publish the local commit to GitHub as a child of the remote branch tip.

.DESCRIPTION
    Wraps tools/push-via-api.ps1 for the common case: the local repository has
    commits that the remote does not, and git itself cannot push. The new commit
    is created on top of whatever the remote branch currently points at, so the
    published history stays linear and nothing already on the remote is lost.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'Didib-Lab/didib-skillhub',
    [string]$RepoPath,
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Continue'

if (-not $RepoPath) { $RepoPath = Split-Path -Parent $PSScriptRoot }
$RepoPath = (Resolve-Path $RepoPath).Path

# Reuse the local commit's message so the published commit matches what is here.
$message = (& git -C $RepoPath log -1 --pretty=%B HEAD) -join "`n"
$message = $message.Trim()
if (-not $message) { Write-Error 'no commit message found on HEAD'; exit 1 }

$remoteTip = (& gh api "/repos/$Repo/git/ref/heads/$Branch" --jq '.object.sha' 2>$null | Out-String).Trim()
if (-not $remoteTip) {
    Write-Host "no existing tip for $Branch; the commit will be a root commit"
} else {
    Write-Host "remote tip: $remoteTip"
}

# The pushed tree comes from the working tree, so make sure it is committed.
$dirty = & git -C $RepoPath status --porcelain
if ($dirty) {
    Write-Warning 'the working tree has uncommitted changes; they will not be published'
    $dirty | ForEach-Object { Write-Host "    $_" }
}

$arguments = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'push-via-api.ps1'),
    '-RepoPath', $RepoPath,
    '-Repo', $Repo,
    '-Branch', $Branch,
    '-CommitMessage', $message,
    '-Force'
)
if ($remoteTip) { $arguments += @('-Parent', $remoteTip) }

& powershell @arguments
exit $LASTEXITCODE
