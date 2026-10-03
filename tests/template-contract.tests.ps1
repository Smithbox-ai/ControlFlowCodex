$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$templateRoot=Join-Path $repoRoot 'plans/templates'
$exampleRoot=Join-Path $repoRoot 'plans/examples'
Import-Module (Join-Path $repoRoot 'scripts/ControlFlow.Core.psm1') -Force -DisableNameChecking

# Exact shipped entries prevent the old Markdown/sidecar workflow from quietly
# returning alongside the current machine-readable v3 contract.
$templates=@(Get-ChildItem -LiteralPath $templateRoot -File -Recurse -Force|ForEach-Object {[IO.Path]::GetRelativePath($templateRoot,$_.FullName).Replace('\','/')})
if(@(Compare-Object @('plan.meta.v3.json') $templates).Count){throw "Expected only the v3 metadata template, found: $($templates -join ', ')"}
$examples=@(Get-ChildItem -LiteralPath $exampleRoot -File -Recurse -Force|ForEach-Object {[IO.Path]::GetRelativePath($exampleRoot,$_.FullName).Replace('\','/')})
if(@(Compare-Object @('small-v3.meta.json') $examples).Count){throw "Expected only the v3 SMALL example, found: $($examples -join ', ')"}
foreach($path in @((Join-Path $templateRoot 'plan.meta.v3.json'),(Join-Path $exampleRoot 'small-v3.meta.json'))){
    $read=Read-ControlFlowContract -Path $path
    if($read.legacy -or $read.contract.schema_version -cne '3.0.0' -or $read.contract.tier -cne 'SMALL' -or $read.contract.commit.mode -cne 'none'){throw "V3 template/example must be a current SMALL contract with no requested commit: $path"}
    $global:LASTEXITCODE=0
    $output=& (Join-Path $repoRoot 'scripts/validate-contract.ps1') -Path $path
    if($LASTEXITCODE -ne 0 -or ($output|ConvertFrom-Json).status -cne 'PASS'){throw "Shipped v3 contract failed its public validator: $path"}
}
Write-Output 'VALID v3-only template and SMALL example contracts'
$global:LASTEXITCODE=0
