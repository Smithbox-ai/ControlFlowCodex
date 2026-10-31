. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
$p=V4Contract $r final;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
$v.quality_profiles=@(@{id='mutation';kind='mutation';required=$true;check_ids=@();capability='unsupported'},@{id='lint-empty';kind='lint';required=$false;check_ids=@();capability='available'})
[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40));$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'UnsupportedRequiredProfileBlocks'
$v.quality_profiles[0].capability='available';$v.quality_profiles[0].check_ids=@('check-1');[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'NUnitReportCannotSatisfyMutationProfile'
$v.quality_profiles[0].capability='unsupported';$v.quality_profiles[0].check_ids=@()
$v.quality_profiles[0].required=$false;[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
$cap=Capture-ControlFlowCheck $r $rp check-1
Assert ($cap.quality.assertion_count -eq 1 -and $cap.quality.status -ceq 'PASS') 'ActualNUnitAssertionCaptured'
Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
$packet=Artifact $r $rp review-packet
Assert ((Test-ControlFlowGate $r $rp Completion).status -ceq 'PASS') 'OptionalUnsupportedDoesNotBlockLight'
$raw=Get-Content (Join-Path $rp $packet.path) -Raw|ConvertFrom-Json -AsHashtable
Assert ($raw.profile_summary[0].status -ceq 'UNSUPPORTED' -and $raw.evidence_summary[0].status -ceq 'PASS') 'PacketDistinguishesCapabilityAndEvidence'
Assert ($raw.profile_summary[1].status -ceq 'NOT_RUN') 'EmptyOptionalProfileIsNotPass'
Update-ControlFlowRun $r $rp @{type='complete'}|Out-Null
Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:reopen'}} 'CompletedV4CannotReopen'
Write-Output "quality-profiles-v4: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
