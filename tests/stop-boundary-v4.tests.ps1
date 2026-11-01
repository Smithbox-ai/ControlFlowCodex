. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
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
