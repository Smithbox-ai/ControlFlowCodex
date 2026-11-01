param([int]$ChangedFiles=0,[switch]$BehaviorChange,[switch]$HighRisk,[switch]$CrossBoundary,[switch]$ProductQuestion,[ValidateSet("4.0.0")][string]$SchemaVersion="4.0.0",[ValidateSet("feature","bugfix","refactor","docs")][string]$WorkType="feature",[ValidateSet("core","supporting","generic","unknown")][string]$Domain="unknown")
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
Get-ControlFlowClassification @PSBoundParameters|ConvertTo-Json -Depth 10
