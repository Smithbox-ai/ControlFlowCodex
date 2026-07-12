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

Write-Output "VALID revision request contract"
