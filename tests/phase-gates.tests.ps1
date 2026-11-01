. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
$p=V4Contract $r;$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
Throws {Capture-ControlFlowCheck $r $rp 'check-1'} 'DraftCannotAuthorizeCodeOrChecks'
Throws {Artifact $r $rp 'implementation-plan'} 'ImplementationPlanNeedsQABaseline'
Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'DraftCannotPreflight'
$plan=Planning $r $rp
$b=Get-ControlFlowPlanningContext $r $rp
Assert ($b.artifacts.design.sha256 -ceq $plan.design.sha256) 'DownstreamAppendKeepsDesignValid'
$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable;$v.contract_status='final';[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
File $r 'owned.txt' 'authorized code'
$capture=Capture-ControlFlowCheck $r $rp 'check-1';Assert ($capture.status -ceq 'PASS') 'FinalCheckCapture'
Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
$re=Artifact $r $rp 'qa-recheck' @($plan.qa,$plan.implementation)
$packet=Artifact $r $rp 'review-packet' @($re)
Assert ((Test-ControlFlowGate $r $rp Completion).status -ceq 'PASS') 'V4CompletePath'
File $r 'owned.txt' 'new code';$gate=Test-ControlFlowGate $r $rp Completion
Assert ($gate.status -cne 'PASS') 'FinalPacketBoundToCurrentSource'
Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='user:replan'}|Out-Null
Assert ((Get-ControlFlowPlanningContext $r $rp).planning_epoch_id -eq 1) 'AuthorizedCodeCanReenterDesign'
Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'ReplannedDesignRequiresFreshDownstreamEvidence'
$again=Planning $r $rp;File $r 'owned.txt' 'unauthorized during wait'
Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'EditDuringReplanWaitBlocksPreflight'
Write-Output "phase-gates: $script:Count assertions passed"
}finally{RemoveFixture $r}
$r=NewFixture
try {
File $r 'foreign.txt' 'user baseline'
$p=V4Contract $r;$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
$plan=Planning $r $rp
$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable;$v.contract_status='final';[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
File $r 'owned.txt' 'too early'
Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'PreflightRejectsEarlyProductionEdit'
Throws {Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='user:replan'}} 'ReplanCannotLaunderEarlyEdits'
File $r 'owned.txt' 'initial';Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
File $r 'foreign.txt' 'changed foreign'
Throws {Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='user:replan'}} 'ReplanPreservesOriginalForeignOwnership'
Write-Output "phase-gates ownership: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
