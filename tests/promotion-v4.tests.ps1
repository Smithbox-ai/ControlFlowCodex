. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$r=NewFixture
try{
$p=V4Contract $r;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.criteria+=@(@{id='C2';text='Second external behavior'});$v.review_policy.requirements+=@(@{target_id='C2';judges=@('code')})
$check=$v.checks[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json -AsHashtable;$check.id='check-2';$check.criteria=@('C2');$check.report.path='.cache/report2.xml';$check.command=$check.command.Replace('report.xml','report2.xml');$v.checks+=@($check)
[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40));$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
$ctx=Artifact $r $rp context;$design=Artifact $r $rp design @($ctx);ReviewArtifact $r $rp $design|Out-Null
$qa=Artifact $r $rp qa-plan @($design) @{scenarios=@(
 @{id='S1';inputs='one';expected='first';expectation_source='user';criterion_refs=@('C1');check_refs=@('check-1');negative='invalid';boundary='empty'},
 @{id='S2';inputs='two';expected='second';expectation_source='user';criterion_refs=@('C2');check_refs=@('check-2');negative='invalid';boundary='empty'});mutation_assessment=@{decision='skip';method='none';rationale='This fixture tests immutable QA bindings during contract promotion; mutation sensitivity is outside its scope';scope=@();criterion_refs=@();check_refs=@()}}
$impl=Artifact $r $rp implementation-plan @($qa)
$v.contract_status='final';$v.checks[0].criteria=@('C2');$v.checks[1].criteria=@('C1');[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'FinalPromotionRejectsReassignedQAChecks'
$v.checks[0].criteria=@('C1');$v.checks[1].criteria=@('C2');$text=$v.criteria[0].text;$v.criteria[0].text='Changed expectation meaning';[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'FinalPromotionRejectsChangedCriterionMeaning'
$v.criteria[0].text=$text;[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
Assert ((Read-ControlFlowRun $r $rp).state.preflight_digest -ceq (Read-ControlFlowContract $p).digest) 'ExactQABindingsPromote'
Write-Output "promotion-v4: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
