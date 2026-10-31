. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
$p=Contract $r
$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.schema_version='4.0.0';$v.contract_status='draft';$v.work_type='feature'
$v.domain=@{classification='supporting';rationale='Existing bounded behavior';refs=@('owned.txt')}
$v.intent=@{non_goals=@('New orchestrator');constraints=@('Native permissions');user_decisions=@('user:implement')}
$v.workflow=@{profile='feature';required_artifacts=@('context','design','qa-plan','implementation-plan','qa-recheck','review-packet')}
$v.review_policy=@{assurance='manual';requirements=@(@{target_id='C1';judges=@('code')});human_design=$true;human_final=$false}
$v.quality_profiles=@();$v.criteria=@();$v.checks=@()
function SaveV { [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40)) }
SaveV
Assert ((Read-ControlFlowContract $p).contract.contract_status -ceq 'draft') 'V4DraftValid'
$v.schema_version='4.0.1';SaveV;Throws {Read-ControlFlowContract $p} 'V4UnknownVersionRejected';$v.schema_version='4.0.0'
$v.contract_status='final';SaveV;Throws {Read-ControlFlowContract $p} 'FinalRequiresCompleteContract'
$v.criteria=@(@{id='C1';text='Human accepts behavior'});$v.review_policy.requirements[0].judges=@('human');SaveV
Assert ((Read-ControlFlowContract $p).contract.checks.Count -eq 0) 'HumanOnlyCriterionNeedsNoDummyCheck'
$v.review_policy.requirements[0].judges=@('code');SaveV;Throws {Read-ControlFlowContract $p} 'CodeCriterionNeedsCheck'
$v.checks=@(@{id='check-1';command='Write-Output ok';working_directory='.';criteria=@('C1')});SaveV
Assert ((Read-ControlFlowContract $p).contract.schema_version -ceq '4.0.0') 'V4FinalValid'
$v.workflow.profile='invented';SaveV;Throws {Read-ControlFlowContract $p} 'UnknownWorkflowRejected';$v.workflow.profile='feature'
$v.workflow.required_artifacts=@('review-packet');SaveV;Throws {Read-ControlFlowContract $p} 'FixedProfileCannotDropPrerequisites'
foreach($work in @('feature','bugfix','refactor','docs')) {
 $route=Get-ControlFlowClassification -SchemaVersion '4.0.0' -WorkType $work -Domain supporting -ChangedFiles 1
 Assert ($route.workflow.profile -cin @('light','feature','bugfix','refactor','docs')) ('EveryRoutedWorkTypeHasFixedProfile:'+ $work)
}
$route=Get-ControlFlowClassification -SchemaVersion '4.0.0' -WorkType feature -Domain core -ChangedFiles 1
Assert ($route.review_policy.human_design -and $route.workflow.profile -ceq 'feature') 'TinyCoreCannotBypassHuman'
$route=Get-ControlFlowClassification -SchemaVersion '4.0.0' -WorkType docs -Domain generic -ChangedFiles 1
Assert ($route.workflow.profile -ceq 'light') 'TrivialSafeDocsLight'
Assert ($route.tier -ceq 'SMALL') 'V4PersistedTierMatchesSchema'
$v.workflow=$route.workflow;$v.tier=$route.tier;$v.work_type='docs';$v.domain.classification='generic';$v.review_policy.human_design=$false;SaveV
Assert ((Read-ControlFlowContract $p).contract.workflow.profile -ceq 'light') 'ClassifierContractRoundTrip'
$p=Contract $r;Assert ((Read-ControlFlowContract $p).contract.schema_version -ceq '3.0.0') 'V3StillValid'
$run=Start-ControlFlowRun $r $p -ManualFallback
$old=[IO.File]::ReadAllText($p);SaveV
Throws {Read-ControlFlowRun $r $run.run_path} 'V3RuntimeRejectsV4Replacement'
[IO.File]::WriteAllText($p,$old)
$dest=Join-Path $r 'v4.json'
& "$script:CoreRoot/scripts/migrate-contract.ps1" -Path $p -OutputPath $dest -TaskId migrated -TargetVersion '4.0.0' | Out-Null
Assert ($LASTEXITCODE -eq 0) 'ExplicitV4Migration'
$m=Get-Content $dest -Raw|ConvertFrom-Json -AsHashtable
Assert ($m.commit.mode -ceq 'none' -and $m.contract_status -ceq 'draft' -and -not $m.ContainsKey('approvals')) 'MigrationCopiesNoApprovals'
Write-Output "contract-v4: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
