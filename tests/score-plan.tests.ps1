$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scorerPath = Join-Path $repoRoot "scripts/score-plan.ps1"
$fixtureRoot = Join-Path $PSScriptRoot "fixtures/plan-metadata"
$metricNames = @(
    "completeness",
    "executability",
    "criteria_coverage",
    "dependency_sanity",
    "risk_coverage",
    "evidence_readiness"
)

function Invoke-ScorePlan([string]$Root, [string]$PlanPath) {
    if (-not (Test-Path -LiteralPath $scorerPath -PathType Leaf)) {
        throw "Missing score-plan script: $scorerPath"
    }

    $global:LASTEXITCODE = 0
    $output = @(& $scorerPath -RepoRoot $Root -PlanPath $PlanPath 2>&1)
    $exitCode = $global:LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "score-plan failed for '$PlanPath': $($output -join [Environment]::NewLine)"
    }
    if ($output.Count -ne 1) {
        throw "score-plan must emit one JSON object for '$PlanPath', got $($output.Count) output records"
    }

    try {
        return ($output -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw "score-plan output is not valid JSON for '$PlanPath': $($_.Exception.Message)"
    }
}

$positive = Invoke-ScorePlan $repoRoot "plans/examples/bugfix-plan.md"
if ($positive.verdict -ne "APPROVED") {
    throw "Expected approved golden score, got '$($positive.verdict)'"
}
if ($positive.aggregate_score -ne 100) {
    throw "Expected aggregate score 100, got '$($positive.aggregate_score)'"
}
foreach ($metric in $metricNames) {
    if ($null -eq $positive.metrics.PSObject.Properties[$metric]) {
        throw "Positive score output is missing metric '$metric'"
    }
    if ($positive.metrics.$metric -ne 100) {
        throw "Expected metric '$metric' to equal 100, got '$($positive.metrics.$metric)'"
    }
}

$missingPlanPath = "plans/missing-score-plan.md"
$global:LASTEXITCODE = 0
$errorOutput = @(& $scorerPath -RepoRoot $repoRoot -PlanPath $missingPlanPath 2>&1)
$errorExitCode = $global:LASTEXITCODE
if ($errorExitCode -eq 0) {
    throw "score-plan must reject a missing plan"
}
if ($errorOutput.Count -ne 1) {
    throw "score-plan must emit one error JSON object, got $($errorOutput.Count) output records"
}
$errorResult = ($errorOutput -join [Environment]::NewLine) | ConvertFrom-Json
if ($null -eq $errorResult.PSObject.Properties["plan_path"] -or
    $null -eq $errorResult.PSObject.Properties["task_slug"]) {
    throw "Error score output is missing stable path fields"
}
if ($errorResult.plan_path -ne $missingPlanPath -or $errorResult.verdict -ne "REJECTED") {
    throw "Missing plan must return its input path and a rejected verdict"
}
$global:LASTEXITCODE = 0

$invalid = Invoke-ScorePlan $fixtureRoot "plans/invalid-metadata-plan.md"
if ($invalid.metrics.dependency_sanity -ne 0) {
    throw "Expected invalid dependency score 0, got '$($invalid.metrics.dependency_sanity)'"
}
if ($invalid.verdict -eq "APPROVED") {
    throw "Invalid dependency fixture must not be approved"
}

$safetyRoot = Join-Path ([System.IO.Path]::GetTempPath()) "controlflow-score-plan-$([Guid]::NewGuid().ToString('N'))"
Copy-Item -LiteralPath $fixtureRoot -Destination $safetyRoot -Recurse
try {
    $metadataPath = Join-Path $safetyRoot "plans/artifacts/invalid-metadata/plan.meta.json"
    $markerPath = Join-Path $safetyRoot "declared-command-was-executed.txt"
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.phases[0].commands = @("New-Item -ItemType File -Path '$markerPath'")
    $metadata.phases += [pscustomobject]@{
        id = "2"
        objective = "Exercise missing command coverage."
        dependencies = @("1")
        files = @("scripts/validate-plan.ps1")
        commands = @()
        success_criteria = @("The scorer reports missing command coverage.")
    }
    $metadata.semantic_risks += [pscustomobject]@{
        category = "unsupported"
        applicability = "not_applicable"
        impact = "LOW"
    }
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath

    $safety = Invoke-ScorePlan $safetyRoot "plans/invalid-metadata-plan.md"
    if (Test-Path -LiteralPath $markerPath) {
        throw "score-plan executed a declared plan command"
    }
    if ($safety.metrics.executability -ne 25) {
        throw "Expected executability 25 for one missing command phase, got '$($safety.metrics.executability)'"
    }
    if ($safety.metrics.dependency_sanity -ne 0) {
        throw "Expected cyclic dependency score 0, got '$($safety.metrics.dependency_sanity)'"
    }
    if ($safety.metrics.risk_coverage -ne 0) {
        throw "Expected unsupported risk category score 0, got '$($safety.metrics.risk_coverage)'"
    }

    $metadata.phases[1].dependencies = @("2")
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath
    $selfDependency = Invoke-ScorePlan $safetyRoot "plans/invalid-metadata-plan.md"
    if ($selfDependency.metrics.dependency_sanity -ne 0) {
        throw "Expected self dependency score 0, got '$($selfDependency.metrics.dependency_sanity)'"
    }

    $metadata.phases[0].dependencies = "unknown"
    $metadata.phases[1].dependencies = @()
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath
    $malformedDependency = Invoke-ScorePlan $safetyRoot "plans/invalid-metadata-plan.md"
    if ($malformedDependency.metrics.dependency_sanity -ne 0) {
        throw "Expected malformed dependency score 0, got '$($malformedDependency.metrics.dependency_sanity)'"
    }

    $metadata.semantic_risks = @($metadata.semantic_risks | Where-Object { $_.category -ne "unsupported" })
    $metadata.semantic_risks[0].impact = "INVALID"
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath
    $malformedRisk = Invoke-ScorePlan $safetyRoot "plans/invalid-metadata-plan.md"
    if ($malformedRisk.metrics.risk_coverage -ne 0) {
        throw "Expected malformed risk score 0, got '$($malformedRisk.metrics.risk_coverage)'"
    }

    $planPath = Join-Path $safetyRoot "plans/invalid-metadata-plan.md"
    $planContent = Get-Content -LiteralPath $planPath -Raw
    $incompletePlan = $planContent -replace '(?ms)^## Design Decisions\s*$.*?(?=^## Implementation Phases\s*$)', ''
    if ($incompletePlan -match '(?m)^## Design Decisions\s*$') {
        throw "Test fixture did not remove the Design Decisions heading"
    }
    Set-Content -LiteralPath $planPath -Value $incompletePlan
    $incomplete = Invoke-ScorePlan $safetyRoot "plans/invalid-metadata-plan.md"
    if ($incomplete.metrics.completeness -ge 100) {
        throw "Expected missing Markdown contract section to reduce completeness"
    }
} finally {
    Remove-Item -LiteralPath $safetyRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "VALID score-plan contract"
