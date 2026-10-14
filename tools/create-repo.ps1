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

$ErrorActionPreference = 'Stop'
$repo = "$Owner/$RepoName"

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Die { param([string]$Message) Write-Error $Message; exit 1 }

# --- Preconditions ---------------------------------------------------------

Write-Step 'Checking the GitHub CLI'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Die 'the GitHub CLI (gh) is not installed; see https://cli.github.com'
}

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Die "gh is not authenticated; run 'gh auth login'" }

Write-Step "Checking that the owner '$Owner' is reachable"
$ownerType = gh api "/users/$Owner" --jq '.type' 2>$null
if ($LASTEXITCODE -ne 0) {
    Die "cannot resolve '$Owner'. If this is a new organization, create it first at https://github.com/organizations/plan"
}

if ($ownerType -eq 'Organization') {
    $canCreate = gh api "/orgs/$Owner" --jq '.login' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Die "no access to the organization '$Owner'. Check that you are a member with permission to create repositories."
    }
    Write-Host "    owner is an organization"
} else {
    Write-Host "    owner is a user account"
}

Write-Step "Checking whether $repo already exists"
gh repo view $repo 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Die "$repo already exists. To push into it, run: git remote add origin https://github.com/$repo.git; git push -u origin $Branch"
}

# --- Create and push -------------------------------------------------------

Write-Step "Creating $repo as a public repository"
gh repo create $repo --public --description $Description
if ($LASTEXITCODE -ne 0) { Die "repository creation failed" }

Write-Step "Setting topics"
foreach ($topic in $Topics) {
    gh repo edit $repo --add-topic $topic 2>&1 | Out-Null
}

Write-Step "Configuring the remote"
$existing = git remote 2>$null
if ($existing -contains 'origin') {
    git remote set-url origin "https://github.com/$repo.git"
} else {
    git remote add origin "https://github.com/$repo.git"
}

Write-Step "Pushing $Branch"
git push -u origin $Branch
if ($LASTEXITCODE -ne 0) { Die "push failed" }

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
