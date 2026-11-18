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
$r=NewFixture
try {
$oracle='checks/owner.ps1'
$command="[IO.File]::WriteAllText('.cache/owner-ran','original oracle')"
File $r $oracle $command
Git $r @('add','--',$oracle)|Out-Null
Git $r @('commit','-qm','trusted oracle')|Out-Null
File $r '.cache/keep' 'ignored'
$p=V4Contract $r final;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
$v.scope+=@($oracle);$v.checks[0].Remove('report');$v.checks[0].command="& './$oracle'"
$v.checks[0].baseline_inputs=@($oracle)
function SaveOracleContract {[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))}
function AssertOracleFailure([scriptblock]$Body,[string]$Expected,[string]$Name) {
 $observed=$null
 try{& $Body|Out-Null}catch{$observed=$_.Exception.Message}
 Assert ($observed -ceq $Expected) $Name
}
SaveOracleContract
$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
$v.checks[0].Remove('baseline_inputs');SaveOracleContract
AssertOracleFailure {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'BASELINE_CHECK_CHANGED: check-1' 'SameEpochPreflightCannotDropOracle'
$v.checks[0].baseline_inputs=@($oracle);$v.checks[0].command='Write-Output bypass';SaveOracleContract
AssertOracleFailure {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'BASELINE_CHECK_CHANGED: check-1' 'SameEpochPreflightCannotReplaceOracleCommand'
$v.checks[0].command="& './$oracle'";SaveOracleContract
File $r 'owned.txt' 'candidate may change'
$capture=Capture-ControlFlowCheck $r $rp check-1
Assert ($capture.status -ceq 'PASS' -and [IO.File]::ReadAllText((Join-Path $r '.cache/owner-ran')) -ceq 'original oracle') 'CleanBaselineOracleCanRunOnCandidate'
Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Artifact $r $rp review-packet|Out-Null
Assert ((Test-ControlFlowGate $r $rp Completion).status -ceq 'PASS') 'CleanBaselineOracleCanComplete'

$changed="[IO.File]::WriteAllText('.cache/owner-ran','edited oracle')"
File $r $oracle $changed
AssertOracleFailure {Capture-ControlFlowCheck $r $rp check-1} "BASELINE_INPUT_CHANGED: $oracle" 'EditedOracleIsRefusedBeforeExecution'
Assert ([IO.File]::ReadAllText((Join-Path $r '.cache/owner-ran')) -ceq 'original oracle') 'ChangedVerifierNeverExecuted'
Assert ("BASELINE_INPUT_CHANGED: $oracle" -cin (Test-ControlFlowGate $r $rp Completion).reasons) 'EditedOracleBlocksGateEvenWhenInScope'
Git $r @('add','--',$oracle)|Out-Null
File $r $oracle $command
AssertOracleFailure {Capture-ControlFlowCheck $r $rp check-1} "BASELINE_INPUT_CHANGED: $oracle" 'IndexOnlyOracleDriftIsRefused'
$gate=Test-ControlFlowGate $r $rp Completion
Assert ($gate.source_digest -ceq $capture.source_after -and "BASELINE_INPUT_CHANGED: $oracle" -cin $gate.reasons) 'IndexOnlyOracleDriftBlocksGateWithSameEffectiveSource'
Git $r @('add','--',$oracle)|Out-Null

File $r $oracle $changed
Git $r @('add','--',$oracle)|Out-Null
Git $r @('commit','-qm','in-run oracle drift')|Out-Null
Git $r @('restore','--source',$v.baseline.commit,'--staged','--worktree','--',$oracle)|Out-Null
AssertOracleFailure {Capture-ControlFlowCheck $r $rp check-1} "BASELINE_INPUT_CHANGED: $oracle" 'CommittedOracleDriftBlocksCaptureAfterWorktreeAndIndexRestore'
$gate=Test-ControlFlowGate $r $rp Completion
Assert ($gate.source_digest -ceq $capture.source_after -and "BASELINE_INPUT_CHANGED: $oracle" -cin $gate.reasons) 'CommittedOracleDriftBlocksGateWithSameEffectiveSource'
Git $r @('commit','-qm','restore oracle')|Out-Null

Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='user:approve replanning'}|Out-Null
$v.checks[0].Remove('baseline_inputs');SaveOracleContract
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
Assert ((Read-ControlFlowRun $r $rp).state.planning_epoch_id -eq 1) 'ExplicitReplanCanChangeProtectedCheckDefinition'
$v.checks[0].baseline_inputs=@($oracle);SaveOracleContract

File $r $oracle $changed
$run=Start-ControlFlowRun $r $p -ManualFallback
AssertOracleFailure {Update-ControlFlowRun $r $run.run_path @{type='preflight';status='APPROVED'}} "BASELINE_INPUT_NOT_CLEAN: $oracle" 'UnstagedOriginalOracleCannotBeNominated'
Git $r @('add','--',$oracle)|Out-Null
File $r $oracle $command
$run=Start-ControlFlowRun $r $p -ManualFallback
AssertOracleFailure {Update-ControlFlowRun $r $run.run_path @{type='preflight';status='APPROVED'}} "BASELINE_INPUT_NOT_CLEAN: $oracle" 'StagedOriginalOracleCannotBeNominated'
Git $r @('add','--',$oracle)|Out-Null

$v.checks[0].baseline_inputs=@('checks/../foreign.txt');SaveOracleContract
AssertOracleFailure {Read-ControlFlowContract $p} 'INVALID_CHECK_INPUT_PATH: checks/../foreign.txt' 'BaselineOraclePathIsLiteral'
$v.checks[0].baseline_inputs=@('.cache/keep');SaveOracleContract
$run=Start-ControlFlowRun $r $p -ManualFallback
AssertOracleFailure {Update-ControlFlowRun $r $run.run_path @{type='preflight';status='APPROVED'}} 'BASELINE_INPUT_NOT_TRACKED_REGULAR_FILE: .cache/keep' 'IgnoredFileIsNotABaselineOracle'

$v.checks[0].baseline_inputs=@($oracle);SaveOracleContract
File $r $oracle $changed
Git $r @('add','--',$oracle)|Out-Null
Git $r @('commit','-qm','unapproved oracle revision')|Out-Null
$run=Start-ControlFlowRun $r $p -ManualFallback
AssertOracleFailure {Update-ControlFlowRun $r $run.run_path @{type='preflight';status='APPROVED'}} "BASELINE_INPUT_NOT_CLEAN: $oracle" 'CleanHeadCannotReplaceOlderBaselineOracle'

# A symlink-mode Git entry is invalid even with a plain checkout placeholder.
$link='checks/oracle-link.txt'
Git $r @('config','core.symlinks','false')|Out-Null
File $r $link 'owner.ps1'
$targetBlob=Git $r @('hash-object','-w','--',$link)
Git $r @('update-index','--add','--cacheinfo',"120000,$targetBlob,$link")|Out-Null
Git $r @('commit','-qm','oracle symlink fixture')|Out-Null
$v.baseline.commit=Git $r @('rev-parse','HEAD');$v.checks[0].baseline_inputs=@($link);SaveOracleContract
$run=Start-ControlFlowRun $r $p -ManualFallback
AssertOracleFailure {Update-ControlFlowRun $r $run.run_path @{type='preflight';status='APPROVED'}} "BASELINE_INPUT_NOT_TRACKED_REGULAR_FILE: $link" 'GitSymlinkCannotBeABaselineOracle'
Write-Output "phase-gates baseline inputs: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
