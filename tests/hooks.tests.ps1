. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
function Hook([string]$Repo,[string]$Session,[string]$Event='Stop',[string]$PermissionMode='on-request') {
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=@(Get-Command pwsh -CommandType Application)[0].Source
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-File',"$script:CoreRoot/scripts/invoke-hook.ps1",'-Event',$Event)){[void]$psi.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
    try {
        [void]$process.Start()
        $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.WriteLine((@{session_id=$Session;cwd=$Repo;turn_id='fixture-turn';stop_hook_active=$false;permission_mode=$PermissionMode}|ConvertTo-Json -Compress))
        $process.StandardInput.Close()
        $deadline=if($Event -eq 'Interrupt'){3000}else{15000}
        if(-not $process.WaitForExit($deadline)){$process.Kill($true);throw "Hook exceeded $deadline ms fixture deadline"}
        $stdout=$out.GetAwaiter().GetResult();$stderr=$err.GetAwaiter().GetResult()
        Assert ($process.ExitCode -eq 0) "Hook must emit valid native protocol, stderr=$stderr"
        return ($stdout|ConvertFrom-Json -AsHashtable)
    }finally{$process.Dispose()}
}
$r=NewFixture
try {
    Assert ((Hook $r 'unmanaged').Count -eq 0) 'No active v3 run leaves native session unmanaged'
    File $r 'plans/old-plan.md' 'V2 plan with arbitrary prose DONE'
    Assert ((Hook $r 'unmanaged').Count -eq 0) 'V2 prose cannot activate v3 Stop'
    $p=Contract $r
    $run=Start-ControlFlowRun $r $p 'session-a'
    Assert ((Hook $r 'session-b').Count -eq 0) 'Foreign session never adopts another run'
    [IO.Directory]::CreateDirectory((Join-Path $r 'subdir'))|Out-Null
    $decision=Hook (Join-Path $r 'subdir') 'session-a'
    Assert ($decision.decision -eq 'block') 'Missing check blocks active native Stop'
    Assert ((Read-ControlFlowRun $r $run.run_path).state.continuations.total -eq 1) 'Hook continuation counter persists'
    $null=Hook $r 'session-a'
    $last=Hook $r 'session-a'
    Assert ($last.continue -eq $false) 'Third identical Stop ends BLOCKED'
    Assert ((Read-ControlFlowRun $r $run.run_path).state.status -eq 'BLOCKED') 'Budget exhaustion is not COMPLETED'
    $resume=Hook $r 'session-a' 'SessionStart'
    Assert ($resume.hookSpecificOutput.additionalContext -match 'explicit user decision') 'Resume does not restart BLOCKED'
    Update-ControlFlowRun $r $run.run_path @{type='resume';user_decision_ref='fixture-user-resume'}|Out-Null
    Update-ControlFlowRun $r $run.run_path @{type='stop';reason='CLARIFICATION';evidence='Unknown product default';question='Which default?';pending_decision_id='choice-1'}|Out-Null
    $question=Hook $r 'session-a'
    Assert (-not $question.ContainsKey('decision') -and $question.systemMessage -match 'incomplete') 'Clarification allows turn end without DONE'
    Update-ControlFlowRun $r $run.run_path @{type='resume';user_decision_ref='fixture-choice-1'}|Out-Null
    $busyWriter=[IO.File]::Open((Join-Path $run.run_path 'writer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$interrupted=Hook $r 'session-a' 'Interrupt'}finally{$busyWriter.Dispose()}
    Assert ((Read-ControlFlowRun $r $run.run_path).state.status -eq 'INTERRUPTED') 'Native Interrupt persists and never continues'
    Assert (-not $interrupted.ContainsKey('decision')) 'Interrupt cannot block cancellation'
    Update-ControlFlowRun $r $run.run_path @{type='resume';user_decision_ref='fixture-user-resume-2'}|Out-Null
    $planStop=Hook $r 'session-a' -PermissionMode 'plan'
    Assert (-not $planStop.ContainsKey('decision')) 'Native Plan Mode is a lawful turn end'
    Assert ((Read-ControlFlowRun $r $run.run_path).state.status -eq 'PLAN_MODE') 'Native Plan Mode persists distinct from DONE'
    Update-ControlFlowRun $r $run.run_path @{type='resume';user_decision_ref='fixture-exit-plan-mode'}|Out-Null
    Capture-ControlFlowCheck $r $run.run_path 'check-1'|Out-Null
    Update-ControlFlowRun $r $run.run_path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
    $complete=Hook $r 'session-a'
    Assert ($complete.Count -eq 0) 'Fresh verified completion permits native final'
    Assert ((Read-ControlFlowRun $r $run.run_path).state.status -eq 'COMPLETED') 'Completion publication internally rechecks gate'
    File $r 'owned.txt' 'later mutation'
    $stale=Hook $r 'session-a'
    Assert ($stale.ContainsKey('decision') -or $stale.ContainsKey('stopReason')) 'Mutation after completion is checked again'
    Assert ((Read-ControlFlowRun $r $run.run_path).state.status -eq 'BLOCKED') 'Mutation after completion persists BLOCKED, not historical COMPLETED'
    [IO.File]::WriteAllText((Join-Path $run.run_path 'state.json'),'broken')
    $corrupt=Hook $r 'session-a'
    Assert ($corrupt.continue -eq $false -and $corrupt.systemMessage -match 'UNVERIFIABLE') 'Corrupt ledger has visible bounded failure, never DONE'
    Write-Output "VALID native hook protocol: $script:Count assertions"
}finally{
    $resolved=[IO.Path]::GetFullPath($r)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('cf-core-')){throw 'Unsafe fixture cleanup'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
