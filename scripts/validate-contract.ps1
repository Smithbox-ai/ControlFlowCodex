param([Parameter(Mandatory)][string]$Path,[switch]$AllowV2)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
try {$r=Read-ControlFlowContract @PSBoundParameters;@{status='PASS';contract_digest=$r.digest;schema_version=$r.contract.schema_version;legacy=$r.legacy}|ConvertTo-Json;exit 0}catch{@{status='ERROR';reasons=@('INVALID_CONTRACT');error=$_.Exception.Message}|ConvertTo-Json;exit 2}
