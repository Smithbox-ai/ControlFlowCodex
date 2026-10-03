param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[Parameter(Mandatory)][string]$EventPath,[Nullable[int]]$ExpectedRevision)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
try {$event=Get-Content -LiteralPath $EventPath -Raw|ConvertFrom-Json -AsHashtable -Depth 40;$p=@{RepoRoot=$RepoRoot;RunPath=$RunPath;Event=$event};if($PSBoundParameters.ContainsKey('ExpectedRevision')){$p.ExpectedRevision=$ExpectedRevision};Update-ControlFlowRun @p|ConvertTo-Json -Depth 80;exit 0}catch{@{status='ERROR';reasons=@('UNVERIFIABLE');error=$_.Exception.Message}|ConvertTo-Json;exit 2}
