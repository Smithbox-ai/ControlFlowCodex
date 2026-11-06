. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$module=Get-TestControlFlowModule
$r=NewFixture
try {
    $p=V4Contract $r final
    File $r '.cache/guard.cs' 'original guard'
    $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -AsHashtable
    $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
    $v.quality_profiles=@(@{id='mutation';kind='mutation';required=$true;capability='available';check_ids=@('check-1')})
    $v.checks[0].report=@{format='stryker-json';path='.cache/mutation.json';tool='fixture';version='1';scope=@('.cache/guard.cs');config='inline';baseline='initial';exclusions=@();minimum_score=80}
    $v.checks[0].command=@'
$source=[IO.File]::ReadAllText('.cache/guard.cs')
$report=@{schemaVersion='1';files=@{'.cache/guard.cs'=@{source=$source;language='cs';mutants=@(@{id='1';status='Killed'})}}}
[IO.File]::WriteAllText('.cache/mutation.json',($report|ConvertTo-Json -Depth 20))
'@
    [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
    $run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
    Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
    $capture=Capture-ControlFlowCheck $r $rp check-1
    Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
    Artifact $r $rp review-packet|Out-Null
    Assert ((Test-ControlFlowGate $r $rp Completion).status -ceq 'PASS') 'IgnoredMutationTargetInitiallyPasses'
    File $r '.cache/guard.cs' 'changed after capture'
    $gate=Test-ControlFlowGate $r $rp Completion
    Assert ($gate.status -ceq 'FAIL' -and 'CHECK_STALE:check-1' -cin $gate.reasons) 'IgnoredMutationScopeAutomaticallyInvalidatesCapture'
    $packet=Artifact $r $rp review-packet -Revision 2
    $saved=Get-Content -LiteralPath (Join-Path $rp $packet.path) -Raw|ConvertFrom-Json -AsHashtable
    Assert ($saved.profile_summary[0].status -ceq 'STALE') 'ProfileIncludesAutomaticScopeInputs'
    File $r '.cache/guard.cs' 'original guard'
    $read=Read-ControlFlowRun $r $rp
    $oldRead=$read|ConvertTo-Json -Depth 80|ConvertFrom-Json -AsHashtable
    $oldRead.evidence.checks[0].Remove('input_before');$oldRead.evidence.checks[0].Remove('input_after')
    $accepted=& $module {param($Read,$P,$Digest) Test-CFV4Capture $Read (Read-ControlFlowContract $P) @{digest=$Digest} check-1} $oldRead $p $capture.source_after
    Assert (-not $accepted) 'OldCaptureWithoutScopeInputReceiptNeedsRecapture'
    $v.checks[0].command+="`n[IO.File]::WriteAllText('.cache/guard.cs','changed by check')"
    [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
    Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
    $changed=Capture-ControlFlowCheck $r $rp check-1
    Assert ($changed.status -ceq 'STALE' -and $changed.input_before -cne $changed.input_after) 'CheckCannotChangeIgnoredMutationTarget'
    foreach($invalid in @('../outside.cs','/rooted.cs','src/*.cs','src\guard.cs')) {
        $bad=@{report=@{format='stryker-json';scope=@($invalid)}}
        $rejected=$false;try {& $module {param($Root,$Check) Get-CFCheckInputDigest $Root $Check} $r $bad|Out-Null}catch{$rejected=$true}
        Assert $rejected ('AutomaticScopeValidatedBeforeReading:'+ $invalid)
    }
    $check=@{inputs=@('owned.txt','.cache/guard.cs');report=@{format='stryker-json';scope=@('.cache/guard.cs')}}
    $paths=@(& $module {param($Check) Get-CFCheckInputPaths $Check} $check)
    Assert ($paths.Count -eq 2) 'ExplicitAndAutomaticInputsDeduplicate'
    Write-Output "mutation-inputs: $script:Count assertions passed"
} finally {RemoveFixture $r}
$global:LASTEXITCODE=0
