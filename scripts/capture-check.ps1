param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[Parameter(Mandatory)][string]$CheckId)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
try {$r=Capture-ControlFlowCheck @PSBoundParameters;$r|ConvertTo-Json -Depth 80;if($r.status -eq 'PASS'){exit 0}else{exit 1}}catch{@{status='ERROR';reasons=@('UNVERIFIABLE');error=$_.Exception.Message}|ConvertTo-Json;exit 2}
