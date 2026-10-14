#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Create the DDB-skillhub repository and push the current branch to it.

.DESCRIPTION
    GitHub has no API for creating an organization, so the organization must
    exist before this script runs. Everything after that is automated: create
    the public repository, set the description and topics, push main, and print
    the resulting URLs.

    Requires the GitHub CLI to be installed and authenticated, with the 'repo'
    scope, which `gh auth status` reports.

.EXAMPLE
    ./tools/create-repo.ps1 -Owner Didib-Lab

.EXAMPLE
    ./tools/create-repo.ps1 -Owner Didib-Lab -RepoName didib-skillhub
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = 'Organization or user that will own the repository.')]
    [string]$Owner,

    [string]$RepoName = 'didib-skillhub',

    [string]$Branch = 'main',

    [string]$Description = 'Community hub of agent skills. Anyone can publish a skill by pull request; anyone can install one with a single command.',

    [string[]]$Topics = @('agent-skills', 'skills', 'ai-agents', 'skillhub', 'awesome-list')
)

$ErrorActionPreference = 'Continue'
$repo = "$Owner/$RepoName"

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Detail { param([string]$Message) Write-Host "    $Message" }
function Die { param([string]$Message) [Console]::Error.WriteLine("error: $Message"); exit 1 }

# Start-Process joins -ArgumentList with spaces and performs no quoting of its
# own, so arguments containing spaces must be quoted here or the child process
# receives them as separate arguments.
function ConvertTo-ArgumentString {
    param([string[]]$Arguments)
    $quoted = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
        } else {
            $argument
        }
    }
    return ($quoted -join ' ')
}

# Runs a command and captures its stdout and exit code. gh writes diagnostics to
# stderr for the expected "does not exist" cases, and under
# $ErrorActionPreference = 'Stop' that would abort the script, so native calls
# are made through Start-Process and judged by their exit code instead.
function Invoke-Capture {
    param([string]$File, [string[]]$Arguments)
    $out = Join-Path ([System.IO.Path]::GetTempPath()) ("ghout-" + [guid]::NewGuid().ToString('N'))
    $err = "$out.err"
    $process = Start-Process -FilePath $File -ArgumentList (ConvertTo-ArgumentString $Arguments) `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $stdout = if (Test-Path $out) { (Get-Content $out -Raw) } else { '' }
    $stderr = if (Test-Path $err) { (Get-Content $err -Raw) } else { '' }
    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = "$stdout".Trim()
        StdErr   = "$stderr".Trim()
    }
}

# --- Preconditions ---------------------------------------------------------

Write-Step 'Checking the GitHub CLI'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Die 'the GitHub CLI (gh) is not installed; see https://cli.github.com'
}

if ((Invoke-Capture gh @('auth', 'status')).ExitCode -ne 0) {
    Die "gh is not authenticated; run 'gh auth login'"
}

Write-Step "Checking that the owner '$Owner' is reachable"
$ownerProbe = Invoke-Capture gh @('api', "/users/$Owner", '--jq', '.type')
if ($ownerProbe.ExitCode -ne 0) {
    Die "cannot resolve '$Owner'. If this is a new organization, create it first at https://github.com/organizations/plan"
}
$ownerType = $ownerProbe.StdOut

if ($ownerType -eq 'Organization') {
    if ((Invoke-Capture gh @('api', "/orgs/$Owner", '--jq', '.login')).ExitCode -ne 0) {
        Die "no access to the organization '$Owner'. Check that you are a member with permission to create repositories."
    }
    Write-Detail 'owner is an organization'
} else {
    Write-Detail 'owner is a user account'
}

Write-Step "Checking whether $repo already exists"
if ((Invoke-Capture gh @('repo', 'view', $repo)).ExitCode -eq 0) {
    Die "$repo already exists. To push into it, run: git remote add origin https://github.com/$repo.git; git push -u origin $Branch"
}

# --- Create and push -------------------------------------------------------

Write-Step "Creating $repo as a public repository"
$create = Invoke-Capture gh @('repo', 'create', $repo, '--public', '--description', $Description)
if ($create.ExitCode -ne 0) {
    Die "repository creation failed: $($create.StdErr)"
}

Write-Step 'Setting topics'
foreach ($topic in $Topics) {
    Invoke-Capture gh @('repo', 'edit', $repo, '--add-topic', $topic) | Out-Null
}

Write-Step 'Configuring the remote'
$existing = @(git remote 2>$null)
if ($existing -contains 'origin') {
    git remote set-url origin "https://github.com/$repo.git"
} else {
    git remote add origin "https://github.com/$repo.git"
}

Write-Step "Pushing $Branch"
git push -u origin $Branch
if ($LASTEXITCODE -ne 0) { Die 'push failed' }

# --- Report ----------------------------------------------------------------

Write-Host ''
Write-Step 'Done'
Write-Host "    repository   https://github.com/$repo"
Write-Host "    actions      https://github.com/$repo/actions"
Write-Host "    new issue    https://github.com/$repo/issues/new/choose"
Write-Host "    settings     https://github.com/$repo/settings"
Write-Host ''
Write-Host 'Recommended next steps in the web UI:'
Write-Host '  1. Settings -> General -> Features: enable Discussions for skill ideas.'
Write-Host '  2. Settings -> Branches: protect main, require the "Validate skills" check.'
Write-Host '  3. Settings -> General -> Danger Zone: confirm the default branch is main.'
