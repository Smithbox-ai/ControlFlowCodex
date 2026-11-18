param([switch]$RepairOnly)
. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
    $session='repair-limit-session'
    $p=V4Contract $r final $session
    $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -AsHashtable
    $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
    [void]$v.checks[0].Remove('report')
    $v.checks[0].command='if([IO.File]::ReadAllText("owned.txt") -cne "fixed"){throw "unresolved fixture failure"}'
    [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
    $rp=(Start-ControlFlowRun $r $p -SessionId $session).run_path
    Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
    $initial=Capture-ControlFlowCheck $r $rp check-1
    $raw=Capture-ControlFlowCheck $r $rp check-1
    Assert (@((Read-ControlFlowRun $r $rp).evidence.events|Where-Object {$_.type -ceq 'repair_attempt'}).Count -eq 0) 'RawCapturesAreNotRepairRounds'
    $after=Capture-ControlFlowCheck $r $rp check-1
    $event=@{type='repair_attempt';cause_id='fixture-cause';before_capture_id=$initial.capture_id;after_capture_id=$after.capture_id;change='Corrected fixture initialization'}
    Throws {Update-ControlFlowRun $r $rp $event} 'RepairMustUseConsecutiveCapturesOfItsCheck'
    $event.before_capture_id=$raw.capture_id
    $result=Update-ControlFlowRun $r $rp $event
    Assert ($result.state.status -ceq 'ACTIVE' -and $result.evidence.events[-1].round -eq 1) 'FirstRecordedRepairLeavesRunActive'
    Throws {Update-ControlFlowRun $r $rp $event} 'FailureCaptureCannotBeCountedTwice'
    $contractBytes=[IO.File]::ReadAllBytes($p)
    [IO.File]::AppendAllText($p,[Environment]::NewLine)
    $preflightError=$null
    try {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null}catch{$preflightError=$_.Exception.Message}
    Assert ($preflightError -ceq 'REPAIR_HISTORY_REPLAN_REQUIRED') 'NewlineOnlyContractApprovalCannotResetRepairHistory'
    [IO.File]::WriteAllBytes($p,$contractBytes)
    $event.before_capture_id=$after.capture_id
    File $r 'owned.txt' 'fixed'
    $pass=Capture-ControlFlowCheck $r $rp check-1
    $event.after_capture_id=$pass.capture_id
    Throws {Update-ControlFlowRun $r $rp $event} 'PassingCaptureIsNotFailedRepair'
    File $r 'owned.txt' 'failure returned'
    $before=Capture-ControlFlowCheck $r $rp check-1
    foreach($round in 1..3){
        File $r 'owned.txt' ("targeted repair "+$round)
        $after=Capture-ControlFlowCheck $r $rp check-1
        $event.before_capture_id=$before.capture_id
        $event.after_capture_id=$after.capture_id
        if($round -eq 2){Throws {Update-ControlFlowRun $r $rp $event} 'DuplicateChangeNoteIsNotAnotherRepair'}
        $event.change="Checked alternate failure hypothesis $round"
        if($round -eq 1){
            File $r 'owned.txt' 'different source after capture'
            Throws {Update-ControlFlowRun $r $rp $event} 'ChangedSourceMakesRepairCaptureStale'
            File $r 'owned.txt' ("targeted repair "+$round)
        }
        if($round -eq 3){
            Throws {Update-ControlFlowRun $r $rp $event} 'ThirdRepairNeedsConcreteEscalationQuestion'
            $event.question='Which fixture prerequisite can be restored?'
        }
        $result=Update-ControlFlowRun $r $rp $event
        Assert ($result.evidence.events[-1].round -eq $round) ('RepairRoundSinceLastSuccess:'+ $round)
        if($round -eq 2){
            Update-ControlFlowRun $r $rp @{type='stop';reason='CLARIFICATION';evidence='separate fixture question'}|Out-Null
            Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:separate-answer'}|Out-Null
        }
        $before=$after
    }
    $escalation=$result.state.repair_escalation
    Assert ($result.state.status -ceq 'BLOCKED' -and $result.state.structured_reason.evidence -ceq 'REPAIR_LIMIT' -and $escalation.id -ceq $after.capture_id -and $escalation.question -ceq $event.question) 'ThirdFailedRepairAtomicallyEscalates'
    Assert ($result.state.stop_source_digest -ceq $after.source_after) 'RepairEscalationPreservesSourceBoundary'
    Assert ('REPAIR_ESCALATION_PENDING' -cin (Test-ControlFlowGate $r $rp Completion).reasons) 'PendingRepairEscalationPreventsDelivery'
    Throws {Capture-ControlFlowCheck $r $rp check-1} 'EscalatedRepairCannotRunAnotherCheck'
    Update-ControlFlowRun $r $rp @{type='stop';reason='CLARIFICATION';evidence='later unrelated stop'}|Out-Null
    Request-ControlFlowInterrupt $r $session|Out-Null
    Assert ((Read-ControlFlowRun $r $rp).state.repair_escalation.id -ceq $escalation.id) 'OtherStopAndInterruptPreserveEscalation'
    Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:resume'}} 'EscalationNeedsExactReceipt'
    Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:resume';repair_escalation_id=$raw.capture_id}} 'WrongEscalationReceiptCannotResume'
    Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:resume';repair_escalation_id=@($escalation.id)}} 'EscalationReceiptMustBeExactScalar'
    Throws {Update-ControlFlowRun $r $rp @{type='resume';repair_escalation_id=$escalation.id}} 'ExactEscalationNeedsUserDecision'
    $resumed=Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:authorized-repair';repair_escalation_id=$escalation.id}
    Assert ($resumed.state.status -ceq 'ACTIVE' -and -not $resumed.state.ContainsKey('repair_escalation')) 'ApprovedExactEscalationResumesWithoutPassingGate'
    Assert ((Test-ControlFlowGate $r $rp Completion).status -ceq 'FAIL') 'ResumeKeepsRequiredCheckFailure'
    File $r 'owned.txt' 'targeted repair after escalation'
    $after=Capture-ControlFlowCheck $r $rp check-1
    $event.before_capture_id=$escalation.id;$event.after_capture_id=$after.capture_id;$event.change='Followed the approved prerequisite decision'
    $newRound=Update-ControlFlowRun $r $rp $event
    Assert ($newRound.state.status -ceq 'ACTIVE' -and $newRound.evidence.events[-1].round -eq 1) 'ApprovedEscalationResumeStartsNewRepairSeries'
    $replanned=Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='user:authorized-replan'}
    Assert ($replanned.state.planning_epoch_id -eq 1) 'ApprovedReplanStartsNewRepairEpoch'
    [IO.File]::AppendAllText($p,[Environment]::NewLine)
    $reapproved=Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}
    Assert ($reapproved.state.preflight_digest -ceq (Read-ControlFlowContract $p).digest) 'ExplicitNewEpochAllowsChangedContractApproval'
    Write-Output "repair-boundary-v4: $script:Count assertions passed"
} finally {RemoveFixture $r}
if($RepairOnly){$global:LASTEXITCODE=0;return}
$r=NewFixture
try{
$p=V4Contract $r final;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false;$v.review_policy.requirements[0].judges=@('human');$v.checks=@()
[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40));$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
File $r owned.txt 'authorized before wait'
$packet=Artifact $r $rp review-packet
ReviewArtifact $r $rp $packet human REJECTED manual C1|Out-Null
Update-ControlFlowRun $r $rp @{type='stop';reason='BLOCKED';evidence='another stop'}|Out-Null
Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='old decision'}} 'StopCannotErasePendingHumanDecision'
File $r owned.txt 'unauthorized during wait'
Update-ControlFlowRun $r $rp @{type='stop';reason='BLOCKED';evidence='cannot reset boundary'}|Out-Null
Throws {Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='user:replan'}} 'ReplanCannotLaunderWaitEdits'
File $r owned.txt 'authorized before wait'
ReviewArtifact $r $rp $packet human APPROVED manual C1|Out-Null
$receipt=(Read-ControlFlowRun $r $rp).evidence.events[-1].receipt_id
Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:now';decision_receipt_id=$receipt}|Out-Null
Assert ((Read-ControlFlowRun $r $rp).state.status -ceq 'ACTIVE') 'CurrentDecisionCanResumePreservedBoundary'
Write-Output "stop-boundary-v4: $script:Count assertions passed"
}finally{RemoveFixture $r}
$r=NewFixture
try{
$p=V4Contract $r draft 'fast-interrupt';$run=Start-ControlFlowRun $r $p 'fast-interrupt';$rp=$run.run_path
Request-ControlFlowInterrupt $r fast-interrupt first|Out-Null
$noticePath=Join-Path $rp pending-interrupt.json;$first=Get-Content $noticePath -Raw|ConvertFrom-Json -AsHashtable
# Simulate a writer that read ACTIVE before the interrupt and published later.
# The native mailbox must preserve its first boundary without a Git operation.
File $r owned.txt 'late writer source'
$statePath=Join-Path $rp state.json;$state=Get-Content $statePath -Raw|ConvertFrom-Json -AsHashtable
$state.last_observed_source_digest=(Get-ControlFlowPlanningContext $r $rp).source_digest
[IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 50))
Request-ControlFlowInterrupt $r fast-interrupt second|Out-Null
$second=Get-Content $noticePath -Raw|ConvertFrom-Json -AsHashtable
Assert ($second.observed_source_digest -ceq $first.observed_source_digest) 'RepeatedInterruptPreservesFirstSourceBoundary'
Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:resume'}} 'InterruptCannotLaunderLaterSource'
Write-Output "stop-boundary-v4 interrupt: $script:Count assertions passed (busy-writer publication simulated)"
}finally{RemoveFixture $r}
foreach($mode in @('continuation','agent-correction')){
 $r=NewFixture
 try{
  $p=V4Contract $r final;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
  $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
  [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40));$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
  Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
  File $r owned.txt 'authorized before implicit block'
  if($mode -ceq 'agent-correction'){$packet=Artifact $r $rp review-packet}
  for($i=0;$i -lt 3;$i++){
   if($mode -ceq 'continuation'){Update-ControlFlowRun $r $rp @{type='continuation';signature='repeat'}|Out-Null}
   else{ReviewArtifact $r $rp $packet agent REJECTED manual C1|Out-Null}
  }
  File $r owned.txt 'unauthorized during implicit block'
  Throws {Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='user:replan'}} ($mode+'BlockCannotLaunderWaitEdits')
  File $r owned.txt 'authorized before implicit block'
  Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='user:replan'}|Out-Null
  Assert ((Read-ControlFlowRun $r $rp).state.planning_epoch_id -eq 1) ($mode+'BlockAllowsAuthorizedReplan')
 }finally{RemoveFixture $r}
}
Write-Output "implicit-block regression: $script:Count assertions passed"


$global:LASTEXITCODE=0
