$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $repoRoot "scripts/validate-revision.ps1"
$fixtureRoot = Join-Path $PSScriptRoot "fixtures/revision-request"

if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
    throw "Missing revision validator: $validatorPath"
}

function Invoke-RevisionValidator(
    [string]$PlanPath,
    [string]$ValidationRoot = $fixtureRoot
) {
    $global:LASTEXITCODE = 0
    $caughtError = $null
    try {
        $output = @(& $validatorPath -RepoRoot $ValidationRoot -PlanPath $PlanPath 2>&1)
    } catch {
        $caughtError = $_
        $output = @($_)
    }

    return [pscustomobject]@{
        Succeeded = ($null -eq $caughtError -and $LASTEXITCODE -eq 0)
        Output = $output
    }
}

function Assert-RevisionSucceeds(
    [string]$PlanPath,
    [string]$ValidationRoot = $fixtureRoot
) {
    $result = Invoke-RevisionValidator $PlanPath $ValidationRoot
    if (-not $result.Succeeded) {
        throw "Expected revision validation to succeed for '$PlanPath', but it failed: $($result.Output -join [Environment]::NewLine)"
    }
}

function Assert-MutatedRequestFails([string]$Label, [scriptblock]$Mutation) {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-revision-request-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "plans") -Destination $temporaryRoot -Recurse

        $requestPath = Join-Path $temporaryRoot "plans/artifacts/revision-loop/revision-request.json"
        $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
        & $Mutation $request
        $request | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $requestPath -Encoding UTF8

        $result = Invoke-RevisionValidator "plans/revision-loop-plan.md" $temporaryRoot
        if ($result.Succeeded) {
            throw "Expected revision validation to reject '$Label', but it succeeded: $($result.Output -join [Environment]::NewLine)"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

function Assert-ApprovedRetainedRequestSucceeds() {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-revision-approved-retained-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot "plans") -Destination $temporaryRoot -Recurse

        $requestPath = Join-Path $temporaryRoot "plans/artifacts/bugfix/revision-request.json"
        $request = Get-Content -LiteralPath (Join-Path $fixtureRoot "plans/artifacts/revision-loop/revision-request.json") -Raw | ConvertFrom-Json
        $request.plan_path = "plans/examples/bugfix-plan.md"
        $request.source_verdict_path = "plans/artifacts/bugfix/verify-verdict.md"
        $request | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $requestPath -Encoding UTF8

        $result = Invoke-RevisionValidator "plans/examples/bugfix-plan.md" $temporaryRoot
        if (-not $result.Succeeded) {
            throw "Expected approved verdict to accept a valid retained revision request: $($result.Output -join [Environment]::NewLine)"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

function Assert-ApprovedRequestPathFails() {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-revision-approved-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot "plans") -Destination $temporaryRoot -Recurse
        $requestDirectory = Join-Path $temporaryRoot "plans/artifacts/bugfix/revision-request.json"
        New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null

        $result = Invoke-RevisionValidator "plans/examples/bugfix-plan.md" $temporaryRoot
        if ($result.Succeeded) {
            throw "Expected approved verdict to reject an existing revision request path, but it succeeded: $($result.Output -join [Environment]::NewLine)"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

function Assert-StaleExitCodeDoesNotPoisonValidation() {
    $global:LASTEXITCODE = 7
    $caughtError = $null
    try {
        $output = @(& $validatorPath -RepoRoot $fixtureRoot -PlanPath "plans/revision-loop-plan.md" 2>&1)
    } catch {
        $caughtError = $_
        $output = @($_)
    }

    if ($null -ne $caughtError -or $LASTEXITCODE -ne 0) {
        throw "Expected stale LASTEXITCODE to be cleared for valid revision validation: $($output -join [Environment]::NewLine)"
    }
}

function Assert-RejectedReplanSucceeds() {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-revision-replan-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "plans") -Destination $temporaryRoot -Recurse

        $verdictPath = Join-Path $temporaryRoot "plans/artifacts/revision-loop/verify-verdict.md"
        (Get-Content -LiteralPath $verdictPath -Raw).Replace("NEEDS_REVISION", "REJECTED").Replace("fixable", "needs_replan") | Set-Content -LiteralPath $verdictPath -Encoding UTF8
        $requestPath = Join-Path $temporaryRoot "plans/artifacts/revision-loop/revision-request.json"
        $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
        $request.source_verdict_status = "REJECTED"
        $request.failure_classification = "needs_replan"
        $request.next_action = "replan"
        $request | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $requestPath -Encoding UTF8

        $result = Invoke-RevisionValidator "plans/revision-loop-plan.md" $temporaryRoot
        if (-not $result.Succeeded) {
            throw "Expected REJECTED/needs_replan to validate: $($result.Output -join [Environment]::NewLine)"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

function Assert-RevisionSchemaContract() {
    $schemaPath = Join-Path $repoRoot "schemas/revision-request.schema.json"
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    if ($schema.type -ne "object" -or $schema.additionalProperties -ne $false) {
        throw "Revision request schema must be a strict object"
    }
    foreach ($requiredField in @("schema_version", "plan_path", "source_verdict_path", "source_verdict_status", "failure_classification", "next_action", "summary", "items")) {
        if ($schema.required -notcontains $requiredField) {
            throw "Revision request schema does not require '$requiredField'"
        }
    }
    $itemSchema = $schema.'$defs'.item
    if ($null -eq $itemSchema -or $itemSchema.additionalProperties -ne $false) {
        throw "Revision request item schema must be strict"
    }
    foreach ($requiredField in @("id", "location", "finding", "required_change", "acceptance_criteria")) {
        if ($itemSchema.required -notcontains $requiredField) {
            throw "Revision request item schema does not require '$requiredField'"
        }
    }
}

function Assert-DeclaredCommandIsNotExecuted() {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-revision-no-exec-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "plans") -Destination $temporaryRoot -Recurse
        $markerPath = Join-Path $temporaryRoot "declared-command-marker.txt"
        $metadataPath = Join-Path $temporaryRoot "plans/artifacts/revision-loop/plan.meta.json"
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $metadata.phases[0].commands = @("New-Item -ItemType File -Force -Path '$markerPath'")
        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

        $result = Invoke-RevisionValidator "plans/revision-loop-plan.md" $temporaryRoot
        if (-not $result.Succeeded) {
            throw "Expected declared command string to remain inert: $($result.Output -join [Environment]::NewLine)"
        }
        if (Test-Path -LiteralPath $markerPath) {
            throw "Validator executed a declared metadata command"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

function Assert-NonPlansPathFails() {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-revision-plan-path-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "plans") -Destination $temporaryRoot -Recurse

        $rootPlanPath = Join-Path $temporaryRoot "revision-loop-plan.md"
        Copy-Item -LiteralPath (Join-Path $temporaryRoot "plans/revision-loop-plan.md") -Destination $rootPlanPath

        $metadataPath = Join-Path $temporaryRoot "plans/artifacts/revision-loop/plan.meta.json"
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $metadata.plan_path = "revision-loop-plan.md"
        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

        $requestPath = Join-Path $temporaryRoot "plans/artifacts/revision-loop/revision-request.json"
        $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
        $request.plan_path = "revision-loop-plan.md"
        $request | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $requestPath -Encoding UTF8

        $result = Invoke-RevisionValidator "revision-loop-plan.md" $temporaryRoot
        if ($result.Succeeded) {
            throw "Expected revision validation to reject a plan outside plans/: $($result.Output -join [Environment]::NewLine)"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

Assert-RevisionSucceeds "plans/revision-loop-plan.md" $fixtureRoot
Assert-RevisionSucceeds "plans/examples/bugfix-plan.md" $repoRoot
Assert-MutatedRequestFails "an action that conflicts with NEEDS_REVISION" {
    param($request)
    $request.next_action = "replan"
}
Assert-MutatedRequestFails "duplicate item ids" {
    param($request)
    $request.items += $request.items[0]
}
Assert-MutatedRequestFails "a mismatched plan path" {
    param($request)
    $request.plan_path = "plans/other-plan.md"
}
Assert-MutatedRequestFails "a wrong-case schema property" {
    param($request)
    $planPath = $request.plan_path
    $request.PSObject.Properties.Remove("plan_path")
    $request | Add-Member -NotePropertyName "Plan_Path" -NotePropertyValue $planPath
}
Assert-MutatedRequestFails "a whitespace-padded next action" {
    param($request)
    $request.next_action = "revise "
}
Assert-MutatedRequestFails "empty item finding" {
    param($request)
    $request.items[0].finding = ""
}
Assert-ApprovedRequestPathFails
Assert-ApprovedRetainedRequestSucceeds
Assert-StaleExitCodeDoesNotPoisonValidation
Assert-NonPlansPathFails
Assert-RejectedReplanSucceeds
Assert-RevisionSchemaContract
Assert-DeclaredCommandIsNotExecuted

Write-Output "VALID revision request contract"
