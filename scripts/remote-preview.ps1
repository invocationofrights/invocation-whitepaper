$ErrorActionPreference = 'Stop'

# ---------- CONFIG ---------------------------------------------------------
$mainBranch        = 'main'
$ghExe             = "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe"
$pollIntervalSec   = 5
$pollTimeoutSec    = 180
# --------------------------------------------------------------------------

Set-Location -Path (git rev-parse --show-toplevel)

$ts        = Get-Date -Format 'yyyyMMddHHmmss'
$branch    = "preview/$ts"
$stashRef  = ''
$previewSHA= ''
$workTreeDirty = (git status --porcelain).Length -gt 0

try {
    # 1. Stash edits (if any) and create preview branch
    if ($workTreeDirty) {
        Write-Host "Stashing edits ..."
        git stash push -u -k -m "preview-$ts" | Out-Null
        $stashRef = git stash list -n 1 --format=%gd
        Write-Host "Stashed edits as $stashRef"
    } else {
        Write-Host "No edits to stash."
    }

    git switch -c $branch
    if ($stashRef) { git stash apply $stashRef }

    # 2. Commit & push (allow-empty triggers CI even with no edits)
    git add -A
    git commit -m "Remote preview $ts" --allow-empty --no-verify
    $previewSHA = git rev-parse --short HEAD
    git push -q -u origin $branch --no-verify

    # 3. Wait for workflow run
    $maxAttempts = [math]::Ceiling($pollTimeoutSec / $pollIntervalSec)
    $runId = $null
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        $runId = & $ghExe run list --workflow preview-build --branch $branch `
                  --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null
        if ($runId) { break }
        Start-Sleep $pollIntervalSec
    }
    if (-not $runId) { throw "Timeout: no Actions run found for $branch." }

#    throw "Run ID: $runId"
    Write-Host "Waiting for run $runId ..."
    & $ghExe run watch $runId

    # 4. Ensure success & fetch artifact
    if ((& $ghExe run view $runId --json conclusion --jq '.conclusion') -ne 'success') {
        throw "CI run $runId failed."
    }
    Remove-Item -Recurse -Force build -EA SilentlyContinue
    New-Item -ItemType Directory build | Out-Null
    & $ghExe run download $runId --name preview --dir build
    $pdf = (Resolve-Path build\Invocation_of_Rights.pdf).Path
    Start-Process $pdf
    Write-Host "Preview ready at $pdf"
}
finally {
    Write-Host "Restoring edits and cleaning up."
    git switch $mainBranch

    # 1️⃣  Re-apply the stash entry, but keep it on the stack
    if ($stashRef) {
        try {
            git stash apply $stashRef
            if ($LASTEXITCODE -eq 0) {
                git stash drop $stashRef | Out-Null
            } else {
                Write-Warning "Stash apply had conflicts; entry kept as $stashRef."
            }
        } catch {
            Write-Warning "Could not apply $stashRef – resolve manually."
        }
    }

    # 2️⃣  Cherry-pick diff only if it has changes
    if ($previewSHA -and (git diff --quiet $previewSHA^ $previewSHA) -eq $false) {
        try { git cherry-pick -n $previewSHA }
        catch { Write-Warning "Cherry-pick of preview commit failed – resolve manually." }
    }

    # 3️⃣  Delete preview branch locally & remotely
    try { git branch -D $branch | Out-Null } catch { }
    try { git push -q origin --delete $branch >$null 2>&1 } catch { }

    Write-Host "Cleanup complete."
}

