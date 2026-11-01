. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
function V4Hook($Root,$Session) {
 $inputJson=@{session_id=$Session;cwd=$Root;turn_id='fixture-turn';stop_hook_active=$false;permission_mode='on-request'}|ConvertTo-Json -Compress
 $stdout=$inputJson | & (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -NoProfile -File "$script:CoreRoot/scripts/invoke-hook.ps1" -Event Stop
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
Write-Output "hooks-v4 wait: $script:Count assertions passed (adapter only)"
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
File $r owned.txt 'late mutation';$stale=V4Hook $r 'v4-hooks'
Assert ($stale.continue -eq $false -and (Read-ControlFlowRun $r $rp).state.status -ceq 'BLOCKED') 'StaleCompletedV4PersistsBlocked'
Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:resume'}} 'StaleTerminalCannotReopen'
Write-Output "hooks-v4: $script:Count assertions passed (adapter only; no host dispatch claim)"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
