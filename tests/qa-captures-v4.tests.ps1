. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
function RejectsQAEvidence([scriptblock]$Body,[string]$Message) {
 $errorCode=$null
 try{& $Body|Out-Null}catch{$errorCode=$_.Exception.Message}
 Assert ($errorCode -ceq 'QA_EVIDENCE_MISSING') $Message
}
$r=NewFixture
try {
$p=V4Contract $r;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.checks[0].command=@'
$mode=if(Test-Path -LiteralPath '.cache/report-mode'){[IO.File]::ReadAllText('.cache/report-mode')}else{'pass'}
if($mode -ceq 'missing'){[IO.File]::Delete('.cache/report.xml');exit 0}
$xml=switch -CaseSensitive($mode){
 'zero' {'<test-run total="0" passed="0" failed="0" skipped="0" inconclusive="0" asserts="0" result="Passed"/>'}
 'failure' {'<test-run total="1" passed="0" failed="1" skipped="0" inconclusive="0" asserts="1" result="Failed"><test-case name="fixture" result="Failed" asserts="1"/></test-run>'}
 default {'<test-run total="1" passed="1" failed="0" skipped="0" inconclusive="0" asserts="1" result="Passed"><test-case name="fixture" result="Passed" asserts="1"/></test-run>'}
}
[IO.File]::WriteAllText('.cache/report.xml',$xml)
'@
$v.checks+=@(
 @{id='build';command="if(Test-Path -LiteralPath '.cache/build-fail'){throw 'fixture build failed'}; if(-not (Test-Path -LiteralPath 'owned.txt' -PathType Leaf)){throw 'fixture source missing'}";working_directory='.';criteria=@('C1');inputs=@('.cache/build-input')},
 @{id='diff';command='git diff --check';working_directory='.';criteria=@('C1')}
)
[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
File $r '.cache/build-input' 'initial input'
$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
$ctx=Artifact $r $rp context;$design=Artifact $r $rp design @($ctx);ReviewArtifact $r $rp $design|Out-Null
$qa=Artifact $r $rp qa-plan @($design) @{scenarios=@(@{id='S1';inputs='fixture';expected='External requested behavior';expectation_source='user:implement';criterion_refs=@('C1');check_refs=@('build','diff','check-1');negative='Invalid input fails';boundary='Empty input'})}
$impl=Artifact $r $rp implementation-plan @($qa)
$payload=@{baseline_ref=$qa;dispositions=@(@{scenario_id='S1';status='PASS';expected='External requested behavior';evidence_refs=@('build','diff','check-1');drift='none'})}
$v.contract_status='final';[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
File $r 'owned.txt' 'authorized implementation'
Capture-ControlFlowCheck $r $rp check-1|Out-Null
$diff=Capture-ControlFlowCheck $r $rp diff
RejectsQAEvidence {Artifact $r $rp qa-recheck @($qa,$impl) $payload} 'MissingPlainCaptureCannotSatisfyQARecheck'
Assert ('QA_CAPTURE_MISSING_OR_STALE:build' -cin (Test-ControlFlowGate $r $rp Completion).reasons) 'MissingPlainCaptureBlocksCompletion'
Capture-ControlFlowCheck $r $rp build|Out-Null
File $r '.cache/build-fail' 'fail'
Capture-ControlFlowCheck $r $rp build|Out-Null
RejectsQAEvidence {Artifact $r $rp qa-recheck @($qa,$impl) $payload} 'LatestFailedPlainCaptureCannotReuseEarlierPass'
[IO.File]::Delete((Join-Path $r '.cache/build-fail'))
Capture-ControlFlowCheck $r $rp build|Out-Null
File $r '.cache/build-input' 'changed input'
RejectsQAEvidence {Artifact $r $rp qa-recheck @($qa,$impl) $payload} 'StaleDeclaredInputRejectsPlainQACapture'
Assert ('QA_CAPTURE_MISSING_OR_STALE:build' -cin (Test-ControlFlowGate $r $rp Completion).reasons) 'StalePlainInputBlocksCompletion'
$build=Capture-ControlFlowCheck $r $rp build
foreach($case in @(@{mode='missing';quality='NOT_RUN'},@{mode='zero';quality='FAIL'},@{mode='failure';quality='FAIL'})){
 File $r '.cache/report-mode' $case.mode
 $capture=Capture-ControlFlowCheck $r $rp check-1
 Assert ($capture.exit_code -eq 0 -and $capture.status -ceq 'FAIL' -and $capture.quality.status -ceq $case.quality) ('DeclaredReportOverridesExitZero:'+ $case.mode)
 RejectsQAEvidence {Artifact $r $rp qa-recheck @($qa,$impl) $payload} ('InvalidDeclaredReportRejectsQARecheck:'+ $case.mode)
}
File $r '.cache/report-mode' 'pass'
Capture-ControlFlowCheck $r $rp check-1|Out-Null
Assert ($build.status -ceq 'PASS' -and $diff.status -ceq 'PASS' -and -not $build.ContainsKey('quality') -and -not $diff.ContainsKey('quality')) 'PlainBuildAndDiffHaveProcessEvidenceWithoutQualityReports'
$recheck=$null
try{$recheck=Artifact $r $rp qa-recheck @($qa,$impl) $payload}catch{if($_.Exception.Message -cne 'QA_EVIDENCE_MISSING'){throw}}
Assert ($null -ne $recheck) 'FreshPlainAndReportCapturesSatisfyQARecheck'
Artifact $r $rp review-packet @($recheck)|Out-Null
Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('build','diff','check-1')}|Out-Null
Assert ((Test-ControlFlowGate $r $rp Completion).status -ceq 'PASS') 'MixedPlainAndReportQACapturesPermitCompletion'
Write-Output "qa-captures-v4: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
