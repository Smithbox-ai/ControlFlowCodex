. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
Import-Module "$script:CoreRoot/scripts/ControlFlow.Hooks.psm1" -Force
$r=NewFixture
try {
$p=V4Contract $r;$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
$context=Artifact $r $rp context;$design=Artifact $r $rp design @($context)
Throws {ReviewArtifact $r $rp $design human APPROVED verified} 'SelfAttestationNotVerified'
$decision=ReviewArtifact $r $rp $design human REJECTED
Assert ($decision.state.status -ceq 'HUMAN_WAIT') 'RejectedDecisionBlocks'
$policy=Get-ControlFlowStopPolicy $decision.state @{status='FAIL';reasons=@('HUMAN_DESIGN_REQUIRED')}
Assert ($policy.action -ceq 'LAWFUL_STOP' -and -not $policy.done) 'HumanWaitDoesNotContinue'
Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='old message'}} 'WaitCannotResumeFromBareText'
$decision=ReviewArtifact $r $rp $design human APPROVED
$receipt=$decision.evidence.events[-1]
Assert ($receipt.assurance -ceq 'manual') 'ManualAssuranceVisible'
Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:resume';decision_receipt_id=$receipt.receipt_id}|Out-Null
$replacement=Artifact $r $rp design @($context) -Revision 2
Throws {Artifact $r $rp 'qa-plan' @($replacement)} 'ChangedDesignNeedsNewDecision'
ReviewArtifact $r $rp $replacement human REJECTED|Out-Null
Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:old';decision_receipt_id=$receipt.receipt_id}} 'StaleDecisionCannotResume'
ReviewArtifact $r $rp $replacement agent REJECTED | Out-Null
Assert ((Read-ControlFlowRun $r $rp).state.status -ceq 'BLOCKED') 'CorrectionBudgetExhausted'
Write-Output "decisions-v4: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
