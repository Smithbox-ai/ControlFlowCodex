. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$foreignCore=New-Module -Name ControlFlow.Core -ScriptBlock {}
Import-Module $foreignCore
Assert (@(Get-Module ControlFlow.Core).Count -ge 2) 'assessment tests exercise duplicate loaded module names'
$script:Failures=@()
function Case([string]$Name,[scriptblock]$Body) {
 try { & $Body; Write-Output "PASS $Name" } catch { $script:Failures+=($Name+': '+$_.Exception.Message); Write-Output "FAIL $Name`: $($_.Exception.Message)" }
}
function AssessmentContract {
 $v=Get-Content "$script:CoreRoot/plans/templates/plan.meta.v4.json" -Raw|ConvertFrom-Json -AsHashtable
 $v.contract_status='final';$v.domain.classification='supporting';$v.review_policy.human_final=$false
 $v.criteria+=@(@{id='C2';text='Another behavior'})
 $v.review_policy.requirements+=@(@{target_id='C2';judges=@('human')})
 return $v
}
function AssessmentPayload([string]$Decision='run',[string]$Method='controlled') {
 return @{scenarios=@(@{id='S1';inputs='fixture';expected='Invalid state fails';expectation_source='user:implement';criterion_refs=@('C1');check_refs=@('check-1');negative='Invalid input';boundary='Empty input'});mutation_assessment=@{decision=$Decision;method=$Method;rationale='Sensitive branching warrants a bounded audit';scope=@('src/decision.ps1');criterion_refs=@('C1');check_refs=@(if($Decision -ceq 'run'){'check-1'});budget='At most five minutes and ten mutants';acceptance='Every selected mutant is detected'}}
}
function Guard($Contract,$Payload) { & (Get-TestControlFlowModule) {param($C,$P) Assert-CFV4MutationAssessment $C $P} $Contract $Payload }
function RejectAssessment($Contract,$Payload,[string]$Message) {
 $failure=$null;try {Guard $Contract $Payload}catch{$failure=$_.Exception.Message}
 Assert ($null -ne $failure -and $failure.StartsWith('MUTATION_ASSESSMENT_')) $Message
}
function RejectContract($Contract,[string]$Message) {
 $failure=$null;try {& (Get-TestControlFlowModule) {param($C) Assert-CFV4Contract $C} $Contract}catch{$failure=$_.Exception.Message}
 Assert ($failure -ceq 'REQUIRED_MUTATION_MINIMUM_SCORE_REQUIRED') $Message
}
function MutationReport {
 return @{format='stryker-json';path='.cache/mutation.json';tool='Stryker';version='fixture';scope=@('src/decision.ps1');config='stryker-config.json';baseline='initial';exclusions=@()}
}
function MutationContract {
 $v=AssessmentContract;$v.checks[0].report=MutationReport
 $v.quality_profiles=@(@{id='mutation';kind='mutation';required=$true;check_ids=@('check-1');capability='available'})
 return $v
}
Case 'RequiredFinalMutationReportNeedsThreshold' {RejectContract (MutationContract) 'required final mutation threshold missing is rejected'}
Case 'RequiredFinalMutationReportRejectsZeroThreshold' {$v=MutationContract;$v.checks[0].report.minimum_score=0;RejectContract $v 'zero threshold cannot satisfy required mutation profile'}
Case 'RequiredFinalMutationReportAcceptsPositiveThreshold' {$v=MutationContract;$v.checks[0].report.minimum_score=75;& (Get-TestControlFlowModule) {param($C) Assert-CFV4Contract $C} $v;Assert $true 'positive threshold accepted'}
Case 'OptionalMeasurementNeedsNoThreshold' {$v=MutationContract;$v.quality_profiles[0].required=$false;& (Get-TestControlFlowModule) {param($C) Assert-CFV4Contract $C} $v;Assert $true 'optional measurement accepted'}
Case 'DraftMutationProfileNeedsNoThreshold' {$v=MutationContract;$v.contract_status='draft';& (Get-TestControlFlowModule) {param($C) Assert-CFV4Contract $C} $v;Assert $true 'draft can defer threshold selection'}
Case 'UnsupportedProfileRetainsPreflightValidation' {$v=MutationContract;$v.quality_profiles[0].capability='unsupported';& (Get-TestControlFlowModule) {param($C) Assert-CFV4Contract $C} $v;Assert $true 'unsupported capability is left to preflight'}
Case 'CodeQaRequiresAssessment' {$p=AssessmentPayload;[void]$p.Remove('mutation_assessment');RejectAssessment (AssessmentContract) $p 'code QA cannot silently omit mutation assessment'}
Case 'JustifiedSkipAccepted' {Guard (AssessmentContract) (AssessmentPayload skip none);Assert $true 'justified skip accepted'}
Case 'UnsupportedAcceptedWithoutInstallingTool' {Guard (AssessmentContract) (AssessmentPayload unsupported none);Assert $true 'unsupported decision records limitation'}
Case 'HumanOnlyQaWithoutProfilesExempt' {$v=AssessmentContract;foreach($req in $v.review_policy.requirements){$req.judges=@('human')};Guard $v @{scenarios=@()};Assert $true 'human-only QA requires no dummy assessment'}
Case 'HumanOnlyQaWithMutationProfileRequiresAssessment' {$v=MutationContract;foreach($req in $v.review_policy.requirements){$req.judges=@('human')};RejectAssessment $v @{scenarios=@()} 'mutation profile requires an explicit decision'}
Case 'LightRouteExempt' {$v=AssessmentContract;$v.workflow.profile='light';Guard $v @{scenarios=@()};Assert $true 'light route exempt'}
Case 'V3Exempt' {$v=AssessmentContract;$v.schema_version='3.0.0';Guard $v @{scenarios=@()};Assert $true 'V3 remains readable'}
Case 'ValidControlledAssessmentAccepted' {Guard (AssessmentContract) (AssessmentPayload);Assert $true 'controlled audit binds to declared QA check'}
Case 'ValidStrykerAssessmentAccepted' {$v=MutationContract;$v.checks[0].report.minimum_score=75;Guard $v (AssessmentPayload run stryker);Assert $true 'Stryker audit binds to recognized mutation profile'}
Case 'EveryAssessedCriterionNeedsCheckCoverage' {$p=AssessmentPayload;$p.mutation_assessment.criterion_refs=@('C1','C2');RejectAssessment (AssessmentContract) $p 'an extra assessed criterion cannot claim evidence from an unrelated check'}
Case 'StrykerScopeMustMatchLinkedReportScope' {$v=MutationContract;$v.checks[0].report.scope=@('src/unrelated.ps1');RejectAssessment $v (AssessmentPayload run stryker) 'assessed files must match linked Stryker report scope'}
Case 'StrykerScopeCannotOmitReportedFiles' {$v=MutationContract;$v.checks[0].report.scope=@('src/decision.ps1','src/other.ps1');RejectAssessment $v (AssessmentPayload run stryker) 'assessment must describe every referenced report file'}
Case 'StrykerScopeMatchIsCaseSensitive' {$v=MutationContract;$v.checks[0].report.scope=@('src/Decision.ps1');RejectAssessment $v (AssessmentPayload run stryker) 'Stryker file scope uses case-sensitive repository paths'}
Case 'StrykerMultiCheckScopeUnionAccepted' {
 $v=MutationContract;$v.checks[0].report.minimum_score=75
 $second=$v.checks[0]|ConvertTo-Json -Depth 40|ConvertFrom-Json -AsHashtable
 $second.id='check-2';$second.criteria=@('C2');$second.report.path='.cache/mutation2.json';$second.report.scope=@('src/other.ps1','src/decision.ps1')
 $v.checks+=@($second);$v.quality_profiles[0].check_ids=@('check-1','check-2')
 $p=AssessmentPayload run stryker;$p.mutation_assessment.scope=@('src/other.ps1','src/decision.ps1');$p.mutation_assessment.criterion_refs=@('C1','C2');$p.mutation_assessment.check_refs=@('check-1','check-2')
 $p.scenarios+=@(@{id='S2';inputs='fixture';expected='Other behavior';expectation_source='user:implement';criterion_refs=@('C2');check_refs=@('check-2');negative='Invalid input';boundary='Empty input'})
 Guard $v $p;Assert $true 'multiple checks can report overlapping files in the exact aggregate assessment scope'
}
Case 'UnknownCriterionRejected' {$p=AssessmentPayload;$p.mutation_assessment.criterion_refs=@('imaginary');RejectAssessment (AssessmentContract) $p 'unknown assessed criterion rejected'}
Case 'UnknownCheckRejected' {$p=AssessmentPayload;$p.mutation_assessment.check_refs=@('imaginary');RejectAssessment (AssessmentContract) $p 'unknown assessed check rejected'}
Case 'UnrelatedCheckRejected' {$v=AssessmentContract;$v.checks[0].criteria=@('C2');RejectAssessment $v (AssessmentPayload) 'check must target assessed criterion'}
Case 'CheckOutsideScenarioRejected' {$p=AssessmentPayload;$p.scenarios[0].check_refs=@();RejectAssessment (AssessmentContract) $p 'audit check must be captured through a QA scenario'}
Case 'ScenarioMustLinkAssessedCriterionAndCheck' {$p=AssessmentPayload;$p.scenarios[0].criterion_refs=@('C2');RejectAssessment (AssessmentContract) $p 'unrelated scenario cannot carry mutation evidence'}
Case 'StrykerRequiresRecognizedReport' {RejectAssessment (AssessmentContract) (AssessmentPayload run stryker) 'Stryker decision cannot use an ordinary check'}
Case 'StrykerRequiresMutationProfile' {$v=MutationContract;$v.quality_profiles=@();RejectAssessment $v (AssessmentPayload run stryker) 'Stryker check must belong to mutation profile'}
Case 'SkipCannotDeclareRunChecks' {$p=AssessmentPayload skip none;$p.mutation_assessment.check_refs=@('check-1');RejectAssessment (AssessmentContract) $p 'skip does not claim executed mutation checks'}
Case 'SkipMustUseNoneMethod' {RejectAssessment (AssessmentContract) (AssessmentPayload skip controlled) 'skip must use method none'}
Case 'WhitespaceRationaleRejected' {$p=AssessmentPayload;$p.mutation_assessment.rationale=' ';RejectAssessment (AssessmentContract) $p 'rationale must explain decision'}
foreach($field in @('budget','acceptance','scope','criterion_refs','check_refs')) {
 $fieldName=$field
 Case "RunRequires$fieldName" {$p=AssessmentPayload;[void]$p.mutation_assessment.Remove($fieldName);RejectAssessment (AssessmentContract) $p ('run requires '+$fieldName)}
}
foreach($path in @('/rooted.ps1','../outside.ps1','src/../outside.ps1','src/*.ps1','src/[a].ps1','src\decision.ps1','src/','src//decision.ps1','C:decision.ps1')) {
 $invalidPath=$path
 Case "LiteralScope:$invalidPath" {$p=AssessmentPayload;$p.mutation_assessment.scope=@($invalidPath);RejectAssessment (AssessmentContract) $p ('scope must be a literal repo-relative file: '+$invalidPath)}
}
Case 'HumanPhaseCodeJudgmentRequiresAssessment' {$v=AssessmentContract;$v.review_policy.requirements=@(@{target_id='P1';judges=@('code')});$v.phases=@(@{id='P1';criteria=@('C1')});RejectAssessment $v @{scenarios=@()} 'phase code judgment also requires mutation decision'}
Case 'HistoricalQaSchemaRemainsReadable' {
 $p=AssessmentPayload;[void]$p.Remove('mutation_assessment')
 $a=@{schema_version='1.0.0';artifact_id=('a'*32);kind='qa-plan';revision=1;task_id='test';run_id=('b'*32);planning_epoch_id=0;source_digest=('a'*64);intent_digest=('b'*64);policy_digest=('c'*64);inputs=@();policy_refs=@('docs/policy.md');criterion_refs=@('C1');payload=$p}
 Assert (Test-Json -Json ($a|ConvertTo-Json -Depth 40) -SchemaFile "$script:CoreRoot/schemas/phase-artifact-v1.schema.json") 'historical QA without assessment remains schema-valid'
 $a.payload=AssessmentPayload
 Assert (Test-Json -Json ($a|ConvertTo-Json -Depth 40) -SchemaFile "$script:CoreRoot/schemas/phase-artifact-v1.schema.json") 'new assessment is schema-valid'
 $a.payload.mutation_assessment.decision='silently-ignore'
 Assert (-not (Test-Json -Json ($a|ConvertTo-Json -Depth 40) -SchemaFile "$script:CoreRoot/schemas/phase-artifact-v1.schema.json" -ErrorAction SilentlyContinue)) 'assessment shape is schema-validated'
}
if($script:Failures.Count -gt 0){throw ($script:Failures -join "`n")}
Remove-Module -ModuleInfo $foreignCore
Write-Output "mutation-assessment-v4: $script:Count assertions passed"
$global:LASTEXITCODE=0
