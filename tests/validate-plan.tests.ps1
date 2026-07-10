$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $repoRoot "scripts/validate-plan.ps1"
$fixtureRoot = Join-Path $PSScriptRoot "fixtures/plan-metadata"
$schemaPath = Join-Path $repoRoot "schemas/plan-meta.schema.json"

if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    throw "Missing metadata schema: $schemaPath"
}

try {
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
} catch {
    throw "Metadata schema is not valid JSON: $($_.Exception.Message)"
}

foreach ($requiredField in @("schema_version", "plan_path", "goal", "complexity_tier", "phases", "semantic_risks", "success_criteria")) {
    if ($schema.required -notcontains $requiredField) {
        throw "Metadata schema does not require '$requiredField'"
    }
}

function Invoke-MetadataValidator(
    [string]$PlanPath,
    [string]$ValidationRoot = $fixtureRoot
) {
    $global:LASTEXITCODE = 0
    $caughtError = $null
    try {
        $output = @(& $validatorPath -RepoRoot $ValidationRoot -PlanPath $PlanPath -RequirePlanMetadata 2>&1)
    } catch {
        $caughtError = $_
        $output = @($_)
    }

    return [pscustomobject]@{
        Succeeded = ($null -eq $caughtError -and $LASTEXITCODE -eq 0)
        Output    = $output
    }
}

function Assert-ValidatorSucceeds([string]$PlanPath) {
    $result = Invoke-MetadataValidator $PlanPath
    if (-not $result.Succeeded) {
        throw "Expected metadata validation to succeed for '$PlanPath', but it failed: $($result.Output -join [Environment]::NewLine)"
    }
}

function Assert-ValidatorFails(
    [string]$PlanPath,
    [string]$Label,
    [string]$ValidationRoot = $fixtureRoot
) {
    $result = Invoke-MetadataValidator $PlanPath $ValidationRoot
    if ($result.Succeeded) {
        throw "Expected metadata validation to fail for '$Label', but it succeeded: $($result.Output -join [Environment]::NewLine)"
    }
}

function Assert-MutatedMetadataFails([string]$Label, [scriptblock]$Mutation) {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-plan-metadata-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "plans") -Destination $temporaryRoot -Recurse

        $metadataPath = Join-Path $temporaryRoot "plans/artifacts/valid-metadata/plan.meta.json"
        & $Mutation $metadataPath
        Assert-ValidatorFails "plans/valid-metadata-plan.md" $Label $temporaryRoot
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

function Assert-MutatedVerdictFails([string]$Label, [scriptblock]$Mutation) {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-plan-verdict-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "plans") -Destination $temporaryRoot -Recurse

        $verdictPath = Join-Path $temporaryRoot "plans/artifacts/valid-metadata/verify-verdict.md"
        & $Mutation $verdictPath

        $global:LASTEXITCODE = 0
        $caughtError = $null
        try {
            $output = @(& $validatorPath -RepoRoot $temporaryRoot -PlanPath "plans/valid-metadata-plan.md" -RequirePlanMetadata -RequireVerifyVerdict 2>&1)
        } catch {
            $caughtError = $_
            $output = @($_)
        }

        if ($null -eq $caughtError -and $LASTEXITCODE -eq 0) {
            throw "Expected metadata validation to reject '$Label', but it succeeded: $($output -join [Environment]::NewLine)"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

function Assert-RepositoryPlanSucceeds([string]$PlanPath) {
    $global:LASTEXITCODE = 0
    $caughtError = $null
    try {
        $output = @(& $validatorPath -RepoRoot $repoRoot -PlanPath $PlanPath -RequirePlanMetadata -RequireVerifyVerdict 2>&1)
    } catch {
        $caughtError = $_
        $output = @($_)
    }

    if ($null -ne $caughtError -or $LASTEXITCODE -ne 0) {
        throw "Expected repository plan validation to succeed for '$PlanPath', but it failed: $($output -join [Environment]::NewLine)"
    }
}

function Assert-FixtureVerdictFails([string]$Label) {
    $global:LASTEXITCODE = 0
    $caughtError = $null
    try {
        $output = @(& $validatorPath -RepoRoot $fixtureRoot -PlanPath "plans/valid-metadata-plan.md" -RequirePlanMetadata -RequireVerifyVerdict 2>&1)
    } catch {
        $caughtError = $_
        $output = @($_)
    }

    if ($null -eq $caughtError -and $LASTEXITCODE -eq 0) {
        throw "Expected metadata validation to reject '$Label', but it succeeded: $($output -join [Environment]::NewLine)"
    }
}

Assert-ValidatorSucceeds "plans/valid-metadata-plan.md"
Assert-ValidatorFails "plans/invalid-metadata-plan.md" "unknown phase dependency"
Assert-FixtureVerdictFails "a verdict without score and revision sections"
Assert-MutatedMetadataFails "an empty metadata goal" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.goal = ""
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedMetadataFails "malformed metadata JSON" {
    param($metadataPath)
    Set-Content -LiteralPath $metadataPath -Value "{" -Encoding UTF8
}
Assert-MutatedMetadataFails "a metadata tier that differs from Markdown" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.complexity_tier = "MEDIUM"
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedVerdictFails "a score dimension without an assessment" {
    param($verdictPath)
    @'
# ControlFlow Verify Verdict

**Status:** APPROVED

## Findings

- Fixture finding.

## Score Breakdown

| Dimension | Score | Rationale |
| --- | --- | --- |
| completeness | 90/100 | Complete. |
| executability | 90/100 | Runnable. |
| dependency sanity |  | Missing assessment. |
| evidence readiness | 90/100 | Available. |
| risk handling | 90/100 | Covered. |

## Revision Patch Instructions

- None required.

## Evidence

- Fixture evidence.

## Recommendation

Proceed.
'@ | Set-Content -LiteralPath $verdictPath -Encoding UTF8
}
Assert-MutatedVerdictFails "empty revision patch instructions" {
    param($verdictPath)
    @'
# ControlFlow Verify Verdict

**Status:** APPROVED

## Findings

- Fixture finding.

## Score Breakdown

| Dimension | Score | Rationale |
| --- | --- | --- |
| completeness | 90/100 | Complete. |
| executability | 90/100 | Runnable. |
| dependency sanity | 90/100 | Sound. |
| evidence readiness | 90/100 | Available. |
| risk handling | 90/100 | Covered. |

## Revision Patch Instructions

## Evidence

- Fixture evidence.

## Recommendation

Proceed.
'@ | Set-Content -LiteralPath $verdictPath -Encoding UTF8
}

foreach ($planPath in @(
    "plans/plan-contract-foundation-plan.md",
    "plans/examples/bugfix-plan.md",
    "plans/examples/refactor-plan.md",
    "plans/examples/migration-plan.md",
    "plans/examples/feature-plan.md",
    "plans/examples/docs-test-only-plan.md"
)) {
    Assert-RepositoryPlanSucceeds $planPath
}

Write-Output "VALID metadata validation contract"
