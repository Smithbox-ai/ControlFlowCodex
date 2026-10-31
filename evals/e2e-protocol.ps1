# Evaluation receipts establish integrity, never native authority or verified usage.
function Get-E2EProtocolReadiness([hashtable]$Config) {
    if($Config.Variant -isnot [string]){throw 'Unknown E2E treatment'}
    $variant=$Config.Variant.ToLowerInvariant()
    if($variant -cnotin @('native','v4')){throw 'Unknown or retired E2E treatment'}
    $collector=if(-not $Config.ContainsKey('Collector')){'stdout-jsonl'}elseif($Config.Collector -is [string]){$Config.Collector.ToLowerInvariant()}else{throw 'Unknown E2E collector'}
    if($collector -cne 'stdout-jsonl'){throw 'Only stdout-jsonl collection is supported; session collectors are retired'}
    # No implemented native verifier supplies these facts. Requested settings,
    # model output and locally authored verified=true fields cannot replace one.
    return @{collector=$collector;protocol_version='exec-jsonl-root-v1';status='UNSUPPORTED';may_launch=$false;missing=@('actual-native-context-and-selected-entry','resolved-native-policies','complete-child-tree-and-usage','ambient-plugin-isolation','enforceable-in-flight-token-budget');assurance='root stdout observations only'}
}
function Get-E2ECollectedUsage {
    param([ValidateSet('stdout-jsonl')][string]$Collector='stdout-jsonl',[hashtable]$Capture)
    return Read-E2EStdoutUsage -Capture $Capture
}
function Read-E2EStdoutUsage([hashtable]$Capture) {
    $failures=[Collections.Generic.List[string]]::new();$thread=$null;$turnStarted=$false;$terminal=$false;$usage=$null;$tools=0
    $items=@{};$rootUsage=$null
    if($Capture.exit_code -ne 0 -or $Capture.timed_out -or $Capture.budget_reason -or $Capture.streams_complete -isnot [bool] -or -not $Capture.streams_complete -or $Capture.cleanup_verified -isnot [bool] -or -not $Capture.cleanup_verified){$failures.Add('incomplete-process')}
    try{$events=@(Read-E2EEvents $Capture.stdout)}catch{$events=@();$failures.Add('malformed-jsonl')}
    foreach($e in $events){
        if($e -isnot [hashtable] -or $e.type -isnot [string]){$failures.Add('invalid-event-envelope');continue}
        if($terminal){$failures.Add('event-after-terminal');continue}
        switch -CaseSensitive ($e.type){
            'thread.started' {
                $parsed=[guid]::Empty
                if($thread -or $turnStarted -or -not [guid]::TryParse([string]$e.thread_id,[ref]$parsed) -or $parsed -eq [guid]::Empty){$failures.Add('invalid-or-duplicate-thread')}else{$thread=[string]$e.thread_id}
            }
            'turn.started' {if(-not $thread -or $turnStarted){$failures.Add('invalid-or-duplicate-turn')}else{$turnStarted=$true}}
            {$_ -cin @('item.started','item.updated','item.completed')} {
                $item=$e.item
                if(-not $turnStarted -or $item -isnot [hashtable] -or $item.id -isnot [string] -or [string]::IsNullOrWhiteSpace($item.id)){$failures.Add('invalid-item');continue}
                $known=@('agent_message','reasoning','todo_list','command_execution','mcp_tool_call','web_search','file_change')
                if($item.type -cnotin $known){$failures.Add('unknown-item-scope');continue}
                if($items.ContainsKey($item.id)){
                    if($items[$item.id].completed -or $items[$item.id].type -cne $item.type -or $e.type -ceq 'item.started'){$failures.Add('invalid-item-sequence');continue}
                }else{
                    if($e.type -ceq 'item.updated'){$failures.Add('update-without-item');continue}
                    $items[$item.id]=@{type=$item.type;completed=$false}
                    if($item.type -cin @('command_execution','mcp_tool_call','web_search','file_change')){$tools++}
                }
                if($e.type -ceq 'item.completed'){$items[$item.id].completed=$true}
            }
            'turn.completed' {
                if(-not $turnStarted){$failures.Add('completion-without-turn')}
                $terminal=$true;$usage=$e.usage;$valid=$usage -is [hashtable]
                if($valid){foreach($key in @('input_tokens','cached_input_tokens','output_tokens')){if(($usage[$key] -isnot [long] -and $usage[$key] -isnot [int]) -or $usage[$key] -lt 0){$valid=$false}}}
                if($valid -and ($usage.cached_input_tokens -gt $usage.input_tokens -or $usage.input_tokens -gt ([long]::MaxValue-$usage.output_tokens))){$valid=$false}
                if($valid){$rootUsage=@{input_tokens=$usage.input_tokens;cached_input_tokens=$usage.cached_input_tokens;output_tokens=$usage.output_tokens;total_tokens=([long]$usage.input_tokens+[long]$usage.output_tokens);tool_calls=$tools}}else{$failures.Add('invalid-usage')}
            }
            default {$failures.Add('unsupported-or-failed-event')}
        }
    }
    if(-not $thread -or -not $turnStarted -or -not $terminal -or $null -eq $rootUsage){$failures.Add('missing-terminal-accounting')}
    if(@($items.Values|Where-Object {-not $_.completed}).Count){$failures.Add('unfinished-items')}
    return @{collector='stdout-jsonl';protocol_version='exec-jsonl-root-v1';complete=$false;root_complete=$failures.Count -eq 0;reason='Root stdout cannot prove child accounting, actual context, resolved policies or isolation';failures=@($failures);session_id=$thread;observed_root_usage=$rootUsage;input_tokens=$null;output_tokens=$null;cached_input_tokens=$null;total_tokens=$null;tool_calls=$null;actual_context=@{verified=$false;source=$null};child_usage_complete=$false;isolation_verified=$false}
}
function Assert-E2EAdapterNoLinks([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){$item=[IO.FileInfo]::new($cursor);if($item.LinkTarget -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (Test-Path -LiteralPath $cursor))){throw 'E2E_LINK_FORBIDDEN'};$next=[IO.Path]::GetDirectoryName($cursor);if($next -eq $cursor){break};$cursor=$next}
}
function Get-E2EV4CandidateInventory([string]$PluginRoot) {
    Assert-E2EAdapterNoLinks $PluginRoot
    $files=@(foreach($rel in @('plugin.json','.codex-plugin','skills','schemas','scripts','hooks','assets','plans/templates','docs')){
        $path=Join-Path $PluginRoot $rel
        if(Test-Path -LiteralPath $path -PathType Leaf){Get-Item -LiteralPath $path -Force}
        elseif(Test-Path -LiteralPath $path -PathType Container){
            # Reject links before recursion; never follow a linked subtree.
            $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($path)
            while($queue.Count){$dir=$queue.Dequeue();Assert-E2EAdapterNoLinks $dir;foreach($child in Get-ChildItem -LiteralPath $dir -Force){Assert-E2EAdapterNoLinks $child.FullName;if($child.PSIsContainer){$queue.Enqueue($child.FullName)}else{$child}}}
        }
    })
    return @(foreach($file in $files|Sort-Object FullName){Assert-E2EAdapterNoLinks $file.FullName;@{path=[IO.Path]::GetRelativePath($PluginRoot,$file.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()}})
}
function New-E2EV4Treatment {
    param([hashtable]$Case,[string]$FixtureRoot,[string]$TrialDirectory,[string]$PluginRoot)
    foreach($p in @($FixtureRoot,$TrialDirectory,$PluginRoot)){if(-not [IO.Path]::IsPathFullyQualified($p)){throw 'E2E_ABSOLUTE_PATH_REQUIRED'};Assert-E2EAdapterNoLinks $p}
    if(Test-Path -LiteralPath $TrialDirectory){throw 'E2E_TREATMENT_DIRECTORY_MUST_BE_NEW'}
    if($Case.id -isnot [string] -or [string]::IsNullOrWhiteSpace($Case.id)){throw 'E2E_CASE_ID_REQUIRED'}
    $relative=[IO.Path]::GetRelativePath($FixtureRoot,$TrialDirectory)
    if($relative -eq '.' -or (-not [IO.Path]::IsPathRooted($relative) -and $relative -ne '..' -and -not $relative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar))){throw 'E2E_TREATMENT_MUST_BE_EXTERNAL'}
    $inventory=@(Get-E2EV4CandidateInventory $PluginRoot);$digest=Get-E2EPluginDigest $inventory
    $manifest=Get-Content -LiteralPath (Join-Path $PluginRoot 'plugin.json') -Raw|ConvertFrom-Json -AsHashtable
    if($manifest.version -cnotmatch '^4\.0\.0(?:-[A-Za-z0-9.-]+)?$'){throw 'E2E_V4_CANDIDATE_REQUIRED'}
    $module=Import-Module (Join-Path $PluginRoot 'scripts/ControlFlow.Core.psm1') -Force -PassThru -DisableNameChecking
    $baseline=(& (@(Get-Command git -CommandType Application -ErrorAction Stop)[0]).Source -c core.excludesFile= -C $FixtureRoot rev-parse HEAD) -join "`n"
    if($LASTEXITCODE -ne 0){throw 'E2E_FIXTURE_BASELINE_UNAVAILABLE'}
    $source=& $module {param($r,$b) Get-ControlFlowSourceDigest -RepoRoot $r -Baseline $b} $FixtureRoot $baseline
    [IO.Directory]::CreateDirectory($TrialDirectory)|Out-Null
    $stateRoot=Join-Path $TrialDirectory 'state';[IO.Directory]::CreateDirectory($stateRoot)|Out-Null
    $binding=@{schema_version='1.0.0';treatment='v4';contract_version='4.0.0';treatment_id=[guid]::NewGuid().ToString('N');case_id=$Case.id;task_id=('eval-'+(Get-E2EHash $Case.id).Substring(0,20));fixture_root=[IO.Path]::GetFullPath($FixtureRoot);state_root=$stateRoot;plugin_root=[IO.Path]::GetFullPath($PluginRoot);plugin_sha256=$digest;package_version=$manifest.version;baseline_commit=$baseline;initial_source_digest=$source.digest}
    $request=Join-Path $TrialDirectory 'treatment.json';Write-E2EText $request ($binding|ConvertTo-Json -Depth 10)
    $prompt=(Get-E2ETrialPrompt -Case $Case -Variant v4)+"`nUse task_id $($binding.task_id) in this trial's external CONTROLFLOW_STATE_ROOT. Bind the run to the actual native thread ID. Do not use manual fallback. Preserve manual decision assurance; wait for a real human when required. Never fabricate approvals or verified-human evidence."
    return @{binding=$binding;request_path=$request;request_sha256=(Get-FileHash -LiteralPath $request).Hash.ToLowerInvariant();prompt=$prompt;environment=@{CONTROLFLOW_STATE_ROOT=$stateRoot};assurance='local-runtime-integrity; native context remains unverified'}
}
function Read-E2EV4RuntimeReceipt {
    param([hashtable]$Treatment,[string]$ThreadId,[string]$ExpectedRunId='')
    $answer=@{integrity_verified=$false;workflow_complete=$false;verified_human=$false;source_current=$false;assurance='local-runtime-integrity';reason='runtime receipt unavailable';lawful_stop=$false}
    $prior=[Environment]::GetEnvironmentVariable('CONTROLFLOW_STATE_ROOT')
    try{
        $b=$Treatment.binding;$parsed=[guid]::Empty
        if(-not [guid]::TryParse($ThreadId,[ref]$parsed) -or $parsed -eq [guid]::Empty){throw 'E2E_NATIVE_THREAD_REQUIRED'}
        Assert-E2EAdapterNoLinks $Treatment.request_path
        if((Get-FileHash -LiteralPath $Treatment.request_path).Hash.ToLowerInvariant() -cne $Treatment.request_sha256){throw 'E2E_TREATMENT_TAMPERED'}
        $saved=Get-Content -LiteralPath $Treatment.request_path -Raw|ConvertFrom-Json -AsHashtable
        foreach($key in $saved.Keys){if($b[$key] -cne $saved[$key]){throw 'E2E_TREATMENT_BINDING_MISMATCH'}}
        if($b.contract_version -cne '4.0.0' -or $b.treatment -cne 'v4'){throw 'E2E_V4_REQUIRED'}
        Assert-E2EAdapterNoLinks $b.state_root
        if((Get-E2EPluginDigest @(Get-E2EV4CandidateInventory $b.plugin_root)) -cne $b.plugin_sha256){throw 'E2E_CANDIDATE_CHANGED'}
        $env:CONTROLFLOW_STATE_ROOT=$b.state_root
        $module=Import-Module (Join-Path $b.plugin_root 'scripts/ControlFlow.Core.psm1') -Force -PassThru -DisableNameChecking
        $read=& $module {param($r,$s) Get-ControlFlowActiveRun $r $s} $b.fixture_root $ThreadId
        if($null -eq $read){throw 'E2E_ACTIVE_RUN_MISSING'}
        $s=$read.state
        if($s.schema_version -cne '4.0.0' -or $s.task_id -cne $b.task_id -or $s.binding.session_id -cne $ThreadId -or $s.manual_fallback -or ($ExpectedRunId -and $s.run_id -cne $ExpectedRunId) -or $s.baseline_commit -cne $b.baseline_commit -or $read.initial_snapshot.source.digest -cne $b.initial_source_digest){throw 'E2E_RUNTIME_BINDING_MISMATCH'}
        $statePath=Join-Path $read.run_path 'state.json';Assert-E2EAdapterNoLinks $statePath
        $stateHash=(Get-FileHash -LiteralPath $statePath).Hash.ToLowerInvariant()
        $diskState=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
        if($diskState.revision -ne $s.revision -or $diskState.evidence_ref.sha256 -cne $s.evidence_ref.sha256){throw 'E2E_RUNTIME_CHANGED_DURING_COLLECTION'}
        $contract=& $module {param($p) Read-ControlFlowContract $p} $s.contract_path
        if($contract.contract.task_id -cne $b.task_id -or $contract.contract.baseline.commit -cne $s.baseline_commit){throw 'E2E_CONTRACT_BINDING_MISMATCH'}
        $context=& $module {param($r,$p) Get-ControlFlowPlanningContext $r $p} $b.fixture_root $read.run_path
        $gate=& $module {param($r,$p) Test-ControlFlowGate $r $p Completion} $b.fixture_root $read.run_path
        $contractAfter=& $module {param($p) Read-ControlFlowContract $p} $s.contract_path
        $sourceAfter=& $module {param($r,$base,$run,$thread) Get-ControlFlowSourceDigest $r $base $run $thread} $b.fixture_root $s.baseline_commit $read.run_path $ThreadId
        if((Get-FileHash -LiteralPath $statePath).Hash.ToLowerInvariant() -cne $stateHash -or $contractAfter.digest -cne $contract.digest -or $context.contract_digest -cne $contract.digest -or $context.source_digest -cne $sourceAfter.digest -or $gate.run_id -cne $s.run_id -or $gate.source_digest -cne $context.source_digest -or $gate.contract_hash -cne $contract.digest){throw 'E2E_RUNTIME_CHANGED_DURING_COLLECTION'}
        $answer.integrity_verified=$true;$answer.reason='Local runtime bindings and immutable references validated; native provenance not established'
        $answer.task_id=$s.task_id;$answer.run_id=$s.run_id;$answer.thread_id=$ThreadId;$answer.revision=$s.revision;$answer.planning_epoch_id=$s.planning_epoch_id
        $answer.contract_status=$contract.contract.contract_status;$answer.contract_digest=$context.contract_digest;$answer.intent_digest=$context.intent_digest;$answer.policy_digest=$context.policy_digest
        $answer.source_digest=$context.source_digest;$answer.source_current=$context.source_digest -ceq $s.last_observed_source_digest
        $answer.status=$s.status;$answer.lawful_stop=$s.status -cin @('HUMAN_WAIT','BLOCKED','CLARIFICATION','PERMISSION_DENIED','CANCELLED','PLAN_MODE','INTERRUPTED')
        $answer.workflow_complete=$gate.status -ceq 'PASS' -and $answer.source_current -and -not $answer.lawful_stop
        $answer.gate=$gate;$answer.artifacts=$context.artifacts;$answer.pending_human_targets=@($s.human_wait_targets)
        $answer.decisions=@($read.evidence.events|Where-Object {$_.type -ceq 'phase_review' -and $_.judge -ceq 'human'}|ForEach-Object {@{target_id=$_.target_id;verdict=$_.verdict;assurance=$_.assurance;artifact_ref=$_.artifact_ref}})
        $answer.plugin_sha256=$b.plugin_sha256;$answer.state_sha256=$stateHash;$answer.evidence_ref=$s.evidence_ref
    }catch{$answer.integrity_verified=$false;$answer.workflow_complete=$false;$answer.reason=$_.Exception.Message}
    finally{[Environment]::SetEnvironmentVariable('CONTROLFLOW_STATE_ROOT',$prior)}
    return $answer
}
function New-E2EProtocolBlockedResult {
    param([hashtable]$Case,[hashtable]$Config,[string]$TrialDirectory)
    $ready=Get-E2EProtocolReadiness $Config
    if($ready.may_launch){throw 'Protocol block requested for an enabled collector'}
    Assert-E2EAdapterNoLinks $TrialDirectory
    if(Test-Path -LiteralPath $TrialDirectory){throw 'E2E_TRIAL_DIRECTORY_MUST_BE_NEW'}
    $result=@{schema_version='2.0.0';case_id=$Case.id;tier=$Case.tier;variant=$Config.Variant.ToLowerInvariant();collector=$ready.collector;status='incomplete';reason=('BLOCKED: '+($ready.missing -join ','));protocol=$ready;protocol_blocked_before_generation=$true;generation_started=$false;spend_status='not-generated-protocol-block';usage=$null;outcome=$null;false_completion=$false;resumes=0;wall_ms=0;provenance=@{collector=$ready.collector;protocol_version=$ready.protocol_version}}
    Write-E2EText (Join-Path $TrialDirectory 'result.json') ($result|ConvertTo-Json -Depth 15)
    return $result
}
function Measure-E2EV4Pairs([object[]]$Results) {
    $groups=@{};$pairs=[Collections.Generic.List[object]]::new();$unpaired=0
    foreach($r in $Results){
        if($r.variant -cnotin @('native','v4') -or $r.schema_version -cne '2.0.0' -or $r.case_id -isnot [string] -or [string]::IsNullOrWhiteSpace($r.case_id) -or ($r.trial -isnot [int] -and $r.trial -isnot [long]) -or $r.trial -lt 1){throw 'Invalid V4 paired identity/version'}
        $key=$r.case_id+'|'+$r.trial;if(-not $groups.ContainsKey($key)){$groups[$key]=@{}}
        if($groups[$key].ContainsKey($r.variant)){throw 'Duplicate V4 paired identity'};$groups[$key][$r.variant]=$r
    }
    foreach($key in $groups.Keys|Sort-Object){
        $g=$groups[$key];if(-not $g.ContainsKey('native') -or -not $g.ContainsKey('v4')){$unpaired++;continue}
        $n=$g.native;$v=$g.v4
        if($n.tier -cne $v.tier){throw 'V4 pair tier mismatch'}
        foreach($field in @('model','effort','host','fixture_hash','project_trust','sandbox','windows_sandbox','approval_policy','approvals_reviewer','cli_version','collector','protocol_version','plugin_sha256')){
            if($n.provenance[$field] -cne $v.provenance[$field]){throw "V4 pair mismatched $field provenance"}
        }
        $ns=$n.provenance.settings;$vs=$v.provenance.settings
        if($null -ne $ns -or $null -ne $vs){
            if($ns -isnot [Collections.IList] -or $vs -isnot [Collections.IList] -or @(@($ns)+@($vs)|Where-Object {$_ -isnot [string]}).Count){throw 'Invalid V4 pair settings shape'}
            if((ConvertTo-Json -InputObject @($ns) -Compress) -cne (ConvertTo-Json -InputObject @($vs) -Compress)){throw 'V4 pair mismatched settings'}
        }
        $nb=$n.provenance.budget;$vb=$v.provenance.budget
        if($null -ne $nb -or $null -ne $vb){
            if($nb -isnot [Collections.IDictionary] -or $vb -isnot [Collections.IDictionary]){throw 'Invalid V4 pair budget shape'}
            foreach($field in @('tokens','tools','wall_seconds')){
                foreach($budget in @($nb,$vb)){$value=$budget[$field];if(($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) -or $value -le 0 -or -not [double]::IsFinite([double]$value) -or [Math]::Floor([double]$value) -ne $value){throw 'Invalid V4 pair budget value'}}
                if($nb[$field] -ne $vb[$field]){throw "V4 pair mismatched $field budget"}
            }
        }
        # No native stdout verifier exists for the required context/child/isolation
        # evidence. Even a caller-supplied complete=true must remain incomplete.
        $pairs.Add(@{case_id=$n.case_id;trial=$n.trial;tier=$n.tier;native=$n;v4=$v;metrics_complete=$false;success_delta=$null;reason='native provenance capability unsupported'})
    }
    return @{schema_version='2.0.0';treatment='v4';collector='stdout-jsonl';paired_trials=$pairs.Count;unpaired_records=$unpaired;pairs=$pairs.ToArray();incomplete_metrics_pairs=$pairs.Count;success_delta=$null;release_sample_complete=$false;production_ready=$false;status='BLOCKED';reason='Actual context, native policies, complete child usage and isolation are not verified'}
}
