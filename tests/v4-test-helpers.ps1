. "$PSScriptRoot/core-test-helpers.ps1"
function V4Contract($Root,[string]$Status='draft',[string]$Session='') {
 $p=(Get-ControlFlowStoragePaths $Root 'test-task' $Session -Create).contract_path
 $v=Get-Content "$script:CoreRoot/plans/templates/plan.meta.v4.json" -Raw|ConvertFrom-Json -AsHashtable
 $v.task_id='test-task';$v.baseline.commit=Git $Root @('rev-parse','HEAD');$v.scope=@('owned.txt')
 $v.contract_status=$Status;$v.domain=@{classification='supporting';rationale='Bounded fixture';refs=@('owned.txt')}
 $v.review_policy.human_final=$false;$v.checks[0].id='check-1'
 File $Root '.git/info/exclude' '.cache/'
 $v.checks[0].command="if(-not (Test-Path -LiteralPath 'owned.txt' -PathType Leaf)){throw 'fixture behavior absent'}; [IO.Directory]::CreateDirectory('.cache')|Out-Null; [IO.File]::WriteAllText('.cache/report.xml','<test-run total=""1"" passed=""1"" failed=""0"" skipped=""0"" inconclusive=""0"" asserts=""1"" result=""Passed""><test-case name=""file exists"" result=""Passed"" asserts=""1""/></test-run>')"
 $v.checks[0].report=@{format='nunit3';path='.cache/report.xml';minimum_tests=1;tool='fixture assertions';version='1';scope=@('owned.txt');config='inline';baseline='initial';exclusions=@()}
 [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40));return $p
}
function Artifact($Root,$Run,$Kind,$Inputs=@(),$Payload=$null,[int]$Revision=1) {
 $b=Get-ControlFlowPlanningContext $Root $Run
 if($null -eq $Payload){$Payload=switch($Kind){
 'context' {@{goals=@('Requested behavior');non_goals=@('Deploy');decisions=@('user:implement');assumptions=@();unknowns=@();code_refs=@('owned.txt');invariants=@('Native authority')}}
 'design' {@{behavior='Bounded behavior';boundaries=@('owned.txt');data_dependencies=@();selected='Minimal change';rejected_alternative='New orchestrator';risks=@('Regression');rollback='Restore owned diff'}}
 'qa-plan' {@{scenarios=@(@{id='S1';inputs='fixture';expected='External requested behavior';expectation_source='user:implement';criterion_refs=@('C1');check_refs=@('check-1');negative='Invalid input fails';boundary='Empty input'})}}
 'implementation-plan' {@{parts=@(@{id='part-1';components=@('owned.txt');depends_on=@();readiness='QA baseline approved';criterion_refs=@('C1')})}}
 'qa-recheck' {@{baseline_ref=$Inputs[0];dispositions=@(@{scenario_id='S1';status='PASS';expected='External requested behavior';evidence_refs=@('check-1');drift='none'})}}
 'review-packet' {@{changes=@('Bounded behavior');invariants=@('Native ownership');diff_refs=@('owned.txt');results=@('check-1');limitations=@('Manual assurance');open_decisions=@();rollback='Restore diff'}}
 }}
 $a=@{schema_version='1.0.0';artifact_id=[guid]::NewGuid().ToString('N');kind=$Kind;revision=$Revision;task_id=$b.task_id;run_id=$b.run_id;planning_epoch_id=$b.planning_epoch_id;source_digest=$b.source_digest;intent_digest=$b.intent_digest;policy_digest=$b.policy_digest;inputs=@($Inputs);policy_refs=@('docs/architecture-policy.md');criterion_refs=@('C1');payload=$Payload}
 Update-ControlFlowRun $Root $Run @{type='artifact';artifact=$a}|Out-Null
 return (Get-ControlFlowPlanningContext $Root $Run).artifacts[$Kind]
}
function ReviewArtifact($Root,$Run,$Ref,[string]$Judge='human',[string]$Verdict='APPROVED',[string]$Assurance='manual',[string]$Target='design') {
 Update-ControlFlowRun $Root $Run @{type='phase_review';artifact_ref=$Ref;target_id=$Target;judge=$Judge;verdict=$Verdict;assurance=$Assurance;user_decision_ref='user:decision'}
}
function Planning($Root,$Run) {
 $c=Artifact $Root $Run 'context';$d=Artifact $Root $Run 'design' @($c)
 ReviewArtifact $Root $Run $d|Out-Null
 $q=Artifact $Root $Run 'qa-plan' @($d);$i=Artifact $Root $Run 'implementation-plan' @($q)
 return @{context=$c;design=$d;qa=$q;implementation=$i}
}
