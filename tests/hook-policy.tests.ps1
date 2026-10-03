$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/../scripts/ControlFlow.Hooks.psm1" -Force
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function State([string]$Status='ACTIVE',[int]$Total=0,[int]$Repeated=0) {
    @{status=$Status;continuations=@{total=$Total;repeated=$Repeated;signature='old'};structured_reason=@{reason=$Status;evidence='Native user decision'}}
}
$pass=@{status='PASS';reasons=@();contract_hash='contract';source_digest='source'}
$fail=@{status='FAIL';reasons=@('CHECK_MISSING','REVIEW_MISSING');contract_hash='contract';source_digest='source'}
$errorGate=@{status='ERROR';reasons=@('GIT_UNVERIFIABLE');contract_hash='contract';source_digest=$null}
Assert ((Get-ControlFlowStopPolicy -State $null -Gate $null).action -eq 'UNMANAGED') 'Unmanaged sessions must be unaffected'
Assert ((Get-ControlFlowStopPolicy -State (State) -Gate $pass).action -eq 'COMPLETE') 'Fresh PASS must permit completion'
Assert ((Get-ControlFlowStopPolicy -State (State) -Gate $fail).action -eq 'CONTINUE') 'Incomplete active run must continue'
foreach($status in @('CLARIFICATION','PERMISSION_DENIED','CANCELLED','PLAN_MODE','BLOCKED','INTERRUPTED')) {
    $decision=Get-ControlFlowStopPolicy -State (State $status) -Gate $pass
    Assert ($decision.action -eq 'LAWFUL_STOP') "$status must not become COMPLETE even if previous checks passed"
    Assert (-not $decision.done) 'Lawful turn endings must never report DONE'
}
$invalid=State 'CLARIFICATION';$invalid.structured_reason=$null
Assert ((Get-ControlFlowStopPolicy -State $invalid -Gate $pass).action -eq 'UNVERIFIABLE') 'Missing stop evidence cannot authorize completion'
Assert ((Get-ControlFlowStopPolicy -State (State) -Gate $errorGate).action -eq 'UNVERIFIABLE') 'Incomplete Git must not become PASS'
Assert ((Get-ControlFlowStopPolicy -State (State 'ACTIVE' 5) -Gate $fail).action -eq 'BLOCKED') 'Sixth continuation must block'
$signature=Get-ControlFlowContinuationSignature -Gate $fail
$reordered=@{status='FAIL';reasons=@('REVIEW_MISSING','CHECK_MISSING');contract_hash='contract';source_digest='source'}
Assert ($signature -eq (Get-ControlFlowContinuationSignature -Gate $reordered)) 'Reason order must not reset continuation limit'
$repeated=State 'ACTIVE' 2 2;$repeated.continuations.signature=$signature
Assert ((Get-ControlFlowStopPolicy -State $repeated -Gate $fail).action -eq 'BLOCKED') 'Third identical continuation must block'
$changed=@{status='FAIL';reasons=@('CHECK_MISSING','REVIEW_MISSING');contract_hash='contract';source_digest='new-source'}
Assert ((Get-ControlFlowStopPolicy -State $repeated -Gate $changed).action -eq 'CONTINUE') 'New source resets repetition, not total bound'
$completed=State 'COMPLETED'
Assert ((Get-ControlFlowStopPolicy -State $completed -Gate $fail).action -eq 'BLOCKED') 'Completed source mutation needs explicit resumption, never stale DONE'
Assert ((Get-ControlFlowStopPolicy -State (State) -Gate @{status='CLEAN';reasons=@()}).action -eq 'UNVERIFIABLE') 'Unknown gate result must fail closed'
Write-Output 'VALID hook policy: completion, lawful stops, 3/6 limits, stable signatures'
