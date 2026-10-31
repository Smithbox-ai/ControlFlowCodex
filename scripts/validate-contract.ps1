param([Parameter(Mandatory)][string]$Path,[switch]$AllowV2)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
try {$r=Read-ControlFlowContract @PSBoundParameters;@{status='PASS';contract_digest=$r.digest;schema_version=$r.contract.schema_version;legacy=$r.legacy;usage=$(if($r.contract.schema_version -ceq '2.0.0'){'migration-only'}elseif($r.legacy){'migration-or-existing-run-only'}else{'new-v4-task'})}|ConvertTo-Json;exit 0}catch{@{status='ERROR';reasons=@('INVALID_CONTRACT');error=$_.Exception.Message}|ConvertTo-Json;exit 2}
