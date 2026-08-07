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

foreach ($requiredField in @("schema_version", "goal", "tier", "baseline", "scope", "criteria", "checks")) {
    if ($schema.required -notcontains $requiredField) {
        throw "Metadata schema does not require '$requiredField'"
    }
}
if ($schema.properties.schema_version.const -cne "2.0.0") {
    throw "Metadata schema schema_version const must be '2.0.0'"
}

function Invoke-MetadataValidator(
    [string]$PlanPath,
    [string]$ValidationRoot = $fixtureRoot,
    [switch]$RequireVerifyVerdict
) {
    $global:LASTEXITCODE = 0
    $caughtError = $null
    try {
        if ($RequireVerifyVerdict) {
            $output = @(& $validatorPath -RepoRoot $ValidationRoot -PlanPath $PlanPath -RequirePlanMetadata -RequireVerifyVerdict 2>&1)
        } else {
            $output = @(& $validatorPath -RepoRoot $ValidationRoot -PlanPath $PlanPath -RequirePlanMetadata 2>&1)
        }
    } catch {
        $caughtError = $_
        $output = @($_)
    }

    return [pscustomobject]@{
        Succeeded = ($null -eq $caughtError -and $LASTEXITCODE -eq 0)
        Output    = $output
    }
}

function Assert-ValidatorSucceeds([string]$PlanPath, [string]$ValidationRoot = $fixtureRoot) {
    $result = Invoke-MetadataValidator $PlanPath $ValidationRoot
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
        $result = Invoke-MetadataValidator "plans/valid-metadata-plan.md" $temporaryRoot -RequireVerifyVerdict
        if ($result.Succeeded) {
            throw "Expected verdict validation to reject '$Label', but it succeeded: $($result.Output -join [Environment]::NewLine)"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

# Happy path: valid fixture passes with both metadata and verdict.
Assert-ValidatorSucceeds "plans/valid-metadata-plan.md"
$result = Invoke-MetadataValidator "plans/valid-metadata-plan.md" $fixtureRoot -RequireVerifyVerdict
if (-not $result.Succeeded) {
    throw "Expected valid fixture verdict to succeed: $($result.Output -join [Environment]::NewLine)"
}

# Invalid fixture (bad tier + empty scope) is rejected.
Assert-ValidatorFails "plans/invalid-metadata-plan.md" "invalid metadata (bad tier + empty scope)"

# Metadata mutations that must fail.
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
Assert-MutatedMetadataFails "a bad tier" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.tier = "HUGE"
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedMetadataFails "a missing baseline commit" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.baseline.PSObject.Properties.Remove("commit")
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedMetadataFails "an empty scope array" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.scope = @()
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedMetadataFails "an empty checks array" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.checks = @()
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedMetadataFails "a bad risk impact" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.risks.concurrency.impact = "EXTREME"
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedMetadataFails "an unknown top-level property" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata | Add-Member -NotePropertyName rogue -NotePropertyValue "no"
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedMetadataFails "a duplicate phase id" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $second = [pscustomobject]@{ id = "p1"; objective = "dup"; criteria = @("x") }
    $metadata.phases = @($metadata.phases[0], $second)
    $metadata.phases[1].id = "p1"
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}
Assert-MutatedMetadataFails "a wrong schema_version" {
    param($metadataPath)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.schema_version = "1.0.0"
    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
}

# Verdict mutations that must fail.
Assert-MutatedVerdictFails "a verdict without a Status line" {
    param($verdictPath)
@"
# ControlFlow Verify Verdict

## Findings

- Fixture finding.
"@ | Set-Content -LiteralPath $verdictPath -Encoding UTF8
}
Assert-MutatedVerdictFails "a verdict without a Findings section" {
    param($verdictPath)
@"
# ControlFlow Verify Verdict

Status: APPROVED

No findings section here.
"@ | Set-Content -LiteralPath $verdictPath -Encoding UTF8
}
Assert-MutatedVerdictFails "a verdict with an invalid status" {
    param($verdictPath)
@"
# ControlFlow Verify Verdict

Status: MAYBE

## Findings

- Fixture finding.
"@ | Set-Content -LiteralPath $verdictPath -Encoding UTF8
}

# Repository compact example validates end to end.
$repoResult = Invoke-MetadataValidator "plans/examples/auth-migration-plan.md" $repoRoot -RequireVerifyVerdict
if (-not $repoResult.Succeeded) {
    throw "Expected repository auth-migration example to validate: $($repoResult.Output -join [Environment]::NewLine)"
}

Write-Output "VALID metadata validation contract"
