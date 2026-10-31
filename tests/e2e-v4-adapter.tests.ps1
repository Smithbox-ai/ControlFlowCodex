$ErrorActionPreference='Stop'
. "$PSScriptRoot/v4-test-helpers.ps1"
. "$PSScriptRoot/../evals/e2e-lib.ps1"
$oldStateRoot=$env:CONTROLFLOW_STATE_ROOT
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cf-v4-adapter-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
function Clone($Value){return ($Value|ConvertTo-Json -Depth 80|ConvertFrom-Json -AsHashtable)}
function Capture($Events){return @{stdout=(@($Events|ForEach-Object {$_|ConvertTo-Json -Depth 20 -Compress}) -join "`n")+"`n";exit_code=0;timed_out=$false;streams_complete=$true;cleanup_verified=$true;budget_reason=''}}
$id='11111111-1111-7111-8111-111111111111'
$events=@(@{type='thread.started';thread_id=$id},@{type='turn.started'},@{type='item.completed';item=@{id='i0';type='agent_message';text='done'}},@{type='turn.completed';usage=@{input_tokens=20;cached_input_tokens=5;output_tokens=3}})
try {
 Assert ([bool](Get-Command Get-E2ECollectedUsage -ErrorAction SilentlyContinue)) 'CollectorSeparationRequired'
 $capture=Capture $events
 $u=Get-E2ECollectedUsage -Collector stdout-jsonl -Capture $capture
 Assert ($u.root_complete -and $u.observed_root_usage.total_tokens -eq 23) 'StdoutRootUsageRecognized'
 Assert (-not $u.complete -and $null -eq $u.total_tokens -and -not $u.actual_context.verified) 'RootUsageIsNotCompleteChildOrContextProof'
 foreach($mutation in @('duplicate','negative','truncated','bad-thread','wrong-order','failed-process','unknown-item','duplicate-item','cached-overflow','missing-turn')){
  $e=Clone $events;$c=Clone $capture
  switch($mutation){
   duplicate {$e+=Clone $events[-1]}
   negative {$e[-1].usage.input_tokens=-1}
   truncated {$c.stdout+='{"type":'}
   bad-thread {$e[0].thread_id='wrong'}
   wrong-order {$e=@($e[-1])+$e[0..2]}
   failed-process {$c.exit_code=1}
   unknown-item {$e[2].item.type='future_tool'}
   duplicate-item {$e=@($e[0],$e[1],$e[2],$e[2],$e[3])}
   cached-overflow {$e[-1].usage.cached_input_tokens=21}
   missing-turn {$e=@($e[0],$e[2],$e[3])}
  }
  if($mutation -notin @('truncated','failed-process')){$c=Capture $e}
  $bad=Get-E2ECollectedUsage -Collector stdout-jsonl -Capture $c
  Assert (-not $bad.root_complete -and -not $bad.complete) "IncompleteStdout:$mutation"
 }
 $none=Get-E2ECollectedUsage -Collector stdout-jsonl -Capture (Capture @())
 Assert ($null -eq $none.observed_root_usage -and $null -eq $none.total_tokens) 'MissingUsageNotZero'
 # Requested settings, local booleans and invented capability receipts cannot enable generation.
 $config=@{Variant='v4';Collector='stdout-jsonl';ActualContext=@{verified=$true};IsolationVerified=$true;ChildUsageVerified=$true;ProtocolCapabilities=@{verified=$true}}
 $ready=Get-E2EProtocolReadiness -Config $config
 Assert (-not $ready.may_launch -and $ready.status -ceq 'UNSUPPORTED') 'SelfAttestationCannotEnableModelLaunch'
 $config.CliPath=Join-Path $temp 'must-not-start.exe';$config.SessionRoot=Join-Path $temp 'must-not-read';$config.Model='no-model';$config.Effort='high';$config.HostLabel='fixture';$config.MaxTokens=100;$config.MaxToolCalls=10;$config.MaxWallSeconds=2
 $case=@{id='fixture';tier='SMALL';task='Fix requested behavior'}
 $blocked=Invoke-E2ETrial -Case $case -Config $config -TrialDirectory (Join-Path $temp 'blocked')
 Assert ($blocked.protocol_blocked_before_generation -and -not $blocked.generation_started -and $blocked.spend_status -ceq 'not-generated-protocol-block') 'V4BlockedBeforeAnyCliOrSessionRead'
 $n=Clone $config;$n.Variant='native'
 Assert ((Invoke-E2ETrial $case $n (Join-Path $temp 'native-blocked')).protocol_blocked_before_generation) 'NativeStdoutArmAlsoBlocked'
 $upper=Clone $n;$upper.Collector='STDOUT-JSONL';$upper.Variant='NATIVE'
 Assert ((Invoke-E2ETrial $case $upper (Join-Path $temp 'uppercase-blocked')).protocol_blocked_before_generation) 'ApiCasingCannotBypassProtocolGate'
 $legacy=@{Variant='v3';Collector='legacy-rollout'}
 Assert ((Get-E2EProtocolReadiness -Config $legacy).collector -ceq 'legacy-rollout') 'LegacyCollectorRemainsSeparate'
 Throws {Get-E2EProtocolReadiness @{Variant='v5';Collector='legacy-rollout'}} 'UnknownTreatmentRejected'
 Throws {Get-E2EProtocolReadiness @{Variant='v4';Collector='legacy-rollout'}} 'V4CannotFallBackToSessionCollector'
 LoadCore
 $r=NewFixture
 try {
  $t=New-E2EV4Treatment -Case $case -FixtureRoot $r -TrialDirectory (Join-Path $temp 'treatment') -PluginRoot $script:CoreRoot
  Assert ($t.environment.CONTROLFLOW_STATE_ROOT -ceq $t.binding.state_root -and $t.prompt -match '4.0.0' -and $t.prompt -match 'manual' -and $t.binding.task_id -match '^eval-') 'ActualV4TreatmentHasBoundExternalStateAndExplicitOptIn'
  Assert (@($t.environment.Keys|Where-Object {$_ -in @('HOME','USERPROFILE','CODEX_HOME')}).Count -eq 0) 'TreatmentDoesNotOverrideIdentity'
  Throws {New-E2EV4Treatment -Case $case -FixtureRoot $r -TrialDirectory (Join-Path $temp 'treatment') -PluginRoot $script:CoreRoot} 'TreatmentCannotReuseEvidenceDirectory'
  $env:CONTROLFLOW_STATE_ROOT=$t.binding.state_root
  $p=V4Contract $r -Session $id;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
  $v.task_id=$t.binding.task_id;$paths=Get-ControlFlowStoragePaths $r $v.task_id $id -Create
  [IO.File]::WriteAllText($paths.contract_path,($v|ConvertTo-Json -Depth 40))
  $run=Start-ControlFlowRun $r $paths.contract_path $id
  $context=Artifact $r $run.run_path context
  $proof=Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId $id
  Assert ($proof.integrity_verified -and $proof.run_id -ceq $run.run_id -and $proof.source_digest -ceq $t.binding.initial_source_digest) 'RealRuntimeReceiptsBoundToFixtureTaskSessionSource'
  Assert (-not $proof.workflow_complete -and -not $proof.verified_human -and $proof.assurance -ceq 'local-runtime-integrity') 'DraftReceiptIsNotCompletionOrVerifiedHuman'
  $contractBytes=[IO.File]::ReadAllBytes($paths.contract_path);$foreign=Clone $v;$foreign.task_id='foreign-task'
  [IO.File]::WriteAllText($paths.contract_path,($foreign|ConvertTo-Json -Depth 40))
  Assert (-not (Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId $id).integrity_verified) 'ContractTaskCannotEscapeTreatmentBinding'
  [IO.File]::WriteAllBytes($paths.contract_path,$contractBytes)
  $wrong=Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId '22222222-2222-7222-8222-222222222222'
  Assert (-not $wrong.integrity_verified) 'WrongNativeThreadRejected'
  $wrong=Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId $id -ExpectedRunId ('f'*32)
  Assert (-not $wrong.integrity_verified) 'OldRunReceiptRejected'
  File $r 'owned.txt' 'source changed'
  Assert (-not (Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId $id).source_current) 'SourceEditDoesNotReuseGreenReceipt'
  File $r 'owned.txt' 'initial'
  $artifactPath=Join-Path $run.run_path $context.path;$saved=[IO.File]::ReadAllBytes($artifactPath);[IO.File]::WriteAllText($artifactPath,'{}')
  Assert (-not (Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId $id).integrity_verified) 'TamperedArtifactRejected'
  [IO.File]::WriteAllBytes($artifactPath,$saved)
  $design=Artifact $r $run.run_path design @($context)
  ReviewArtifact $r $run.run_path $design human UNKNOWN|Out-Null
  $wait=Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId $id
  Assert ($wait.integrity_verified -and $wait.lawful_stop -and -not $wait.workflow_complete -and -not $wait.verified_human) 'HumanWaitIsNotAutomaticApprovalOrCompletion'
  Assert ($wait.decisions[0].assurance -ceq 'manual' -and $wait.pending_human_targets -ccontains 'design') 'ManualAssuranceAndWaitTargetRemainVisible'
  $forged=Clone $t;$forged.binding.task_id='another-task'
  Assert (-not (Read-E2EV4RuntimeReceipt -Treatment $forged -ThreadId $id).integrity_verified) 'ForeignTaskTreatmentRejected'
  $requestBytes=[IO.File]::ReadAllBytes($t.request_path);[IO.File]::WriteAllText($t.request_path,'{}')
  Assert (-not (Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId $id).integrity_verified) 'TamperedTreatmentRejected'
  [IO.File]::WriteAllBytes($t.request_path,$requestBytes)
 } finally {$env:CONTROLFLOW_STATE_ROOT=$oldStateRoot;RemoveFixture $r}
 # Deterministically publish a real runtime event between the adapter's API
 # reads. Only a scratch module copy adds this interleaving; production core
 # and the collector under test are unchanged.
 $copy=Join-Path $temp 'race-plugin';[IO.Directory]::CreateDirectory($copy)|Out-Null
 foreach($relative in @('scripts','schemas','plugin.json')){Copy-Item -LiteralPath (Join-Path $script:CoreRoot $relative) -Destination (Join-Path $copy $relative) -Recurse}
 $modulePath=Join-Path $copy 'scripts/ControlFlow.Core.psm1';$moduleText=[IO.File]::ReadAllText($modulePath)
 $interleave=@'
$script:E2EOriginalPlanning=${function:Get-ControlFlowPlanningContext}
function Get-ControlFlowPlanningContext {
 param($RepoRoot,$RunPath)
 $value=& $script:E2EOriginalPlanning $RepoRoot $RunPath
 Update-ControlFlowRun $RepoRoot $RunPath @{type='blocker';id='concurrent-publication';status='OPEN';text='Fixture publication between collector reads'}|Out-Null
 return $value
}
'@
 [IO.File]::WriteAllText($modulePath,$moduleText.Replace('Export-ModuleMember -Function *-ControlFlow*',$interleave+"`nExport-ModuleMember -Function *-ControlFlow*"))
 $r=NewFixture
 try{
  $t=New-E2EV4Treatment -Case $case -FixtureRoot $r -TrialDirectory (Join-Path $temp 'race-treatment') -PluginRoot $copy
  $env:CONTROLFLOW_STATE_ROOT=$t.binding.state_root
  $p=V4Contract $r -Session $id;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable;$v.task_id=$t.binding.task_id
  $paths=Get-ControlFlowStoragePaths $r $v.task_id $id -Create;[IO.File]::WriteAllText($paths.contract_path,($v|ConvertTo-Json -Depth 40))
  $run=Start-ControlFlowRun $r $paths.contract_path $id
  $proof=Read-E2EV4RuntimeReceipt -Treatment $t -ThreadId $id
  Assert (-not $proof.integrity_verified -and $proof.reason -ceq 'E2E_RUNTIME_CHANGED_DURING_COLLECTION') 'ConcurrentPublicationCannotMixReceiptSnapshots'
 }finally{$env:CONTROLFLOW_STATE_ROOT=$oldStateRoot;RemoveFixture $r}
 $v4=@{schema_version='2.0.0';variant='v4';case_id='fixture';tier='SMALL';trial=1;status='success';usage=@{complete=$true;total_tokens=0};provenance=@{};runtime=@{integrity_verified=$true;verified_human=$true}}
 $native=Clone $v4;$native.variant='native'
 $pairs=Measure-E2EPairs -Results @($native,$v4) -Treatment v4
 Assert ($pairs.schema_version -ceq '2.0.0' -and $pairs.treatment -ceq 'v4' -and $pairs.paired_trials -eq 1 -and $pairs.incomplete_metrics_pairs -eq 1 -and $null -eq $pairs.success_delta -and -not $pairs.production_ready) 'VersionedV4PairCannotPromoteForgedProvenance'
 Assert ($pairs.pairs[0].ContainsKey('v4') -and -not $pairs.pairs[0].ContainsKey('v3')) 'V4PairNeverRelabelsV3'
 $v3=Clone $v4;$v3.variant='v3'
 Throws {Measure-E2EPairs -Results @($native,$v3) -Treatment v4} 'V3CannotEnterV4Pair'
 Throws {Measure-E2EPairs -Results @($native,$v4,$v4) -Treatment v4} 'DuplicateV4PairRejected'
 $comparison=@{model='a';effort='high';host='same';fixture_hash=('a'*64);project_trust='untrusted';sandbox='workspace-write';windows_sandbox='unelevated';approval_policy='never';approvals_reviewer='user';cli_version='fixture';settings=@();budget=@{tokens=100;tools=10;wall_seconds=10};collector='stdout-jsonl';protocol_version='exec-jsonl-root-v1';plugin_sha256=('b'*64)}
 $v4.provenance=Clone $comparison;$native.provenance=Clone $comparison;$native.provenance.model='b'
 Throws {Measure-E2EPairs -Results @($native,$v4) -Treatment v4} 'MismatchedV4PairSettingsRejectedEvenWhenBlocked'
 $native.provenance=Clone $comparison;$v4.provenance.budget='invalid'
 Throws {Measure-E2EPairs -Results @($native,$v4) -Treatment v4} 'MalformedOneSidedBudgetRejected'
 $v4.provenance=Clone $comparison;$v4.provenance.budget.tokens=0
 Throws {Measure-E2EPairs -Results @($native,$v4) -Treatment v4} 'ZeroBudgetCannotBecomeMissingEvidence'
 $v4.provenance=Clone $comparison;$native.provenance.settings=@('a','b');$v4.provenance.settings="a`nb"
 Throws {Measure-E2EPairs -Results @($native,$v4) -Treatment v4} 'ScalarSettingsCannotEqualArrayByJoining'
 Write-Output "e2e-v4-adapter: $script:Count assertions passed"
} finally {
 $env:CONTROLFLOW_STATE_ROOT=$oldStateRoot
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($full).StartsWith('cf-v4-adapter-')){throw 'Unsafe test cleanup'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
$global:LASTEXITCODE=0
