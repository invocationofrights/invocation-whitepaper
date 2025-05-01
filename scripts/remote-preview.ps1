<#
.SYNOPSIS
    Push current WIP to a throw-away preview branch,
    wait for GitHub Actions to build the PDF, download it, and open it.
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

# 3. Locate GitHub CLI (adjust path if you installed somewhere custom)
$gh = "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe"

# 4. Poll for the workflow run ID (Actions can take a few seconds to register)
$runId = $null
for ($i = 0; $i -lt 15; $i++) {      # 8 × 5 s = 40 s timeout
    $runId = & $gh run list `
               --workflow preview-build `
               --branch   $branch `
               --limit    1 `
               --json     databaseId `
               --jq       '.[0].databaseId' 2>$null
    if ($runId) { break }
    Start-Sleep 2
}

if (-not $runId) {
    Write-Error "No workflow run found for branch $branch after 30 s."
}

Write-Host "⏳ Waiting for run $runId ..."
& $gh run watch $runId

# 5. Confirm run succeeded
$runState = & $gh run view $runId --json conclusion --jq '.conclusion'
if ($runState -ne 'success') {
    Write-Error "Run ended with state: $runState"
}

# 6. Download artifact
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
New-Item -ItemType Directory build | Out-Null
& $gh run download $runId --name preview --dir build

# 7. Open the PDF
$fullPath = (Resolve-Path build\Invocation_of_Rights.pdf).Path
Start-Process $fullPath
Write-Host "🎉 Preview ready: $fullPath"
