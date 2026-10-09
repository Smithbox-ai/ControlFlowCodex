param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$TaskId,[string]$SessionId,[switch]$Create)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
try {Get-ControlFlowStoragePaths @PSBoundParameters|ConvertTo-Json -Depth 20;exit 0}catch{@{status='ERROR';reasons=@('UNVERIFIABLE');error=$_.Exception.Message}|ConvertTo-Json;exit 2}
