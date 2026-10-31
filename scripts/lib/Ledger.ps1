function Assert-CFNoLinks([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){$item=[IO.FileInfo]::new($cursor);if($null -ne $item.LinkTarget -or (([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)) -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))){throw 'ARTIFACT_LINK_FORBIDDEN'};$next=[IO.Path]::GetDirectoryName($cursor);if($next -eq $cursor){break};$cursor=$next}
}
function Write-CFFlushed([string]$Path,[byte[]]$Bytes) {
    Assert-CFNoLinks $Path
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Write-CFImmutable([string]$RunPath,[string]$Folder,[byte[]]$Bytes,[string]$Extension='json') {
    $relative="$Folder/$([guid]::NewGuid().ToString('N')).$Extension";$path=[IO.Path]::Combine($RunPath,$relative)
    Assert-CFNoLinks $path;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))|Out-Null
    Write-CFFlushed $path $Bytes
    return @{path=$relative;sha256=(Get-CFHash $Bytes)}
}
function Read-CFReference([string]$RunPath,$Reference,[switch]$Binary) {
    if($Reference.path -cnotmatch '^(initial|evidence|output|artifacts)/[a-f0-9]{32}\.(json|stdout\.bin|stderr\.bin)$' -or $Reference.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'INVALID_LEDGER_REFERENCE'}
    $path=[IO.Path]::Combine($RunPath,$Reference.path);Assert-CFNoLinks $path
    $bytes=[IO.File]::ReadAllBytes($path)
    if((Get-CFHash $bytes) -cne $Reference.sha256){throw 'CORRUPT_LEDGER_REFERENCE'}
    if($Binary){return ,$bytes}
    return ConvertFrom-Json -InputObject $script:Utf8.GetString($bytes) -AsHashtable -Depth 80
}
function Publish-CFState([string]$RunPath,$State,$Evidence) {
    $State.evidence_ref=Write-CFImmutable $RunPath 'evidence' $script:Utf8.GetBytes(($Evidence|ConvertTo-Json -Depth 80 -Compress))
    $tmp=[IO.Path]::Combine($RunPath,([guid]::NewGuid().ToString('N')+'.tmp'))
    Write-CFFlushed $tmp $script:Utf8.GetBytes(($State|ConvertTo-Json -Depth 80 -Compress))
    $target=[IO.Path]::Combine($RunPath,'state.json');Assert-CFNoLinks $target
    if([IO.File]::Exists($target)){[IO.File]::Move($tmp,$target,$true)}else{[IO.File]::Move($tmp,$target)}
}
function Get-CFActivePath([string]$RepoRoot,[string]$SessionId) { (Get-CFStorageContext $RepoRoot $SessionId).active_path }
function Start-ControlFlowRun {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$ContractPath,[string]$SessionId,[switch]$ManualFallback)
    if(-not $SessionId -and -not $ManualFallback){throw 'TRUSTED_SESSION_REQUIRED'}
    $identity=Get-CFIdentity $RepoRoot;$RepoRoot=$identity.worktree_realpath
    $read=Read-ControlFlowContract $ContractPath;$contract=$read.contract
    if($contract.schema_version -cne '4.0.0'){throw 'NEW_RUN_REQUIRES_V4: migrate the legacy contract to a fresh V4 draft; existing runs are unchanged'}
    $paths=Get-ControlFlowStoragePaths $RepoRoot $contract.task_id $SessionId
    $canonical=$paths.contract_path
    if([IO.Path]::GetFullPath($ContractPath) -cne [IO.Path]::GetFullPath($canonical)){throw 'CONTRACT_PATH_BINDING_MISMATCH'}
    Assert-CFNoLinks $canonical
    Assert-CFBaseline $RepoRoot $contract.baseline.commit|Out-Null
    $id=[guid]::NewGuid().ToString('N');$runPath=[IO.Path]::Combine($paths.task_path,'runs',$id)
    $initial=Get-ControlFlowGitSnapshot $RepoRoot
    $source=Get-ControlFlowSourceDigest $RepoRoot $contract.baseline.commit $runPath $SessionId
    $initial.source=$source
    Assert-CFNoLinks $runPath;[IO.Directory]::CreateDirectory($runPath)|Out-Null
    $identity.session_id=$SessionId
    $state=@{schema_version=$contract.schema_version;task_id=$contract.task_id;run_id=$id;binding=$identity;revision=0;status='ACTIVE';contract_path=$canonical;initial_contract_digest=$read.digest;baseline_commit=$contract.baseline.commit;manual_fallback=[bool]$ManualFallback;continuations=@{total=0;signature='';repeated=0};structured_reason=$null;acknowledged_interrupt_id=$null;initial_ref=(Write-CFImmutable $runPath 'initial' $script:Utf8.GetBytes(($initial|ConvertTo-Json -Depth 80 -Compress)));evidence_ref=$null}
    if($contract.schema_version -ceq '4.0.0'){$state.planning_epoch_id=0;$state.planning_source_digest=$source.digest;$state.preflight_digest=$null;$state.last_observed_source_digest=$source.digest;$state.stop_source_digest=$null;$state.human_wait_targets=@()}
    Publish-CFState $runPath $state @{events=@();checks=@();candidate=$null}
    if($SessionId){
        $active=Get-CFActivePath $RepoRoot $SessionId;Assert-CFNoLinks $active;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($active))|Out-Null
        Assert-CFNoLinks ($active+'.lock')
        $activeLock=[IO.File]::Open($active+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            if([IO.File]::Exists($active)) { $prior=Get-ControlFlowActiveRun $RepoRoot $SessionId;if($prior.state.status -notin @('COMPLETED','CANCELLED')){throw 'SESSION_ALREADY_ACTIVE'} }
            $pointer=@{schema_version=$contract.schema_version;run_path=$runPath;run_id=$id;task_id=$contract.task_id;binding=$identity}
            $tmp=$active+'.'+[guid]::NewGuid().ToString('N')+'.tmp';Write-CFFlushed $tmp $script:Utf8.GetBytes(($pointer|ConvertTo-Json -Depth 20 -Compress))
            if([IO.File]::Exists($active)){[IO.File]::Move($tmp,$active,$true)}else{[IO.File]::Move($tmp,$active)}
        }finally{$activeLock.Dispose()}
    }
    return @{run_path=$runPath;run_id=$id;state=$state}
}
function Read-ControlFlowRun {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[string]$SessionId)
    $header=Read-CFRunHeader $RepoRoot $RunPath $SessionId
    $state=$header.state;$RunPath=$header.run_path
    $contractVersion=(Read-ControlFlowContract $state.contract_path).contract.schema_version
    if($contractVersion -cne $state.schema_version){throw 'RUNTIME_VERSION_MISMATCH'}
    $initial=Read-CFReference $RunPath $state.initial_ref;$evidence=Read-CFReference $RunPath $state.evidence_ref
    foreach($check in $evidence.checks){Read-CFReference $RunPath $check.stdout_ref -Binary|Out-Null;Read-CFReference $RunPath $check.stderr_ref -Binary|Out-Null;if($check.ContainsKey('quality') -and $check.quality.ContainsKey('raw_report_ref')){Read-CFReference $RunPath $check.quality.raw_report_ref -Binary|Out-Null}}
    if($state.schema_version -ceq '4.0.0'){foreach($event in $evidence.events){if($event.type -ceq 'artifact'){Read-CFReference $RunPath $event.artifact_ref|Out-Null}}}
    $pending=Read-CFPendingInterrupt $RunPath $state
    $ack=if($state.ContainsKey('acknowledged_interrupt_id')){$state.acknowledged_interrupt_id}else{$null}
    if($null -ne $pending -and $pending.interrupt_id -cne $ack){
        if($state.schema_version -ceq '4.0.0' -and -not $state.stop_source_digest){$state.stop_source_digest=$pending.observed_source_digest}
        $state.status='INTERRUPTED'
        $state.structured_reason=@{reason='INTERRUPT';evidence='NATIVE_PENDING_INTERRUPT';interrupt_id=$pending.interrupt_id;native_evidence=$pending.native_evidence}
    }
    return @{state=$state;evidence=$evidence;initial_snapshot=$initial;run_path=$RunPath;pending_interrupt=$pending;legacy_semantics=($state.schema_version -ceq '3.0.0')}
}
function Get-ControlFlowActiveRun {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$SessionId)
    $header=Resolve-CFActiveHeader $RepoRoot $SessionId
    if($null -eq $header){return $null}
    return Read-ControlFlowRun $header.state.binding.worktree_realpath $header.run_path $SessionId
}
function Get-CFRunSource([string]$RepoRoot,[string]$RunPath,$State) { Get-ControlFlowSourceDigest $RepoRoot $State.baseline_commit $RunPath $State.binding.session_id }
function Get-CFQABindings($Contract,$Artifact) {
    $criterionIds=@($Artifact.payload.scenarios|ForEach-Object {$_.criterion_refs}|Sort-Object -Unique)
    $checkIds=@($Artifact.payload.scenarios|ForEach-Object {$_.check_refs}|Sort-Object -Unique)
    $criteria=@(foreach($id in $criterionIds){$defs=@($Contract.criteria|Where-Object {$_.id -ceq $id});if($defs.Count -ne 1){throw 'INVALID_QA_CRITERION'};[ordered]@{id=$id;sha256=(Get-CFJsonHash $defs[0])}})
    $checks=@(foreach($id in $checkIds){$defs=@($Contract.checks|Where-Object {$_.id -ceq $id});if($defs.Count -ne 1){throw 'INVALID_QA_CHECK'};[ordered]@{id=$id;sha256=(Get-CFJsonHash $defs[0])}})
    return [ordered]@{criteria=$criteria;checks=$checks}
}
function Get-CFV4Artifacts($Read,$Contract) {
    $currentContractDigest=(Read-ControlFlowContract $Read.state.contract_path).digest
    $latest=Get-CFMap
    foreach($event in $Read.evidence.events){
        if($event.type -cne 'artifact' -or $event.planning_epoch_id -ne $Read.state.planning_epoch_id){continue}
        $a=Read-CFReference $Read.run_path $event.artifact_ref
        if($a.task_id -cne $Read.state.task_id -or $a.run_id -cne $Read.state.run_id -or $a.planning_epoch_id -ne $Read.state.planning_epoch_id){throw 'ARTIFACT_IDENTITY_MISMATCH'}
        $latest[$a.kind]=@{artifact=$a;ref=$event.artifact_ref;contract_digest=$event.contract_digest}
    }
    $valid=Get-CFMap
    foreach($kind in @('context','design','qa-plan','implementation-plan','qa-recheck','review-packet')){
        if(-not $latest.ContainsKey($kind)){continue};$entry=$latest[$kind];$a=$entry.artifact
        if($null -ne $entry.contract_digest -and $entry.contract_digest -cne $currentContractDigest){continue}
        $promotions=@($Read.evidence.events|Where-Object {$_.type -ceq 'preflight' -and $_.planning_epoch_id -eq $Read.state.planning_epoch_id -and @($_.promoted_artifacts|Where-Object {$_.path -ceq $entry.ref.path}).Count -gt 0})
        if($promotions.Count -gt 0 -and $promotions[0].contract_digest -cne $currentContractDigest){continue}
        if($a.intent_digest -cne (Get-CFIntentDigest $Contract) -or $a.policy_digest -cne (Get-CFPolicyDigest $Contract)){continue}
        if($kind -ceq 'qa-plan'){
            try{$bindings=Get-CFQABindings $Contract $a}catch{if($_.Exception.Message -in @('INVALID_QA_CHECK','INVALID_QA_CRITERION')){continue};throw}
            if(-not $a.ContainsKey('qa_bindings') -or (Get-CFJsonHash $a.qa_bindings) -cne (Get-CFJsonHash $bindings)){continue}
        }
        $ok=$true
        foreach($inputRef in $a.inputs){
            $input=Read-CFReference $Read.run_path $inputRef
            if(-not $valid.ContainsKey($input.kind) -or $valid[$input.kind].ref.sha256 -cne $inputRef.sha256 -or $valid[$input.kind].ref.path -cne $inputRef.path){$ok=$false}
        }
        if($ok){$valid[$kind]=$entry}
    }
    return ,$valid
}
function Get-ControlFlowPlanningContext {
    param([string]$RepoRoot,[string]$RunPath)
    $read=Read-ControlFlowRun $RepoRoot $RunPath;$c=Read-ControlFlowContract $read.state.contract_path
    if($read.state.schema_version -cne '4.0.0' -or $c.contract.schema_version -cne '4.0.0'){throw 'V4_REQUIRED'}
    $refs=Get-CFMap;$artifacts=Get-CFV4Artifacts $read $c.contract
    foreach($kind in $artifacts.Keys){$refs[$kind]=$artifacts[$kind].ref}
    return @{task_id=$read.state.task_id;run_id=$read.state.run_id;planning_epoch_id=$read.state.planning_epoch_id;source_digest=(Get-CFRunSource $RepoRoot $RunPath $read.state).digest;intent_digest=(Get-CFIntentDigest $c.contract);policy_digest=(Get-CFPolicyDigest $c.contract);contract_digest=$c.digest;artifacts=$refs}
}
function Test-CFV4Review($Read,$ContractRead,$Ref,[string]$Judge,[string]$Target) {
    $artifacts=Get-CFV4Artifacts $Read $ContractRead.contract;$artifact=Read-CFReference $Read.run_path $Ref
    if(-not $artifacts.ContainsKey($artifact.kind) -or $artifacts[$artifact.kind].ref.path -cne $Ref.path -or $artifacts[$artifact.kind].ref.sha256 -cne $Ref.sha256){return $false}
    if($artifact.kind -ceq 'review-packet' -and $artifact.source_digest -cne (Get-CFRunSource $Read.state.binding.worktree_realpath $Read.run_path $Read.state).digest){return $false}
    $events=@($Read.evidence.events|Where-Object {$_.type -ceq 'phase_review' -and $_.target_id -ceq $Target -and $_.judge -ceq $Judge -and $_.artifact_ref.path -ceq $Ref.path -and $_.artifact_ref.sha256 -ceq $Ref.sha256 -and $_.planning_epoch_id -eq $Read.state.planning_epoch_id})
    if($events.Count -eq 0){return $false};$review=$events[-1]
    if($review.verdict -cne 'APPROVED' -or $review.intent_digest -cne (Get-CFIntentDigest $ContractRead.contract) -or $review.policy_digest -cne (Get-CFPolicyDigest $ContractRead.contract)){return $false}
    if($ContractRead.contract.review_policy.assurance -ceq 'verified' -and $Judge -ceq 'human'){return $false}
    if($null -ne $review.contract_digest -and $review.contract_digest -cne $ContractRead.digest){return $false}
    return $true
}
function Assert-CFV4Execution($Read,$ContractRead) {
    if($ContractRead.contract.schema_version -cne $Read.state.schema_version){throw 'RUNTIME_VERSION_MISMATCH'}
    if($ContractRead.contract.contract_status -cne 'final'){throw 'DRAFT_CANNOT_AUTHORIZE_EXECUTION'}
    $pre=@($Read.evidence.events|Where-Object {$_.type -ceq 'preflight' -and $_.planning_epoch_id -eq $Read.state.planning_epoch_id})
    if($pre.Count -eq 0 -or $pre[-1].contract_digest -cne $ContractRead.digest){throw 'V4_PREFLIGHT_REQUIRED'}
}
function Test-CFV4Capture($Read,$ContractRead,$Source,[string]$CheckId,[switch]$RequireReport) {
    $defs=@($ContractRead.contract.checks|Where-Object {$_.id -ceq $CheckId});if($defs.Count -ne 1){return $false};$def=$defs[0]
    $captures=@($Read.evidence.checks|Where-Object {$_.check_id -ceq $CheckId});if($captures.Count -eq 0){return $false};$capture=$captures[-1]
    if($capture.status -cne 'PASS' -or $capture.exit_code -ne 0 -or $capture.timed_out -or $capture.process_incomplete -or $capture.contract_digest -cne $ContractRead.digest -or $capture.command_digest -cne (Get-CFJsonHash $def) -or $capture.source_before -cne $Source.digest -or $capture.source_after -cne $Source.digest){return $false}
    if($RequireReport -or $def.ContainsKey('report')){if(-not $capture.ContainsKey('quality') -or $capture.quality.status -cne 'PASS' -or -not $capture.quality.ContainsKey('raw_report_ref')){return $false}}
    if($def.ContainsKey('inputs')){if($capture.input_before -cne (Get-CFCheckInputDigest $Read.state.binding.worktree_realpath $def) -or $capture.input_after -cne $capture.input_before){return $false}}
    return $true
}
function Assert-CFForeignPreserved([string]$RepoRoot,[string]$RunPath,$Read) {
    $source=Get-CFRunSource $RepoRoot $RunPath $Read.state;$now=Get-ControlFlowGitSnapshot $RepoRoot $RunPath $Read.state.binding.session_id
    $oldEntries=Get-CFEntriesMap $Read.initial_snapshot.source.entries;$entries=Get-CFEntriesMap $source.entries
    $oldIndex=Get-CFEntriesMap $Read.initial_snapshot.index;$index=Get-CFEntriesMap $now.index
    foreach($path in $Read.initial_snapshot.dirty_paths){
        $a=if($oldEntries.ContainsKey($path)){$oldEntries[$path]}else{$null};$b=if($entries.ContainsKey($path)){$entries[$path]}else{$null}
        if((Get-CFEntryIdentity $a) -cne (Get-CFEntryIdentity $b)){throw 'FOREIGN_WORKTREE_CHANGED'}
        $a=if($oldIndex.ContainsKey($path)){$oldIndex[$path]}else{$null};$b=if($index.ContainsKey($path)){$index[$path]}else{$null}
        if((Get-CFIndexIdentity $a) -cne (Get-CFIndexIdentity $b)){throw 'FOREIGN_INDEX_CHANGED'}
    }
}
function Update-CFV4Event([string]$RepoRoot,[string]$RunPath,$Read,$Event,$Copy) {
    $s=$Read.state;$c=Read-ControlFlowContract $s.contract_path;$contract=$c.contract
    if($contract.schema_version -cne $s.schema_version){throw 'RUNTIME_VERSION_MISMATCH'}
    $source=Get-CFRunSource $RepoRoot $RunPath $s
    $s.last_observed_source_digest=$source.digest
    $Copy.planning_epoch_id=$s.planning_epoch_id
    switch -CaseSensitive($Event.type){
        'artifact' {
            if($s.status -notin @('ACTIVE','HUMAN_WAIT')){throw 'RUN_NOT_ACTIVE'}
            $a=$Event.artifact;if($a.kind -in @('context','design','qa-plan','implementation-plan') -and $s.preflight_digest){throw 'PLANNING_EPOCH_REQUIRED'}
            if($a.kind -ceq 'review-packet'){
                $a.evidence_summary=@($contract.checks|ForEach-Object {
                    $id=$_.id;$caps=@($Read.evidence.checks|Where-Object {$_.check_id -ceq $id});$last=if($caps.Count -gt 0){$caps[-1]}else{$null}
                    [ordered]@{check_id=$id;status=$(if($null -eq $last){'NOT_RUN'}elseif(Test-CFV4Capture $Read $c $source $id){'PASS'}else{'FAIL'});capture=$last}
                })
                $a.profile_summary=@($contract.quality_profiles|ForEach-Object {
                    $profile=$_;$capability=Get-CFV4ProfileCapability $contract $profile;$status=if($capability -ceq 'unsupported'){'UNSUPPORTED'}elseif($capability -ceq 'not_applicable'){'NOT_APPLICABLE'}elseif($capability -ceq 'unknown' -or $profile.check_ids.Count -eq 0){'NOT_RUN'}elseif(@($profile.check_ids|Where-Object {-not (Test-CFV4Capture $Read $c $source $_)}).Count -gt 0){'NOT_RUN'}else{'PASS'}
                    [ordered]@{id=$profile.id;kind=$profile.kind;required=$profile.required;status=$status;capability=$profile.capability;check_ids=$profile.check_ids}
                })
            }
            $text=ConvertTo-Json -InputObject $a -Depth 80 -Compress
            if(-not (Test-Json -Json $text -SchemaFile (Join-Path $script:CoreModuleRoot '../schemas/phase-artifact-v1.schema.json') -ErrorAction Stop)){throw 'INVALID_ARTIFACT_SCHEMA'}
            foreach($key in @('task_id','run_id','planning_epoch_id')){if($a[$key] -cne $s[$key]){throw 'ARTIFACT_IDENTITY_MISMATCH'}}
            if($a.source_digest -cne $source.digest -or $a.intent_digest -cne (Get-CFIntentDigest $contract) -or $a.policy_digest -cne (Get-CFPolicyDigest $contract)){throw 'ARTIFACT_BINDING_MISMATCH'}
            if($a.kind -cnotin $contract.workflow.required_artifacts){throw 'ARTIFACT_NOT_IN_WORKFLOW'}
            foreach($id in $a.criterion_refs){if($id -cnotin @($contract.criteria|ForEach-Object {$_.id})){throw 'INVALID_CRITERION_REFERENCE'}}
            if($a.kind -ceq 'qa-plan'){
                $ids=Get-CFMap
                foreach($scenario in $a.payload.scenarios){
                    if($ids.ContainsKey($scenario.id)){throw 'DUPLICATE_SCENARIO'};$ids[$scenario.id]=$true
                    foreach($id in $scenario.criterion_refs){if($id -cnotin @($contract.criteria|ForEach-Object {$_.id})){throw 'INVALID_QA_CRITERION'}}
                    foreach($id in $scenario.check_refs){$defs=@($contract.checks|Where-Object {$_.id -ceq $id});if($defs.Count -ne 1){throw 'INVALID_QA_CHECK'};foreach($criterion in $scenario.criterion_refs){if($criterion -cnotin $defs[0].criteria){throw 'QA_CHECK_CRITERION_MISMATCH'}}}
                }
            }
            if($a.kind -ceq 'implementation-plan'){
                $ids=Get-CFMap
                foreach($part in $a.payload.parts){
                    if($ids.ContainsKey($part.id)){throw 'DUPLICATE_IMPLEMENTATION_PART'}
                    foreach($dependency in $part.depends_on){if(-not $ids.ContainsKey($dependency)){throw 'IMPLEMENTATION_DEPENDENCY_NOT_READY'}}
                    foreach($id in $part.criterion_refs){if($id -cnotin @($contract.criteria|ForEach-Object {$_.id})){throw 'INVALID_IMPLEMENTATION_CRITERION'}}
                    $ids[$part.id]=$true
                }
            }
            $artifacts=Get-CFV4Artifacts $Read $contract
            $allArtifacts=@($Read.evidence.events|Where-Object {$_.type -ceq 'artifact'})
            foreach($previous in $allArtifacts){$old=Read-CFReference $RunPath $previous.artifact_ref;if($old.artifact_id -ceq $a.artifact_id){throw 'ARTIFACT_ID_REUSED'};if($old.kind -ceq $a.kind -and $old.planning_epoch_id -eq $s.planning_epoch_id -and $old.revision -ge $a.revision){throw 'ARTIFACT_REVISION_NOT_INCREASING'}}
            $required=@(switch($a.kind){'context'{};'design'{'context'};'qa-plan'{'design'};'implementation-plan'{'qa-plan'};'qa-recheck'{'qa-plan';'implementation-plan'};'review-packet'{if($contract.workflow.profile -cne 'light'){'qa-recheck'}}})
            foreach($kind in $required){
                if(-not $artifacts.ContainsKey($kind)){throw ('PHASE_PREREQUISITE_MISSING:'+$kind)}
                if(@($a.inputs|Where-Object {$_.path -ceq $artifacts[$kind].ref.path -and $_.sha256 -ceq $artifacts[$kind].ref.sha256}).Count -ne 1){throw 'EXACT_INPUT_REQUIRED'}
            }
            foreach($ref in $a.inputs){$input=Read-CFReference $RunPath $ref;if(-not $artifacts.ContainsKey($input.kind) -or $artifacts[$input.kind].ref.path -cne $ref.path -or $artifacts[$input.kind].ref.sha256 -cne $ref.sha256){throw 'FOREIGN_OR_STALE_INPUT'}}
            if($a.kind -in @('qa-plan','implementation-plan') -and $contract.review_policy.human_design){if(-not $artifacts.ContainsKey('design') -or -not (Test-CFV4Review $Read $c $artifacts.design.ref human design)){throw 'HUMAN_DESIGN_DECISION_REQUIRED'}}
            if($a.kind -in @('qa-recheck','review-packet')){
                Assert-CFV4Execution $Read $c
                if($a.kind -ceq 'qa-recheck'){
                    $qa=$artifacts['qa-plan'];if($a.payload.baseline_ref.path -cne $qa.ref.path -or $a.payload.baseline_ref.sha256 -cne $qa.ref.sha256){throw 'EXACT_QA_BASELINE_REQUIRED'}
                    foreach($scenario in $qa.artifact.payload.scenarios){
                        $ds=@($a.payload.dispositions|Where-Object {$_.scenario_id -ceq $scenario.id})
                        if($ds.Count -ne 1 -or $ds[0].expected -cne $scenario.expected){throw 'QA_EXPECTATION_CHANGED'}
                        if($ds[0].status -cne 'PASS' -or $ds[0].drift -cne 'none'){throw 'QA_RECHECK_UNRESOLVED'}
                        foreach($id in $scenario.check_refs){if($id -cnotin $ds[0].evidence_refs -or -not (Test-CFV4Capture $Read $c $source $id -RequireReport)){throw 'QA_EVIDENCE_MISSING'}}
                        if($scenario.check_refs.Count -eq 0){foreach($id in $scenario.criterion_refs){if(Test-CFV4CodeCriterion $contract $id){throw 'CODE_SCENARIO_CHECK_REQUIRED'}}}
                    }
                    if($a.payload.dispositions.Count -ne $qa.artifact.payload.scenarios.Count){throw 'QA_DISPOSITION_SET_MISMATCH'}
                }
            }
            if($a.kind -ceq 'qa-plan'){$a.qa_bindings=Get-CFQABindings $contract $a}
            $text=ConvertTo-Json -InputObject $a -Depth 80 -Compress
            $Copy.Remove('artifact');$Copy.artifact_ref=Write-CFImmutable $RunPath artifacts $script:Utf8.GetBytes($text)
            $Copy.contract_digest=if($contract.contract_status -ceq 'final'){$c.digest}else{$null}
        }
        'phase_review' {
            if($s.status -notin @('ACTIVE','HUMAN_WAIT','BLOCKED') -or ($s.status -ceq 'BLOCKED' -and ($Event.judge -cne 'human' -or $Event.target_id -cnotin $s.human_wait_targets -or ($s.structured_reason.evidence -ceq 'CORRECTION_LIMIT')))){throw 'RUN_NOT_ACTIVE'}
            if($Event.judge -cnotin @('human','agent') -or $Event.verdict -cnotin @('APPROVED','REJECTED','UNKNOWN') -or $Event.assurance -cnotin @('manual','verified')){throw 'INVALID_PHASE_REVIEW'}
            if($Event.assurance -ceq 'verified'){throw 'TRUSTED_DECISION_SOURCE_UNAVAILABLE'}
            if($Event.judge -ceq 'human' -and [string]::IsNullOrWhiteSpace([string]$Event.user_decision_ref)){throw 'EXPLICIT_USER_DECISION_REQUIRED'}
            $artifacts=Get-CFV4Artifacts $Read $contract;$a=Read-CFReference $RunPath $Event.artifact_ref
            if(-not $artifacts.ContainsKey($a.kind) -or $artifacts[$a.kind].ref.path -cne $Event.artifact_ref.path -or $artifacts[$a.kind].ref.sha256 -cne $Event.artifact_ref.sha256){throw 'REVIEW_ARTIFACT_STALE'}
            if($Event.target_id -cnotin (@('design','final')+@($contract.criteria|ForEach-Object {$_.id})+@($(if($contract.ContainsKey('phases')){$contract.phases|ForEach-Object {$_.id}})))){throw 'INVALID_REVIEW_TARGET'}
            if($Event.target_id -ceq 'design' -and $a.kind -cne 'design'){throw 'DESIGN_REVIEW_BINDING_REQUIRED'}
            if($Event.target_id -cne 'design' -and ($a.kind -cne 'review-packet' -or $a.source_digest -cne $source.digest)){throw 'FINAL_REVIEW_BINDING_REQUIRED'}
            $Copy.receipt_id=[guid]::NewGuid().ToString('N');$Copy.intent_digest=Get-CFIntentDigest $contract;$Copy.policy_digest=Get-CFPolicyDigest $contract
            $Copy.contract_digest=if($contract.contract_status -ceq 'final'){$c.digest}else{$null}
            if($Event.verdict -cne 'APPROVED'){
                if(-not $s.ContainsKey('corrections')){$s.corrections=@{total=0;targets=@{}}}
                $key=$Event.target_id;if(-not $s.corrections.targets.ContainsKey($key)){$s.corrections.targets[$key]=0}
                $s.corrections.total++;$s.corrections.targets[$key]++
                if($Event.judge -ceq 'human'){
                    if(-not $s.stop_source_digest){$s.stop_source_digest=$source.digest}
                    $s.human_wait_targets=@(@($s.human_wait_targets)+@($Event.target_id)|Sort-Object -Unique)
                    $s.status='HUMAN_WAIT';$s.structured_reason=@{reason='HUMAN_WAIT';evidence=$Copy.receipt_id}
                }
                if($s.corrections.total -ge 6 -or $s.corrections.targets[$key] -ge 3){$s.status='BLOCKED';$s.structured_reason=@{reason='BLOCKED';evidence='CORRECTION_LIMIT'}}
            }
        }
        'preflight' {
            if($contract.contract_status -cne 'final'){throw 'FINAL_CONTRACT_REQUIRED'}
            foreach($profile in $contract.quality_profiles){if($profile.required -and (Get-CFV4ProfileCapability $contract $profile) -cne 'available'){throw ('REQUIRED_PROFILE_UNSUPPORTED:'+$profile.id)}}
            if($contract.review_policy.assurance -ceq 'verified' -and ($contract.review_policy.human_design -or $contract.review_policy.human_final -or @($contract.review_policy.requirements|Where-Object {'human' -cin $_.judges}).Count -gt 0)){throw 'TRUSTED_DECISION_SOURCE_UNAVAILABLE'}
            if($source.digest -cne $s.planning_source_digest){throw 'PRODUCTION_EDIT_BEFORE_PREFLIGHT'}
            Assert-CFForeignPreserved $RepoRoot $RunPath $Read
            $artifacts=Get-CFV4Artifacts $Read $contract
            foreach($kind in @('context','design','qa-plan','implementation-plan')){if($kind -cin $contract.workflow.required_artifacts -and -not $artifacts.ContainsKey($kind)){throw ('PHASE_PREREQUISITE_MISSING:'+$kind)}}
            if($artifacts.ContainsKey('qa-plan')){
                $covered=@($artifacts['qa-plan'].artifact.payload.scenarios|ForEach-Object {$_.criterion_refs})
                foreach($criterion in $contract.criteria){if($criterion.id -cnotin $covered){throw 'QA_CRITERION_SCENARIO_MISSING'}}
            }
            if($contract.review_policy.human_design -and (-not $artifacts.ContainsKey('design') -or -not (Test-CFV4Review $Read $c $artifacts.design.ref human design))){throw 'HUMAN_DESIGN_DECISION_REQUIRED'}
            $Copy.authorized_scope=@($contract.scope);$Copy.promoted_artifacts=@($artifacts.Values|ForEach-Object {$_.ref});$s.preflight_digest=$c.digest
        }
        'resume' {
            if($s.stop_source_digest -and $source.digest -cne $s.stop_source_digest){throw 'EDIT_DURING_LAWFUL_STOP'}
            if($Event.ContainsKey('mode') -and $Event.mode -ceq 'planning'){
                if([string]::IsNullOrWhiteSpace([string]$Event.user_decision_ref)){throw 'EXPLICIT_USER_DECISION_REQUIRED'}
                if(-not $s.preflight_digest){throw 'REPLAN_REQUIRES_AUTHORIZED_PREFLIGHT'}
                $previous=@($Read.evidence.events|Where-Object {$_.type -ceq 'preflight' -and $_.planning_epoch_id -eq $s.planning_epoch_id})[-1]
                $old=Get-CFEntriesMap $Read.initial_snapshot.source.entries;$now=Get-CFEntriesMap $source.entries;$paths=@($old.Keys)+@($now.Keys)|Sort-Object -Unique
                foreach($path in $paths){$a=if($old.ContainsKey($path)){$old[$path]}else{$null};$b=if($now.ContainsKey($path)){$now[$path]}else{$null};if((Get-CFEntryIdentity $a) -cne (Get-CFEntryIdentity $b) -and -not (Test-ControlFlowScope $path $previous.authorized_scope)){throw 'UNAUTHORIZED_CARRIED_WORK'}}
                Assert-CFForeignPreserved $RepoRoot $RunPath $Read
                # The original initial_ref is never replaced. Only previously authorized
                # work is carried; changes during this epoch are compared to this boundary.
                $Copy.previous_preflight_digest=$s.preflight_digest;$Copy.carried_source_digest=$source.digest
                $Copy.superseded_wait_targets=@($s.human_wait_targets);$s.human_wait_targets=@()
                if($s.ContainsKey('corrections')){$Copy.previous_corrections=$s.corrections;$s.corrections=@{total=0;targets=@{}}}
                $s.planning_epoch_id++;$s.planning_source_digest=$source.digest;$s.preflight_digest=$null
                $Copy.planning_epoch_id=$s.planning_epoch_id
            }elseif($s.status -ceq 'HUMAN_WAIT' -or $s.human_wait_targets.Count -gt 0){
                $receipts=@();if($Event.ContainsKey('decision_receipt_id')){$receipts+=@($Event.decision_receipt_id)};if($Event.ContainsKey('decision_receipt_ids')){$receipts+=@($Event.decision_receipt_ids)}
                if($receipts.Count -eq 0){throw 'EXACT_DECISION_RECEIPT_REQUIRED'}
                $targets=@($s.human_wait_targets);if($targets.Count -eq 0){$targets=@('final')}
                foreach($target in $targets){
                    $decisions=@($Read.evidence.events|Where-Object {$_.type -ceq 'phase_review' -and $_.judge -ceq 'human' -and $_.target_id -ceq $target})
                    if($decisions.Count -eq 0 -or $decisions[-1].receipt_id -cnotin $receipts -or $decisions[-1].verdict -cne 'APPROVED'){throw 'STALE_DECISION_CANNOT_RESUME'}
                    $d=$decisions[-1];if(-not (Test-CFV4Review $Read $c $d.artifact_ref human $d.target_id)){throw 'STALE_DECISION_CANNOT_RESUME'}
                }
                $s.human_wait_targets=@()
            }
            $s.stop_source_digest=$null
        }
        'stop' {
            if($Event.reason -ceq 'HUMAN_WAIT' -and $s.human_wait_targets.Count -eq 0){throw 'HUMAN_WAIT_REQUIRES_BOUND_DECISION'}
            if(-not $s.stop_source_digest){$s.stop_source_digest=$source.digest}
            if($Event.reason -ceq 'HUMAN_WAIT'){$s.status='HUMAN_WAIT';$s.structured_reason=$Copy}
        }
        'coverage' {Assert-CFV4Execution $Read $c}
        'review' {throw 'V4_REQUIRES_PHASE_REVIEW'}
    }
}
function Read-ControlFlowQualityReport {
    param([string]$Path,[string]$Format,[ValidateRange(1,2147483647)][int]$MinimumTests=1,[Nullable[double]]$MinimumScore)
    if($null -ne $MinimumScore -and ($MinimumScore -lt 0 -or $MinimumScore -gt 100 -or [double]::IsNaN($MinimumScore))){throw 'INVALID_MINIMUM_SCORE'}
    $q=@{status='ERROR';format=$Format;executed_tests=$null;assertion_count=$null;mutation_score=$null;counts=@{};limitations=@()}
    if($Format -cnotin @('junit','nunit3','stryker-json')){$q.status='UNSUPPORTED';return $q}
    try{
        Assert-CFNoLinks $Path
        $file=[IO.FileInfo]::new($Path);if(-not $file.Exists){$q.status='NOT_RUN';return $q};if($file.Length -gt 33554432){throw 'REPORT_TOO_LARGE'}
        if($Format -ceq 'stryker-json'){
            $report=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path,$script:Utf8)) -AsHashtable -Depth 80
            if(-not $report.ContainsKey('schemaVersion') -or -not $report.ContainsKey('files')){throw 'INVALID_MUTATION_REPORT'}
            $counts=@{};$count=0
            foreach($f in $report.files.Values){
                $seen=Get-CFMap
                foreach($m in $f.mutants){
                    if($seen.ContainsKey($m.id)){throw 'DUPLICATE_MUTANT'};$seen[$m.id]=$true
                    if($m.status -cnotin @('Killed','Timeout','Survived','NoCoverage','CompileError','RuntimeError','Ignored','Pending')){throw 'UNKNOWN_MUTANT_STATUS'}
                    if(-not $counts.ContainsKey($m.status)){$counts[$m.status]=0};$counts[$m.status]++;$count++
                }
            }
            $q.counts=$counts
            if($count -eq 0){$q.status='FAIL';return $q}
            if($counts.ContainsKey('Pending')){$q.status='NOT_RUN';return $q}
            $detected=0;$undetected=0
            foreach($name in @('Killed','Timeout')){if($counts.ContainsKey($name)){$detected+=$counts[$name]}}
            foreach($name in @('Survived','NoCoverage')){if($counts.ContainsKey($name)){$undetected+=$counts[$name]}}
            if(($detected+$undetected) -eq 0){$q.status='FAIL';return $q}
            $q.mutation_score=100.0*$detected/($detected+$undetected)
            $q.status=if($null -ne $MinimumScore -and $q.mutation_score -lt $MinimumScore){'FAIL'}else{'PASS'}
            $q.limitations=@('Stryker JSON report ingestion only; no language-tool capability inferred.','PASS records a completed report and configured threshold, not full correctness.')
            return $q
        }
        $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
        $reader=[Xml.XmlReader]::Create($Path,$settings)
        try{$doc=[Xml.XmlDocument]::new();$doc.XmlResolver=$null;$doc.Load($reader)}finally{$reader.Dispose()}
        $root=$doc.DocumentElement
        function CountAttr($Node,[string]$Name){$n=0;if(-not [int]::TryParse($Node.GetAttribute($Name),[ref]$n) -or $n -lt 0){throw 'INVALID_REPORT_COUNT'};return $n}
        if($Format -ceq 'junit'){
            if($root.Name -cne 'testsuite'){throw 'UNSUPPORTED_JUNIT_SHAPE'}
            $cases=@($root.SelectNodes('./testcase'));$total=CountAttr $root tests;$fail=CountAttr $root failures;$errors=CountAttr $root errors;$skipped=CountAttr $root skipped
            if($total -ne $cases.Count -or $fail -ne @($root.SelectNodes('./testcase/failure')).Count -or $errors -ne @($root.SelectNodes('./testcase/error')).Count -or $skipped -ne @($root.SelectNodes('./testcase/skipped')).Count -or ($fail+$errors+$skipped) -gt $total){throw 'INCOMPLETE_REPORT'}
            $q.executed_tests=$total-$skipped;$q.status=if($q.executed_tests -lt $MinimumTests -or ($fail+$errors) -gt 0){'FAIL'}else{'PASS'}
            $q.counts=@{total=$total;failed=$fail;errors=$errors;skipped=$skipped}
            $q.limitations=@('JUnit test cases do not prove assertion count or semantic adequacy.')
        }else{
            if($root.Name -cne 'test-run'){throw 'UNSUPPORTED_NUNIT_SHAPE'}
            $cases=@($root.SelectNodes('.//test-case'));$total=CountAttr $root total;$passed=CountAttr $root passed;$failed=CountAttr $root failed;$skipped=CountAttr $root skipped;$inc=CountAttr $root inconclusive;$asserts=CountAttr $root asserts
            if($total -ne $cases.Count -or $total -ne ($passed+$failed+$skipped+$inc)){throw 'INCOMPLETE_REPORT'}
            foreach($pair in @(@('Passed',$passed),@('Failed',$failed),@('Skipped',$skipped),@('Inconclusive',$inc))){if(@($cases|Where-Object {$_.GetAttribute('result') -ceq $pair[0]}).Count -ne $pair[1]){throw 'INCOMPLETE_REPORT'}}
            $q.executed_tests=$passed+$failed;$q.assertion_count=$asserts;$q.counts=@{total=$total;passed=$passed;failed=$failed;skipped=$skipped;inconclusive=$inc}
            $q.status=if($q.executed_tests -ge $MinimumTests -and $asserts -gt 0 -and $failed -eq 0 -and $inc -eq 0 -and $root.GetAttribute('result') -ceq 'Passed'){'PASS'}else{'FAIL'}
        }
    }catch{$q.status='ERROR';$q.error=$_.Exception.Message}
    return $q
}
function Get-CFCheckReportPath([string]$RepoRoot,$Check) {
    $path=$Check.report.path
    if([IO.Path]::IsPathRooted($path) -or $path.Contains('\') -or $path -match '[:*?]' -or @($path.Split('/')|Where-Object {$_ -in @('','.','..')}).Count -gt 0){throw 'INVALID_REPORT_PATH'}
    $full=[IO.Path]::GetFullPath([IO.Path]::Combine($RepoRoot,$path));Assert-CFNoLinks $full;return $full
}
function Get-CFCheckInputDigest([string]$RepoRoot,$Check) {
    $RepoRoot=(Get-CFIdentity $RepoRoot).worktree_realpath
    $entries=@(foreach($path in (Get-CFSorted $Check.inputs)){
        $full=[IO.Path]::GetFullPath([IO.Path]::Combine($RepoRoot,$path))
        Assert-CFNoLinks $full
        $missing=$false
        try{$attributes=[IO.File]::GetAttributes($full)}catch [IO.FileNotFoundException]{$missing=$true}catch [IO.DirectoryNotFoundException]{$missing=$true}
        if(-not $missing -and ($attributes -band [IO.FileAttributes]::ReparsePoint)){throw "CHECK_INPUT_LINK_FORBIDDEN: $path"}
        if(-not $missing -and ($attributes -band [IO.FileAttributes]::Directory)){throw "CHECK_INPUT_NOT_FILE: $path"}
        if(-not $missing){
            [ordered]@{path=$path;state='file';hash=(Get-CFHash ([IO.File]::ReadAllBytes($full)))}
        }else{
            [ordered]@{path=$path;state='missing';hash=''}
        }
    })
    return Get-CFJsonHash $entries
}
function Open-CFWriter([string]$RunPath,[string]$RepoRoot) {
    $identity=Get-CFIdentity $RepoRoot
    Get-CFRunLocation $RepoRoot $RunPath $identity|Out-Null
    $lockPath=[IO.Path]::Combine($RunPath,'writer.lock');Assert-CFNoLinks $lockPath
    return [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}
function Update-ControlFlowRun {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[Parameter(Mandatory)]$Event,[Nullable[int]]$ExpectedRevision)
    if($Event -isnot [Collections.IDictionary]){$Event=$Event|ConvertTo-Json -Depth 40|ConvertFrom-Json -AsHashtable}
    $lock=Open-CFWriter $RunPath $RepoRoot
    try {
        $read=Read-ControlFlowRun $RepoRoot $RunPath;$s=$read.state;$e=$read.evidence
        if($null -ne $ExpectedRevision -and $s.revision -ne $ExpectedRevision){throw 'REVISION_CONFLICT'}
        $eventCopy=$Event|ConvertTo-Json -Depth 40|ConvertFrom-Json -AsHashtable
        $eventCopy.recorded_at=[DateTime]::UtcNow.ToString('o')
        if($s.schema_version -ceq '4.0.0' -and (($s.ContainsKey('lifecycle_closed') -and $s.lifecycle_closed) -or $s.status -in @('COMPLETED','CANCELLED')) -and -not ($s.status -ceq 'COMPLETED' -and $Event.type -ceq 'stop' -and $Event.reason -ceq 'BLOCKED')){throw 'TERMINAL_RUN_IMMUTABLE'}
        if($s.schema_version -ceq '4.0.0'){Update-CFV4Event $RepoRoot $RunPath $read $Event $eventCopy}
        switch -CaseSensitive ($Event.type) {
            {$_ -in @('artifact','phase_review')} {if($s.schema_version -cne '4.0.0'){throw 'UNSUPPORTED_EVENT'}}
            {$_ -in @('preflight','review','coverage')} {
                if($s.status -ne 'ACTIVE'){throw 'RUN_NOT_ACTIVE'}
                $c=Read-ControlFlowContract $s.contract_path;$source=Get-CFRunSource $RepoRoot $RunPath $s
                $eventCopy.contract_digest=$c.digest;$eventCopy.source_digest=$source.digest
                if($Event.type -in @('preflight','review')){if($Event.status -cne 'APPROVED'){throw 'APPROVAL_REQUIRED'}}
                else {
                    if($Event.criterion_id -cnotin @($c.contract.criteria.id)){throw 'INVALID_CRITERION_REFERENCE'}
                    if(-not $Event.ContainsKey('check_ids') -or @($Event.check_ids).Count -eq 0){throw 'CAPTURE_COVERAGE_REQUIRED'}
                    foreach($id in $Event.check_ids){if($id -cnotin @($c.contract.checks.id)){throw 'INVALID_CHECK_REFERENCE'}}
                }
            }
            'blocker' {if(-not $Event.id -or $Event.status -cnotin @('OPEN','RESOLVED') -or -not $Event.text){throw 'INVALID_BLOCKER_EVENT'}}
            'stop' {
                if($Event.reason -cnotin @('CLARIFICATION','PERMISSION_DENIED','CANCEL','PLAN_MODE','BLOCKED','INTERRUPT','HUMAN_WAIT') -or -not $Event.evidence){throw 'INVALID_STOP_REASON'}
                $s.status=switch($Event.reason){'CANCEL'{'CANCELLED'};'INTERRUPT'{'INTERRUPTED'};default{$Event.reason}}
                $s.structured_reason=$eventCopy
            }
            'resume' {
                if(-not $Event.ContainsKey('user_decision_ref') -or [string]::IsNullOrWhiteSpace($Event.user_decision_ref)){throw 'EXPLICIT_USER_DECISION_REQUIRED'}
                if($s.status -eq 'COMPLETED'){throw 'COMPLETED_RUN_IMMUTABLE'}
                if($null -ne $read.pending_interrupt){$s.acknowledged_interrupt_id=$read.pending_interrupt.interrupt_id}
                $s.status='ACTIVE';$s.structured_reason=$null;$s.continuations=@{total=0;signature='';repeated=0}
            }
            'continuation' {
                if($s.status -ne 'ACTIVE' -or -not $Event.signature){throw 'INVALID_CONTINUATION'}
                $s.continuations.total++;$s.continuations.repeated=if($s.continuations.signature -ceq $Event.signature){$s.continuations.repeated+1}else{1};$s.continuations.signature=$Event.signature
                if($s.continuations.total -ge 6 -or $s.continuations.repeated -ge 3){$s.status='BLOCKED';$s.structured_reason=@{reason='BLOCKED';evidence='CONTINUATION_LIMIT';signature=$Event.signature}}
            }
            'complete' {
                $sha=if($Event.ContainsKey('commit_sha')){$Event.commit_sha}else{''}
                $gate=Test-ControlFlowGate $RepoRoot $RunPath 'Completion' -CommitSha $sha
                if($gate.status -ne 'PASS'){throw ('COMPLETION_GATE_REJECTED: '+($gate.reasons -join ','))}
                $s.status='COMPLETED';if($s.schema_version -ceq '4.0.0'){$s.lifecycle_closed=$true};$eventCopy.gate=$gate
            }
            default {throw 'UNSUPPORTED_EVENT'}
        }
        # Every persisted lawful stop pins its first source boundary, including
        # implicit continuation/correction limits that do not emit a stop event.
        if($s.schema_version -ceq '4.0.0' -and $s.status -in @('CLARIFICATION','PERMISSION_DENIED','CANCELLED','PLAN_MODE','BLOCKED','INTERRUPTED','HUMAN_WAIT') -and -not $s.stop_source_digest){$s.stop_source_digest=$s.last_observed_source_digest}
        $e.events=@($e.events)+@($eventCopy);$s.revision++;Publish-CFState $RunPath $s $e
        return Read-ControlFlowRun $RepoRoot $RunPath
    }finally{$lock.Dispose()}
}
function Capture-ControlFlowCheck {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[Parameter(Mandatory)][string]$CheckId)
    $RepoRoot=(Get-CFIdentity $RepoRoot).worktree_realpath
    $lock=Open-CFWriter $RunPath $RepoRoot
    try {
        $read=Read-ControlFlowRun $RepoRoot $RunPath;$state=$read.state
        if($state.status -ne 'ACTIVE'){throw 'RUN_NOT_ACTIVE'}
        $c=Read-ControlFlowContract $state.contract_path;if($state.schema_version -ceq '4.0.0'){Assert-CFV4Execution $read $c}
        $check=@($c.contract.checks|Where-Object {$_.id -ceq $CheckId})
        if($check.Count -ne 1){throw 'UNKNOWN_CHECK'};$check=$check[0]
        $cwd=[IO.Path]::GetFullPath((Join-Path $RepoRoot $check.working_directory));$rel=[IO.Path]::GetRelativePath($RepoRoot,$cwd)
        if([IO.Path]::IsPathRooted($rel) -or $rel -eq '..' -or $rel.StartsWith('../') -or $rel.StartsWith('..\')){throw 'CHECK_CWD_OUTSIDE_REPOSITORY'}
        Assert-CFNoLinks $cwd
        $before=Get-CFRunSource $RepoRoot $RunPath $state
        $inputBefore=if($check.ContainsKey('inputs')){Get-CFCheckInputDigest $RepoRoot $check}else{$null}
        $reportPath=$null;$reportStamp=$null;if($check.ContainsKey('report')){$reportPath=Get-CFCheckReportPath $RepoRoot $check;if([IO.File]::Exists($reportPath)){$reportStamp=[IO.File]::GetLastWriteTimeUtc($reportPath).Ticks}}
        $timeout=if($check.ContainsKey('timeout_seconds')){[int]$check.timeout_seconds}else{120}
        $command='& { '+$check.command+"`n"+' }; if (-not $?) { exit 1 }; if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
        $result=Invoke-CFProcess (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) @('-NoProfile','-NonInteractive','-Command',$command) $cwd @{} $timeout $true
        $after=Get-CFRunSource $RepoRoot $RunPath $state;$afterContract=Read-ControlFlowContract $state.contract_path
        $inputAfter=if($check.ContainsKey('inputs')){Get-CFCheckInputDigest $RepoRoot $check}else{$null}
        $status=if($result.timed_out){'TIMEOUT'}elseif($result.process_incomplete){'FAIL'}elseif($before.digest -cne $after.digest -or $c.digest -cne $afterContract.digest -or $inputBefore -cne $inputAfter){'STALE'}elseif($result.exit_code -ne 0){'FAIL'}else{'PASS'}
        $capture=@{capture_id=[guid]::NewGuid().ToString('N');check_id=$CheckId;status=$status;exit_code=$result.exit_code;timed_out=$result.timed_out;command=$check.command;working_directory=$check.working_directory;command_digest=(Get-CFJsonHash $check);contract_digest=$c.digest;source_before=$before.digest;source_after=$after.digest;recorded_at=[DateTime]::UtcNow.ToString('o');stdout_ref=(Write-CFImmutable $RunPath 'output' $result.stdout 'stdout.bin');stderr_ref=(Write-CFImmutable $RunPath 'output' $result.stderr 'stderr.bin')}
        $capture.process_incomplete=$result.process_incomplete
        if($state.schema_version -ceq '4.0.0'){$state.last_observed_source_digest=$after.digest}
        if($check.ContainsKey('report')){
            $min=if($check.report.ContainsKey('minimum_tests')){[int]$check.report.minimum_tests}else{1}
            $score=if($check.report.ContainsKey('minimum_score')){[double]$check.report.minimum_score}else{$null}
            $quality=Read-ControlFlowQualityReport $reportPath $check.report.format $min $score
            foreach($key in @('tool','version','scope','config','baseline','exclusions')){$quality[$key]=$check.report[$key]}
            if([IO.File]::Exists($reportPath)){
                Assert-CFNoLinks $reportPath
                $quality.raw_report_ref=Write-CFImmutable $RunPath 'output' ([IO.File]::ReadAllBytes($reportPath)) 'stdout.bin'
                if($null -ne $reportStamp -and [IO.File]::GetLastWriteTimeUtc($reportPath).Ticks -le $reportStamp){$quality.status='NOT_RUN';$quality.error='REPORT_NOT_REWRITTEN'}
            }
            $capture.quality=$quality
            if($capture.status -ceq 'PASS' -and $quality.status -cne 'PASS'){$capture.status='FAIL'}
        }
        if($check.ContainsKey('inputs')){$capture.input_before=$inputBefore;$capture.input_after=$inputAfter}
        $read.evidence.checks=@($read.evidence.checks)+@($capture);$state.revision++;Publish-CFState $RunPath $state $read.evidence
        return $capture
    }finally{$lock.Dispose()}
}
