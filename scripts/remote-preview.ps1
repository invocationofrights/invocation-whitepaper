<#
.SYNOPSIS
    Push current WIP to a throw-away preview branch,
    wait for GitHub Actions to build the PDF, download and open it.
#>

$ErrorActionPreference = 'Stop'

# 0. Go to repo root (important when launched from IDE)
Set-Location -Path (git rev-parse --show-toplevel)

# 1. Create a unique preview branch
$ts     = (Get-Date -Format 'yyyyMMddHHmmss')
$branch = "preview/$ts"
git switch -c $branch
git add -A
git commit -m "Remote preview $ts" --no-verify

# 2. Push to origin
git push -u origin $branch --no-verify

# 3. Get the newest run ID for this branch & workflow
$run = gh run list --workflow preview-build --branch $branch --limit 1 --json databaseId,state --jq '.[0]'
$runId = $run.databaseId
Write-Host "⏳ Waiting for run $runId ..."
gh run watch $runId

if ($run.state -ne 'completed') {
    Write-Error "Run did not complete."
}

# 4. Download artifact
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
New-Item -ItemType Directory build | Out-Null
gh run download $runId --name preview --dir build

# 5. Open the PDF
$fullPath = (Resolve-Path build\Invocation_of_Rights.pdf).Path
Start-Process $fullPath
Write-Host "🎉 Preview ready: $fullPath"
