. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
function V4Hook($Root,$Session,[string]$PermissionMode='default',[string]$Event='Stop') {
 $payload=@{session_id=$Session;cwd=$Root;hook_event_name=$Event;model='fixture-model';transcript_path=$null;permission_mode=$PermissionMode}
 if($Event -eq 'SessionStart'){$payload.source='resume'}else{$payload.turn_id='fixture-turn'}
 if($Event -eq 'Stop'){$payload.stop_hook_active=$false;$payload.last_assistant_message=$null}
 $inputJson=$payload|ConvertTo-Json -Compress
 $stdout=$inputJson | & (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -NoProfile -File "$script:CoreRoot/scripts/invoke-hook.ps1" -Event $Event
 Assert ($LASTEXITCODE -eq 0) 'V4AdapterExitZero'
 return ($stdout|ConvertFrom-Json -AsHashtable)
}
$r=NewFixture
try {
$p=V4Contract $r draft 'v4-hooks';$run=Start-ControlFlowRun $r $p 'v4-hooks';$rp=$run.run_path
Throws {Update-ControlFlowRun $r $rp @{type='stop';reason='HUMAN_WAIT';evidence='unbound wait'}} 'HumanWaitRequiresBoundDecision'
$context=Artifact $r $rp context;$design=Artifact $r $rp design @($context)
ReviewArtifact $r $rp $design human UNKNOWN|Out-Null
$out=V4Hook $r 'v4-hooks';Assert ($out.systemMessage -match 'HUMAN_WAIT' -and -not $out.ContainsKey('decision')) 'HumanWaitAdapterDoesNotContinue'
# No decision was supplied: stop remains lawful across another callback.
Assert ((Read-ControlFlowRun $r $rp).state.status -ceq 'HUMAN_WAIT') 'WaitPersistsAcrossCallbacks'
$waiting=(Read-ControlFlowRun $r $rp).state
$plan=V4Hook $r 'v4-hooks' 'plan'
$afterPlan=(Read-ControlFlowRun $r $rp).state
Assert ($afterPlan.status -ceq 'HUMAN_WAIT' -and $afterPlan.revision -eq $waiting.revision -and $plan.systemMessage -match 'HUMAN_WAIT' -and -not $plan.ContainsKey('decision') -and -not $plan.ContainsKey('continue')) 'NativePlanModePreservesPendingHumanWait'
$interrupt=Request-ControlFlowInterrupt $r 'v4-hooks' 'interrupted-turn'
$plan=V4Hook $r 'v4-hooks' 'plan'
$afterPlan=Read-ControlFlowRun $r $rp
Assert ($afterPlan.state.status -ceq 'INTERRUPTED' -and $afterPlan.state.revision -eq $waiting.revision -and $afterPlan.pending_interrupt.interrupt_id -ceq $interrupt.interrupt_id -and $plan.systemMessage -match 'INTERRUPTED' -and -not $plan.ContainsKey('decision') -and -not $plan.ContainsKey('continue')) 'NativePlanModePreservesPendingInterrupt'
$lateStop=Update-ControlFlowRun $r $rp -ExpectedRevision $waiting.revision -Event @{type='stop';reason='PLAN_MODE';evidence='Adapter observed ACTIVE before the interrupt'}
Assert ($lateStop.state.status -ceq 'INTERRUPTED' -and $lateStop.state.revision -eq $waiting.revision -and $lateStop.pending_interrupt.interrupt_id -ceq $interrupt.interrupt_id) 'LedgerPreservesInterruptThatArrivedBeforeLockedPlanStop'
Write-Output "hooks-v4 wait: $script:Count assertions passed (adapter only)"
}finally{RemoveFixture $r}
$r=NewFixture
try {
    $session='manual-mode-conflict'
    $p=V4Contract $r draft $session
    $errorMessage=$null
    try {Start-ControlFlowRun $r $p -SessionId $session -ManualFallback|Out-Null}catch{$errorMessage=$_.Exception.Message}
    Assert ($errorMessage -ceq 'MANUAL_FALLBACK_REQUIRES_NO_SESSION') 'ManualFallbackRejectsNativeSessionBeforeCreatingRun'
    Assert ($null -eq (Get-ControlFlowActiveRun $r $session) -and -not (Test-Path -LiteralPath (Join-Path (Split-Path $p -Parent) 'runs'))) 'RejectedManualBindingLeavesNoRunOrActiveMarker'
    $v4Text=Get-Content -LiteralPath $p -Raw
    $oldDefinition=Get-Content -LiteralPath (LegacyContract $r -SessionId $session) -Raw|ConvertFrom-Json -AsHashtable
    $oldDefinition.task_id='old-manual-task'
    $legacyContract=(Get-ControlFlowStoragePaths $r $oldDefinition.task_id $session -Create).contract_path
    [IO.File]::WriteAllText($legacyContract,($oldDefinition|ConvertTo-Json -Depth 20))
    [IO.File]::WriteAllText($p,$v4Text)
    $legacy=New-HistoricalV3RunFixture $r $legacyContract -SessionId $session -ManualFallback
    foreach($event in @('SessionStart','Stop','Interrupt')) {
        Assert ((V4Hook $r $session -Event $event).Count -eq 0) "OldManualFallbackIgnoresNative$event"
    }
    $historical=Read-ControlFlowRun $r $legacy.run_path
    Assert ($historical.state.manual_fallback -and $historical.state.revision -eq 0 -and $null -eq $historical.pending_interrupt) 'ExistingManualRunRemainsAvailableThroughExplicitPath'
    File $legacy.run_path $historical.state.evidence_ref.path 'corrupt fixture evidence'
    Assert ((V4Hook $r $session).Count -eq 0) 'NativeStopDoesNotReadHistoricalManualEvidence'
    $native=Start-ControlFlowRun $r $p -SessionId $session
    Assert ((Get-ControlFlowActiveRun $r $session).state.run_id -ceq $native.run_id) 'OldManualMarkerDoesNotPreventNativeBinding'
    Write-Output "hooks-v4 modes: $script:Count assertions passed"
}finally{RemoveFixture $r}
$r=NewFixture
try {
$p=V4Contract $r final 'v4-hooks';$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40));$run=Start-ControlFlowRun $r $p 'v4-hooks';$rp=$run.run_path
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
Capture-ControlFlowCheck $r $rp check-1|Out-Null
Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Artifact $r $rp review-packet|Out-Null
$first=V4Hook $r 'v4-hooks';Assert ($first.Count -eq 0) 'V4CompleteCallback'
$revision=(Read-ControlFlowRun $r $rp).state.revision
$second=V4Hook $r 'v4-hooks';Assert ($second.Count -eq 0 -and (Read-ControlFlowRun $r $rp).state.revision -eq $revision) 'CompletedStopIdempotent'
$plan=V4Hook $r 'v4-hooks' 'plan'
$afterPlan=(Read-ControlFlowRun $r $rp).state
Assert ($plan.Count -eq 0 -and $afterPlan.status -ceq 'COMPLETED' -and $afterPlan.revision -eq $revision) 'NativePlanModeLeavesCompletedRunAlone'
$lateStop=Update-ControlFlowRun $r $rp -Event @{type='stop';reason='PLAN_MODE';evidence='Adapter observed ACTIVE before completion'}
Assert ($lateStop.state.status -ceq 'COMPLETED' -and $lateStop.state.revision -eq $revision) 'LedgerPreservesCompletionThatArrivedBeforeLockedPlanStop'
File $r owned.txt 'late mutation';$stale=V4Hook $r 'v4-hooks'
Assert ($stale.continue -eq $false -and (Read-ControlFlowRun $r $rp).state.status -ceq 'BLOCKED') 'StaleCompletedV4PersistsBlocked'
Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:resume'}} 'StaleTerminalCannotReopen'
Write-Output "hooks-v4: $script:Count assertions passed (adapter only; no host dispatch claim)"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
