param([string]$RepoRoot,[string]$RunPath,[ValidateSet('update','capture')][string]$Action)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/../scripts/ControlFlow.Core.psm1" -Force -DisableNameChecking
try {
if($Action -eq 'update'){Update-ControlFlowRun $RepoRoot $RunPath @{type='blocker';id='B1';status='OPEN';text='Concurrent writer'} -ExpectedRevision 0|Out-Null}
else{Capture-ControlFlowCheck $RepoRoot $RunPath 'check-1'|Out-Null}
exit 0
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 2}
