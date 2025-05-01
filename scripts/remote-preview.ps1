<#
.SYNOPSIS
    Push current WIP to a throw-away preview branch,
    wait for GitHub Actions to build the PDF, download & open it,
    then restore your edits back onto the main branch.
#>

$ErrorActionPreference = 'Stop'

# ---- CONFIG ---------------------------------------------------------------
$mainBranch   = 'main'     # change if your default branch is 'master'
$cleanup      = $true      # set $false to keep the preview branch
$ghExe        = "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe"  # adjust if gh.exe lives elsewhere
# --------------------------------------------------------------------------

Set-Location -Path (git rev-parse --show-toplevel)

# Timestamp for unique naming
$ts     = (Get-Date -Format 'yyyyMMddHHmmss')
$branch = "preview/$ts"

# Wrap everything so cleanup always runs
try {
    # 1. Stash current WIP (incl. untracked files)
    git stash push -u -k -m "preview-$ts"

    # 2. Create preview branch & re-apply edits
    git switch -c $branch
    git stash pop

    # 3. Commit edits on preview branch
    git add -A
    git commit -m "Remote preview $ts" --no-verify
    $commitSha = git rev-parse --short HEAD

    # 4. Push to origin
    git push -u origin $branch --no-verify

    # 5. Poll for new workflow run ID
    $runId = $null
    for ($i = 0; $i -lt 8; $i++) {
        $runId = & $ghExe run list --workflow preview-build `
                                    --branch $branch --limit 1 `
                                    --json databaseId `
                                    --jq '.[0].databaseId' 2>$null
        if ($runId) { break }
        Start-Sleep 5
    }
    if (-not $runId) { throw "No workflow run appeared for $branch within 40 s." }

    Write-Host "⏳ Waiting for run $runId ..."
    & $ghExe run watch $runId

    # 6. Fail fast if CI failed
    $state = & $ghExe run view $runId --json conclusion --jq '.conclusion'
    if ($state -ne 'success') { throw "Run ended with state: $state" }

    # 7. Download PDF artifact
    Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
    New-Item -ItemType Directory build | Out-Null
    & $ghExe run download $runId --name preview --dir build

    $pdfPath = (Resolve-Path build\Invocation_of_Rights.pdf).Path
    Start-Process $pdfPath
    Write-Host "`n🎉 Preview ready: $pdfPath`n"
}
finally {
    if ($cleanup) {
        Write-Host "🧹 Restoring edits to $mainBranch and cleaning up …"

        # Restore edits onto main (in case stash pop failed earlier)
        git switch $mainBranch
        git stash pop   2>$null  | Out-Null

        # Delete preview branch locally & remotely
        git branch -D $branch   2>$null  | Out-Null
        git push origin --delete $branch 2>$null  | Out-Null

        Write-Host "✅ Back on $mainBranch; preview branch removed."
    } else {
        Write-Host "⚠️  Preview branch kept: $branch"
    }
}
