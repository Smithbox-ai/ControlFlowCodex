param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$ContractPath,[string]$SessionId,[switch]$ManualFallback)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
try {Start-ControlFlowRun @PSBoundParameters|ConvertTo-Json -Depth 80;exit 0}catch{@{status='ERROR';reasons=@('UNVERIFIABLE');error=$_.Exception.Message}|ConvertTo-Json;exit 2}
