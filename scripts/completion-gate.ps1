param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[string]$CommitSha)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
$r=Test-ControlFlowGate @PSBoundParameters -Kind Completion;$r|ConvertTo-Json -Depth 80
switch($r.status){'PASS'{exit 0};'FAIL'{exit 1};default{exit 2}}
