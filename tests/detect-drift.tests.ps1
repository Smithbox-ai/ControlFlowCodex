$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$driftScript = Join-Path $repoRoot "scripts/detect-drift.ps1"

if (-not (Test-Path -LiteralPath $driftScript -PathType Leaf)) {
    throw "Missing drift detector script: $driftScript"
}

function Invoke-Drift([string]$Root, [string]$PlanPath, [string]$BaseCommit) {
    $global:LASTEXITCODE = 0
    $params = @{ RepoRoot = $Root; PlanPath = $PlanPath }
    if (-not [string]::IsNullOrWhiteSpace($BaseCommit)) { $params["BaseCommit"] = $BaseCommit }
    $output = @(& $driftScript @params 2>&1)
    $exitCode = $global:LASTEXITCODE
    try {
        $json = ($output -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw "detect-drift output is not valid JSON for '$PlanPath': $($_.Exception.Message)"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Json = $json }
}

function Set-Metadata([string]$Root, [string]$BaseCommit, [string[]]$Scope, [switch]$WithBaseline) {
    $meta = [ordered]@{
        schema_version = "2.0.0"
        goal = "Test drift detection"
        tier = "SMALL"
        scope = $Scope
        criteria = @("All tests pass")
        checks = @("pwsh -File tests/test.ps1")
        risks = @{}
        phases = @()
    }
    if ($WithBaseline) {
        $meta["baseline"] = [ordered]@{ commit = $BaseCommit; dirty_paths = @() }
        # reorder so baseline sits after tier as in the canonical contract
        $ordered = [ordered]@{
            schema_version = $meta.schema_version
            goal = $meta.goal
            tier = $meta.tier
            baseline = $meta.baseline
            scope = $meta.scope
            criteria = $meta.criteria
            checks = $meta.checks
            risks = $meta.risks
            phases = $meta.phases
        }
        $meta = $ordered
    }
    $meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Root "plans/artifacts/test-task/plan.meta.json") -Encoding UTF8
}

function New-File([string]$Root, [string]$Rel, [string]$Content) {
    $full = Join-Path $Root $Rel
    $dir = Split-Path $full -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $full -Value $Content -Encoding UTF8
}

function Invoke-GitIn([string]$Root, [string[]]$GitArgs) {
    $prev = Get-Location
    Set-Location $Root
    try {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $global:LASTEXITCODE = 0
        & git @GitArgs 2>&1 | Out-Null
        $ErrorActionPreference = $prevPref
    } finally { Set-Location $prev }
}

function Get-Head([string]$Root) {
    $prev = Get-Location
    Set-Location $Root
    try {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $h = (git rev-parse HEAD 2>&1).Trim()
        $ErrorActionPreference = $prevPref
        return $h
    } finally { Set-Location $prev }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-drift-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Invoke-GitIn $tempRoot @("init", "-q")
    Invoke-GitIn $tempRoot @("config", "user.email", "test@test.com")
    Invoke-GitIn $tempRoot @("config", "user.name", "Test")

    New-Item -ItemType Directory -Path (Join-Path $tempRoot "plans/artifacts/test-task") -Force | Out-Null
    New-File $tempRoot "src/main.ps1" "initial"
    New-File $tempRoot "src/helper.ps1" "initial"
    New-File $tempRoot "README.md" "initial"
    New-File $tempRoot "plans/test-task-plan.md" "# Plan: Test Task"

    # Initial commit includes the plan artifacts so they are in the baseline tree.
    Set-Metadata $tempRoot "PENDING" @("src/main.ps1", "src/helper.ps1", "README.md", "plans/**") -WithBaseline
    Invoke-GitIn $tempRoot @("add", "-A")
    Invoke-GitIn $tempRoot @("commit", "-q", "-m", "c0: plan")
    $c0 = Get-Head $tempRoot

    # Finalize baseline.commit to c0 (creates a meta-only change at c1).
    Set-Metadata $tempRoot $c0 @("src/main.ps1", "src/helper.ps1", "README.md", "plans/**") -WithBaseline
    Invoke-GitIn $tempRoot @("add", "-A")
    Invoke-GitIn $tempRoot @("commit", "-q", "-m", "c1: set baseline")

    # Scenario A: committed implementation diff vs baseline in metadata.
    Set-Content -LiteralPath (Join-Path $tempRoot "src/main.ps1") -Value "modified" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tempRoot "README.md") -Value "modified readme" -Encoding UTF8
    New-File $tempRoot "src/unplanned.ps1" "unplanned"
    Invoke-GitIn $tempRoot @("add", "-A")
    Invoke-GitIn $tempRoot @("commit", "-q", "-m", "c2: impl")

    $result = Invoke-Drift $tempRoot "plans/test-task-plan.md"
    if ($result.ExitCode -ne 0) { throw "Scenario A: expected success, got exit $($result.ExitCode)" }
    if ($result.Json.verdict -ne "DRIFT_DETECTED") { throw "Scenario A: expected DRIFT_DETECTED, got '$($result.Json.verdict)'" }
    if ($result.Json.changed_file_count -ne 4) { throw "Scenario A: expected 4 changed, got $($result.Json.changed_file_count)" }
    if ($result.Json.summary.planned -ne 3) { throw "Scenario A: expected 3 planned, got $($result.Json.summary.planned)" }
    if ($result.Json.summary.unplanned -ne 1) { throw "Scenario A: expected 1 unplanned, got $($result.Json.summary.unplanned)" }
    $unplanned = @($result.Json.classifications | Where-Object { $_.classification -eq "unplanned" } | ForEach-Object { $_.path })
    if ($unplanned -notcontains "src/unplanned.ps1") { throw "Scenario A: src/unplanned.ps1 should be unplanned" }
    $planned = @($result.Json.classifications | Where-Object { $_.classification -eq "planned" } | ForEach-Object { $_.path })
    if ($planned -notcontains "src/main.ps1" -or $planned -notcontains "README.md") { throw "Scenario A: main.ps1 and README.md should be planned" }
    if ($planned -notcontains "plans/artifacts/test-task/plan.meta.json") { throw "Scenario A: plan.meta.json should be planned via plans/**" }
    if ($result.Json.scope_but_unmatched -notcontains "src/helper.ps1") { throw "Scenario A: src/helper.ps1 should be scope_but_unmatched" }

    # Scenario B: working-tree only (staged + unstaged + untracked), baseline at HEAD.
    $c2 = Get-Head $tempRoot
    Set-Metadata $tempRoot $c2 @("src/main.ps1", "plans/**") -WithBaseline
    New-File $tempRoot "src/staged.ps1" "staged"
    Invoke-GitIn $tempRoot @("add", "src/staged.ps1")
    New-File $tempRoot "src/untracked.ps1" "untracked"
    Set-Content -LiteralPath (Join-Path $tempRoot "src/main.ps1") -Value "modified again" -Encoding UTF8

    $wt = Invoke-Drift $tempRoot "plans/test-task-plan.md"
    if ($wt.ExitCode -ne 0) { throw "Scenario B: expected success, got exit $($wt.ExitCode)" }
    if ($wt.Json.verdict -ne "DRIFT_DETECTED") { throw "Scenario B: expected DRIFT_DETECTED, got '$($wt.Json.verdict)'" }
    $wtPaths = @($wt.Json.classifications | ForEach-Object { $_.path })
    if ($wtPaths -notcontains "src/staged.ps1") { throw "Scenario B: staged file not detected" }
    if ($wtPaths -notcontains "src/untracked.ps1") { throw "Scenario B: untracked file not detected" }
    if ($wtPaths -notcontains "src/main.ps1") { throw "Scenario B: unstaged modification not detected" }
    if ($wt.Json.summary.planned -ne 2) { throw "Scenario B: expected 2 planned (main + meta), got $($wt.Json.summary.planned)" }
    if ($wt.Json.summary.unplanned -ne 2) { throw "Scenario B: expected 2 unplanned (staged + untracked), got $($wt.Json.summary.unplanned)" }

    # Scenario C: CLEAN - no changes relative to baseline at HEAD (fallback path).
    Invoke-GitIn $tempRoot @("reset", "-q", "--hard", "HEAD")
    Set-Metadata $tempRoot "" @("src/**")
    Invoke-GitIn $tempRoot @("add", "-A")
    Invoke-GitIn $tempRoot @("commit", "-q", "-m", "c3: clean baseline")
    $clean = Invoke-Drift $tempRoot "plans/test-task-plan.md"
    if ($clean.Json.verdict -ne "CLEAN") { throw "Scenario C: expected CLEAN, got '$($clean.Json.verdict)'" }
    if ($clean.Json.changed_file_count -ne 0) { throw "Scenario C: expected 0 changed, got $($clean.Json.changed_file_count)" }

    # Scenario D: glob matching - src/** covers a nested untracked file -> planned -> CLEAN.
    New-File $tempRoot "src/deep/nested.ps1" "nested"
    $glob = Invoke-Drift $tempRoot "plans/test-task-plan.md"
    if ($glob.Json.verdict -ne "CLEAN") { throw "Scenario D: src/** should cover nested file, got '$($glob.Json.verdict)'" }
    if ($glob.Json.summary.planned -ne 1) { throw "Scenario D: expected 1 planned, got $($glob.Json.summary.planned)" }
    $nested = @($glob.Json.classifications | Where-Object { $_.path -eq "src/deep/nested.ps1" })
    if ($nested.Count -eq 0 -or $nested[0].classification -ne "planned") { throw "Scenario D: nested file should be planned" }

    # Scenario E: invalid plan path -> ERROR.
    $global:LASTEXITCODE = 0
    $errOut = @(& $driftScript -RepoRoot $tempRoot -PlanPath "plans/not-a-plan.txt" 2>&1)
    if ($LASTEXITCODE -eq 0) { throw "Scenario E: detect-drift must reject an invalid plan path" }
    $errJson = ($errOut -join [Environment]::NewLine) | ConvertFrom-Json
    if ($errJson.verdict -ne "ERROR") { throw "Scenario E: expected ERROR verdict, got '$($errJson.verdict)'" }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$global:LASTEXITCODE = 0
Write-Output "VALID drift detection contract"

