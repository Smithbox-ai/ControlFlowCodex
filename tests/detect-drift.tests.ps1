$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$driftScript = Join-Path $repoRoot "scripts/detect-drift.ps1"

if (-not (Test-Path -LiteralPath $driftScript -PathType Leaf)) {
    throw "Missing drift detector script: $driftScript"
}

function Invoke-Drift([string]$Root, [string]$PlanPath, [string]$BaseCommit, [string]$HeadCommit) {
    $global:LASTEXITCODE = 0
    $params = @{
        RepoRoot = $Root
        PlanPath = $PlanPath
    }
    if (-not [string]::IsNullOrWhiteSpace($BaseCommit)) {
        $params["BaseCommit"] = $BaseCommit
    }
    if (-not [string]::IsNullOrWhiteSpace($HeadCommit)) {
        $params["HeadCommit"] = $HeadCommit
    }
    $output = @(& $driftScript @params 2>&1)
    $exitCode = $global:LASTEXITCODE
    if ($output.Count -ne 1) {
        throw "detect-drift must emit one JSON object for '$PlanPath', got $($output.Count) output records"
    }
    try {
        $json = ($output -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw "detect-drift output is not valid JSON for '$PlanPath': $($_.Exception.Message)"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Json = $json
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-drift-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $previousLocation = Get-Location
    Set-Location $tempRoot
    try {
        $global:LASTEXITCODE = 0
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        git init -q 2>&1 | Out-Null
        git config user.email "test@test.com" 2>&1 | Out-Null
        git config user.name "Test" 2>&1 | Out-Null
        $ErrorActionPreference = $prevPref
    } finally {
        Set-Location $previousLocation
    }

    New-Item -ItemType Directory -Path (Join-Path $tempRoot "plans/artifacts/test-task") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot "src") -Force | Out-Null

    $plannedFiles = @("src/main.ps1", "src/helper.ps1", "README.md")
    foreach ($file in $plannedFiles) {
        $fullPath = Join-Path $tempRoot $file
        $dir = Split-Path $fullPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $fullPath -Value "initial content" -Encoding UTF8
    }
    $metadata = [ordered]@{
        schema_version = "1.0.0"
        plan_path = "plans/test-task-plan.md"
        goal = "Test drift detection"
        complexity_tier = "SMALL"
        phases = @(
            [ordered]@{
                id = "1"
                objective = "Implement changes"
                dependencies = @()
                files = @("src/main.ps1", "src/helper.ps1", "README.md")
                commands = @("pwsh -File tests/test.ps1")
                success_criteria = @("All tests pass")
            }
        )
        semantic_risks = @(
            [ordered]@{ category = "data_volume"; applicability = "not_applicable"; impact = "LOW" }
            [ordered]@{ category = "performance"; applicability = "not_applicable"; impact = "LOW" }
            [ordered]@{ category = "concurrency"; applicability = "not_applicable"; impact = "LOW" }
            [ordered]@{ category = "access_control"; applicability = "not_applicable"; impact = "LOW" }
            [ordered]@{ category = "migration_rollback"; applicability = "not_applicable"; impact = "LOW" }
            [ordered]@{ category = "dependency"; applicability = "not_applicable"; impact = "LOW" }
            [ordered]@{ category = "operability"; applicability = "applicable"; impact = "LOW" }
        )
        success_criteria = @("All tests pass")
    }
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempRoot "plans/artifacts/test-task/plan.meta.json") -Encoding UTF8
    $planContent = @'
# Plan: Test Task

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** SMALL
**Confidence:** 0.90
**Abstain:** false
**Summary:** Test plan for drift detection.

## Context & Analysis

Goal Statement: Test drift detection

## Design Decisions

- Test decision.

## Implementation Phases

### Phase 1 - Implementation

Objective: Implement changes
Executor: Editor
Wave: 1
Dependencies: none

## Inter-Phase Contracts

- None.

## Open Questions

- None.

## Risks

- None.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | N/A | N/A |
| performance | not_applicable | LOW | N/A | N/A |
| concurrency | not_applicable | LOW | N/A | N/A |
| access_control | not_applicable | LOW | N/A | N/A |
| migration_rollback | not_applicable | LOW | N/A | N/A |
| dependency | not_applicable | LOW | N/A | N/A |
| operability | applicable | LOW | N/A | N/A |

## Success Criteria

- All tests pass.

## Handoff

Saved plan path: plans/test-task-plan.md

## Notes for Execution

- Test plan.

## Progress

- Phase 1 completed.

## Discoveries

- None.

## Decision Log

- None.

## Outcomes

- None.

## Idempotence & Recovery

- None.
'@
    Set-Content -LiteralPath (Join-Path $tempRoot "plans/test-task-plan.md") -Value $planContent -Encoding UTF8
    $previousLocation = Get-Location
    Set-Location $tempRoot
    try {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        git add -A 2>&1 | Out-Null
        git commit -q -m "initial" 2>&1 | Out-Null
        $baseCommit = (git rev-parse HEAD 2>&1).Trim()
        $ErrorActionPreference = $prevPref
    } finally {
        Set-Location $previousLocation
    }

    Set-Content -LiteralPath (Join-Path $tempRoot "src/main.ps1") -Value "modified content" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tempRoot "README.md") -Value "modified readme" -Encoding UTF8
    $unplannedPath = Join-Path $tempRoot "src/unplanned.ps1"
    Set-Content -LiteralPath $unplannedPath -Value "unplanned file" -Encoding UTF8

    $previousLocation = Get-Location
    Set-Location $tempRoot
    try {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        git add -A 2>&1 | Out-Null
        git commit -q -m "changes" 2>&1 | Out-Null
        $headCommit = (git rev-parse HEAD 2>&1).Trim()
        $ErrorActionPreference = $prevPref
    } finally {
        Set-Location $previousLocation
    }

    $result = Invoke-Drift $tempRoot "plans/test-task-plan.md" $baseCommit $headCommit
    if ($result.ExitCode -ne 0) {
        throw "Expected drift detection to succeed, got exit code $($result.ExitCode)"
    }
    if ($result.Json.verdict -ne "DRIFT_DETECTED") {
        throw "Expected verdict 'DRIFT_DETECTED', got '$($result.Json.verdict)'"
    }
    if ($result.Json.changed_file_count -ne 3) {
        throw "Expected 3 changed files, got $($result.Json.changed_file_count)"
    }
    if ($result.Json.summary.approved_follow_through -ne 2) {
        throw "Expected 2 approved follow-through, got $($result.Json.summary.approved_follow_through)"
    }
    if ($result.Json.summary.blocking_scope_drift -ne 1) {
        throw "Expected 1 blocking scope drift, got $($result.Json.summary.blocking_scope_drift)"
    }
    if ($result.Json.summary.planned_but_unchanged -ne 1) {
        throw "Expected 1 planned but unchanged, got $($result.Json.summary.planned_but_unchanged)"
    }

    $driftPaths = @($result.Json.classifications | Where-Object { $_.classification -eq "blocking_scope_drift" } | ForEach-Object { $_.path })
    if ($driftPaths -notcontains "src/unplanned.ps1") {
        throw "Expected src/unplanned.ps1 to be classified as blocking_scope_drift"
    }

    $approvedPaths = @($result.Json.classifications | Where-Object { $_.classification -eq "approved_follow_through" } | ForEach-Object { $_.path })
    if ($approvedPaths -notcontains "src/main.ps1" -or $approvedPaths -notcontains "README.md") {
        throw "Expected src/main.ps1 and README.md to be classified as approved_follow_through"
    }

    if ($result.Json.planned_but_unchanged -notcontains "src/helper.ps1") {
        throw "Expected src/helper.ps1 in planned_but_unchanged"
    }

    $cleanResult = Invoke-Drift $tempRoot "plans/test-task-plan.md" $headCommit $headCommit
    if ($cleanResult.Json.verdict -ne "CLEAN") {
        throw "Expected CLEAN verdict for no-op diff, got '$($cleanResult.Json.verdict)'"
    }

    $global:LASTEXITCODE = 0
    $errorOutput = @(& $driftScript -RepoRoot $tempRoot -PlanPath "plans/not-a-plan.txt" 2>&1)
    $errorExitCode = $global:LASTEXITCODE
    if ($errorExitCode -eq 0) {
        throw "detect-drift must reject an invalid plan path"
    }
    $errorJson = ($errorOutput -join [Environment]::NewLine) | ConvertFrom-Json
    if ($errorJson.verdict -ne "ERROR") {
        throw "Expected ERROR verdict for invalid plan path, got '$($errorJson.verdict)'"
    }
    $global:LASTEXITCODE = 0

} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "VALID drift detection contract"
