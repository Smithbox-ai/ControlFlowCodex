$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$templateRoot=Join-Path $repoRoot 'plans/templates';$exampleRoot=Join-Path $repoRoot 'plans/examples'
Import-Module (Join-Path $repoRoot 'scripts/ControlFlow.Core.psm1') -Force -DisableNameChecking
$templates=@(Get-ChildItem $templateRoot -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($templateRoot,$_.FullName).Replace('\','/')})
if(Compare-Object @('plan.meta.v4.json') $templates){throw 'Only the current V4 template may create new tasks'}
$examples=@(Get-ChildItem $exampleRoot -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($exampleRoot,$_.FullName).Replace('\','/')})
if(Compare-Object @('small-v4.meta.json') $examples){throw 'Only the current V4 SMALL example is shipped'}
foreach($path in @((Join-Path $templateRoot 'plan.meta.v4.json'),(Join-Path $exampleRoot 'small-v4.meta.json'))){
 $read=Read-ControlFlowContract $path
 if($read.legacy-or$read.contract.schema_version-cne'4.0.0'-or$read.contract.contract_status-cne'draft'-or$read.contract.tier-cne'SMALL'-or$read.contract.commit.mode-cne'none'){throw 'New-task template/example must be V4 draft with no commit authorization'}
 $global:LASTEXITCODE=0;$output=& (Join-Path $repoRoot 'scripts/validate-contract.ps1') -Path $path
 if($LASTEXITCODE-ne0-or($output|ConvertFrom-Json).usage-cne'new-v4-task'){throw 'Current draft failed public V4 validator'}
}
if(Test-Path (Join-Path $repoRoot 'schemas/plan-meta-v3.schema.json')){throw 'V3 schema belongs only in the explicit compatibility namespace'}
if(-not(Test-Path (Join-Path $repoRoot 'schemas/compat/plan-meta-v3.schema.json'))){throw 'Historical V3 inputs still need strict validation'}
if((Get-ControlFlowClassification).schema_version-cne'4.0.0'){throw 'V4 is the default classifier'}
Write-Output 'VALID V4-only new-task template/example and explicit historical compatibility schema'
$global:LASTEXITCODE=0