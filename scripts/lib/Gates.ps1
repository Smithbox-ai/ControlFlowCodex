function Get-CFEntriesMap($Entries) { $map=Get-CFMap;foreach($entry in $Entries){$map.Add($entry.path,$entry)};return ,$map }
function Test-CFV4CodeCriterion($Contract,[string]$Id) {
    foreach($req in $Contract.review_policy.requirements){
        if('code' -cnotin $req.judges){continue}
        if($req.target_id -ceq $Id){return $true}
        if($Contract.ContainsKey('phases')){foreach($phase in $Contract.phases){if($phase.id -ceq $req.target_id -and $Id -cin $phase.criteria){return $true}}}
    }
    return $false
}
function Test-CFV4RequiredCheck($Contract,[string]$Id) {
    foreach($profile in $Contract.quality_profiles){if($profile.required -and $Id -cin $profile.check_ids){return $true}}
    $definition=@($Contract.checks|Where-Object {$_.id -ceq $Id})
    if($definition.Count -eq 1){foreach($criterion in $definition[0].criteria){if(Test-CFV4CodeCriterion $Contract $criterion){return $true}}}
    return $false
}
function Get-CFV4ProfileCapability($Contract,$Profile) {
    if($Profile.capability -cne 'available'){return $Profile.capability}
    # Only adapters whose report semantics are recognized can establish quality.
    $formats=switch -CaseSensitive($Profile.kind){'mutation'{@('stryker-json')};{$_ -in @('tests','environment','lint')}{@('junit','nunit3')};default{@()}}
    if(@($formats).Count -eq 0){return 'unsupported'}
    foreach($id in $Profile.check_ids){
        $defs=@($Contract.checks|Where-Object {$_.id -ceq $id})
        if($defs.Count -ne 1 -or -not $defs[0].ContainsKey('report') -or $defs[0].report.format -cnotin @($formats)){return 'unsupported'}
    }
    return 'available'
}
function Test-CFV4MutationScope($Check,$Capture) {
    if(-not $Check.ContainsKey('report') -or $Check.report.format -cne 'stryker-json'){return $true}
    if(-not $Capture.ContainsKey('quality') -or $null -eq $Capture.quality){return $false}
    $quality=$Capture.quality
    if(-not $quality.ContainsKey('scope_verified') -or $quality.scope_verified -isnot [bool] -or -not $quality.scope_verified -or -not $quality.ContainsKey('verified_scope') -or -not $Check.report.ContainsKey('scope')){return $false}
    if(@($Check.report.scope).Count -eq 0 -or @($quality.verified_scope).Count -ne @($Check.report.scope).Count){return $false}
    return (Get-CFJsonHash @(Get-CFSorted $quality.verified_scope)) -ceq (Get-CFJsonHash @(Get-CFSorted $Check.report.scope))
}
function Get-CFV4ProfileSummary($Read,$ContractRead,$Source,$Profile) {
    $capability=Get-CFV4ProfileCapability $ContractRead.contract $Profile
    $observations=@(foreach($id in $Profile.check_ids){
        $reasons=[Collections.Generic.List[string]]::new()
        $defs=@($ContractRead.contract.checks|Where-Object {$_.id -ceq $id})
        $captures=@($Read.evidence.checks|Where-Object {$_.check_id -ceq $id})
        $capture=if($captures.Count -gt 0){$captures[-1]}else{$null}
        $observation=[ordered]@{check_id=$id;status='NOT_RUN';capture_id=$null;capture_status='NOT_RUN';exit_code=$null;timed_out=$false;process_incomplete=$false;quality_status='NOT_RUN';reasons=@();quality=$null}
        if($null -eq $capture){$reasons.Add('CAPTURE_MISSING')}
        elseif($defs.Count -ne 1){$reasons.Add('CHECK_DEFINITION_MISSING')}
        else {
            $def=$defs[0];$observation.capture_id=$capture.capture_id;$observation.capture_status=$capture.status
            $observation.exit_code=$capture.exit_code;$observation.timed_out=$capture.timed_out
            if($capture.ContainsKey('process_incomplete')){$observation.process_incomplete=$capture.process_incomplete}
            $quality=if($capture.ContainsKey('quality')){$capture.quality}else{$null}
            if($null -ne $quality){
                $observation.quality_status=$quality.status
                # Keep the parsed observations, never arbitrary stdout, stderr, or report bodies.
                $observation.quality=[ordered]@{}
                foreach($key in @('status','format','executed_tests','assertion_count','mutation_score','minimum_score','acceptance_status','scope_verified','verified_scope','counts','limitations','error','tool','version','scope','config','baseline','exclusions','raw_report_ref')){
                    if($quality.ContainsKey($key)){$observation.quality[$key]=$quality[$key]}
                }
            }
            if($capture.status -ceq 'STALE'){$reasons.Add('CAPTURE_MARKED_STALE')}
            if($capture.contract_digest -cne $ContractRead.digest){$reasons.Add('CAPTURE_CONTRACT_MISMATCH')}
            if($capture.command_digest -cne (Get-CFJsonHash $def)){$reasons.Add('CAPTURE_COMMAND_MISMATCH')}
            if($capture.source_before -cne $Source.digest -or $capture.source_after -cne $Source.digest){$reasons.Add('CAPTURE_SOURCE_MISMATCH')}
            if(Test-CFCheckHasInputs $def){
                try{
                    $inputs=Get-CFCheckInputDigest $Read.state.binding.worktree_realpath $def
                    if(-not $capture.ContainsKey('input_before') -or -not $capture.ContainsKey('input_after') -or $capture.input_before -cne $inputs -or $capture.input_after -cne $inputs){$reasons.Add('CAPTURE_INPUT_MISMATCH')}
                }catch{$reasons.Add('CAPTURE_INPUT_UNVERIFIABLE')}
            }
            $stale=$reasons.Count -gt 0
            $timeout=$capture.timed_out -or $capture.status -ceq 'TIMEOUT'
            $processFailed=$capture.exit_code -ne 0 -or ($capture.ContainsKey('process_incomplete') -and $capture.process_incomplete)
            $wrapperFailed=$capture.status -ceq 'FAIL' -or $processFailed
            $hasReport=$def.ContainsKey('report')
            $reportMissing=$hasReport -and ($null -eq $quality -or -not $quality.ContainsKey('raw_report_ref'))
            $scopeUnverified=-not (Test-CFV4MutationScope $def $capture)
            if($timeout){$reasons.Add('CAPTURE_TIMED_OUT')}
            if($wrapperFailed){$reasons.Add('CAPTURE_FAILED')}
            if($reportMissing){$reasons.Add('QUALITY_REPORT_MISSING')}
            if($scopeUnverified){$reasons.Add('QUALITY_SCOPE_UNVERIFIED')}
            if($hasReport -and $null -ne $quality){
                switch -CaseSensitive($quality.status){
                    'FAIL'{$reasons.Add('QUALITY_REPORT_FAILED')}
                    'ERROR'{$reasons.Add('QUALITY_REPORT_ERROR')}
                    'NOT_RUN'{$reasons.Add('QUALITY_REPORT_NOT_RUN')}
                    'UNSUPPORTED'{$reasons.Add('QUALITY_REPORT_UNSUPPORTED')}
                }
            }
            # Freshness describes whether any captured outcome applies to this source.
            # An absent/pending report alone remains NOT_RUN; process failures remain FAIL.
            $observation.status=if($stale){'STALE'}
                elseif($capture.status -ceq 'ERROR' -or ($hasReport -and $null -ne $quality -and $quality.status -ceq 'ERROR')){'ERROR'}
                elseif($timeout){'TIMEOUT'}
                elseif($processFailed){'FAIL'}
                elseif($reportMissing -or $scopeUnverified -or ($hasReport -and $quality.status -cin @('NOT_RUN','UNSUPPORTED'))){'NOT_RUN'}
                elseif($wrapperFailed -or ($hasReport -and $quality.status -ceq 'FAIL')){'FAIL'}
                elseif($capture.status -ceq 'PASS' -and (-not $hasReport -or $quality.status -ceq 'PASS')){'PASS'}
                else{'NOT_RUN'}
            if($observation.status -ceq 'NOT_RUN' -and $reasons.Count -eq 0){$reasons.Add('CAPTURE_NOT_RUN')}
        }
        $observation.reasons=@($reasons)
        $observation
    })
    $status=switch -CaseSensitive($capability){
        'unsupported'{'UNSUPPORTED'}
        'not_applicable'{'NOT_APPLICABLE'}
        'unknown'{'NOT_RUN'}
        default {
            if($observations.Count -eq 0){'NOT_RUN'}
            else{foreach($candidate in @('ERROR','FAIL','TIMEOUT','STALE','NOT_RUN','PASS')){if($candidate -cin @($observations.status)){$candidate;break}}}
        }
    }
    return [ordered]@{id=$Profile.id;kind=$Profile.kind;required=$Profile.required;status=$status;capability=$Profile.capability;check_ids=$Profile.check_ids;observations=$observations;reasons=@(foreach($observation in $observations){foreach($reason in $observation.reasons){$observation.check_id+':'+$reason}})}
}
function Get-CFV4GateReasons($Read,$ContractRead,$Source,$Fresh,$InputDigests=$null) {
    $c=$ContractRead.contract;$artifacts=Get-CFV4Artifacts $Read $c
    if($c.contract_status -cne 'final'){'DRAFT_CANNOT_COMPLETE';return}
    try{Assert-CFV4Execution $Read $ContractRead}catch{'V4_PREFLIGHT_MISSING_OR_STALE'}
    foreach($kind in $c.workflow.required_artifacts){
        if(-not $artifacts.ContainsKey($kind)){('ARTIFACT_MISSING_OR_STALE:'+$kind);continue}
        if($kind -in @('qa-recheck','review-packet') -and ($artifacts[$kind].artifact.source_digest -cne $Source.digest -or $artifacts[$kind].contract_digest -cne $ContractRead.digest)){('ARTIFACT_SOURCE_STALE:'+$kind)}
    }
    if($artifacts.ContainsKey('review-packet') -and $artifacts['review-packet'].artifact.payload.open_decisions.Count -gt 0){'OPEN_PACKET_DECISIONS'}
    if($artifacts.ContainsKey('qa-plan')){foreach($scenario in $artifacts['qa-plan'].artifact.payload.scenarios){foreach($id in $scenario.check_refs){if(-not (Test-CFV4Capture $Read $ContractRead $Source $id -InputDigests $InputDigests)){('QA_CAPTURE_MISSING_OR_STALE:'+$id)}}}}
    if($c.review_policy.human_design -and (-not $artifacts.ContainsKey('design') -or -not (Test-CFV4Review $Read $ContractRead $artifacts.design.ref human design))){'HUMAN_DESIGN_REQUIRED'}
    foreach($req in $c.review_policy.requirements){foreach($judge in $req.judges){
        if($judge -ceq 'code'){
            $ids=@(if($req.target_id -cin @($c.criteria|ForEach-Object {$_.id})){$req.target_id}else{($c.phases|Where-Object {$_.id -ceq $req.target_id}).criteria})
            foreach($id in $ids){if(@($c.checks|Where-Object {$id -cin $_.criteria -and $Fresh.ContainsKey($_.id)}).Count -eq 0){('CODE_JUDGE_MISSING:'+$req.target_id)}}
        }else{
            if(-not $artifacts.ContainsKey('review-packet') -or -not (Test-CFV4Review $Read $ContractRead $artifacts['review-packet'].ref $judge $req.target_id)){('JUDGE_MISSING:'+$req.target_id+':'+$judge)}
        }
    }}
    if($c.review_policy.human_final -and (-not $artifacts.ContainsKey('review-packet') -or -not (Test-CFV4Review $Read $ContractRead $artifacts['review-packet'].ref human final))){'HUMAN_FINAL_REQUIRED'}
    foreach($profile in $c.quality_profiles){if($profile.required){
        if((Get-CFV4ProfileCapability $c $profile) -cne 'available'){('REQUIRED_PROFILE_UNSUPPORTED:'+$profile.id)}
        foreach($id in $profile.check_ids){if(-not $Fresh.ContainsKey($id)){('PROFILE_EVIDENCE_MISSING:'+$profile.id)}}
    }}
}
function Get-CFEntryIdentity($Entry) { if($null -eq $Entry){return 'absent'};return "$($Entry.mode):$($Entry.hash)" }
function Get-CFIndexIdentity($Entry) { if($null -eq $Entry){return 'absent'};return "$($Entry.mode):$($Entry.oid):$($Entry.stage)" }
function New-CFCandidate([string]$RepoRoot,[string]$RunPath,[string[]]$OwnedPaths,$State,[string]$SourceDigest,[string]$ContractDigest) {
    $indexPath=[IO.Path]::Combine($RunPath,([guid]::NewGuid().ToString('N')+'.index'))
    $envVars=@{GIT_INDEX_FILE=$indexPath};$parent=Get-CFGitText $RepoRoot @('rev-parse','HEAD')
    # External namespaces may exceed Windows MAX_PATH. Keep this override local
    # to the temporary index operations rather than changing repository config.
    $gitOptions=@('-c','core.longpaths=true')
    try {
        Invoke-CFGit $RepoRoot ($gitOptions+@('read-tree',$parent)) $envVars|Out-Null
        $paths=@($OwnedPaths|ForEach-Object {':(literal)'+$_})
        Invoke-CFGit $RepoRoot ($gitOptions+@('add','-A','--')+$paths) $envVars|Out-Null
        $tree=Get-CFGitText $RepoRoot ($gitOptions+@('write-tree')) $envVars
        $after=Get-CFRunSource $RepoRoot $RunPath $State
        if($after.digest -cne $SourceDigest -or (Read-ControlFlowContract $State.contract_path).digest -cne $ContractDigest){throw 'SOURCE_CHANGED_DURING_GATE'}
        return @{parent=$parent;tree=$tree;owned_paths=$OwnedPaths;source_digest=$SourceDigest;contract_digest=$ContractDigest;recorded_at=[DateTime]::UtcNow.ToString('o')}
    }finally {if([IO.File]::Exists($indexPath)){[IO.File]::Delete($indexPath)}}
}
function Test-ControlFlowGate {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[Parameter(Mandatory)][ValidateSet('Commit','Completion')][string]$Kind,[string]$CommitSha)
    $result=@{schema_version='4.0.0';kind=$Kind;status='ERROR';reasons=@();run_id=$null;source_digest=$null;contract_hash=$null;input_digests=@{};legacy_semantics=$false}
    $lock=$null
    try {
        if($Kind -eq 'Commit'){$lock=Open-CFWriter $RunPath $RepoRoot}
        $read=Read-ControlFlowRun $RepoRoot $RunPath;$s=$read.state;$e=$read.evidence;$initial=$read.initial_snapshot
        $RepoRoot=$s.binding.worktree_realpath
        $result.run_id=$s.run_id;$result.legacy_semantics=($s.schema_version -ceq '3.0.0')
        $c=Read-ControlFlowContract $s.contract_path;$contract=$c.contract;$result.contract_hash=$c.digest;$result.schema_version=$s.schema_version
        $source=Get-CFRunSource $RepoRoot $RunPath $s;$result.source_digest=$source.digest
        $reasons=[Collections.Generic.List[string]]::new()
        if($s.status -notin @('ACTIVE','COMPLETED')){$reasons.Add('RUN_NOT_ACTIVE')}
        if($contract.task_id -cne $s.task_id -or $contract.baseline.commit -cne $s.baseline_commit){$reasons.Add('CONTRACT_BINDING_CHANGED')}
        if($Kind -eq 'Commit' -and $contract.commit.mode -ne 'required'){$reasons.Add('COMMIT_NOT_REQUESTED')}
        if($contract.schema_version -ceq '3.0.0' -and $contract.tier -in @('MEDIUM','LARGE')) {
            foreach($type in @('preflight','review')) {
                $approvals=@($e.events|Where-Object {$_.type -ceq $type})
                if($approvals.Count -eq 0){$reasons.Add(($type.ToUpperInvariant()+'_MISSING'));continue}
                $approval=$approvals[-1]
                if($approval.status -cne 'APPROVED' -or $approval.contract_digest -cne $c.digest -or ($type -eq 'review' -and $approval.source_digest -cne $source.digest)){$reasons.Add(($type.ToUpperInvariant()+'_STALE'))}
            }
        }
        $fresh=Get-CFMap;$inputDigests=Get-CFMap
        foreach($check in $contract.checks) {
            if($contract.schema_version -ceq '4.0.0' -and -not (Test-CFV4RequiredCheck $contract $check.id)){continue}
            $captures=@($e.checks|Where-Object {$_.check_id -ceq $check.id})
            if($captures.Count -eq 0){$reasons.Add('CHECK_MISSING:'+$check.id);continue}
            $capture=$captures[-1]
            if($capture.status -cne 'PASS' -or $capture.exit_code -ne 0 -or $capture.timed_out){$reasons.Add('CHECK_FAILED:'+$check.id);continue}
            if($capture.contract_digest -cne $c.digest -or $capture.command_digest -cne (Get-CFJsonHash $check) -or $capture.source_before -cne $source.digest -or $capture.source_after -cne $source.digest){$reasons.Add('CHECK_STALE:'+$check.id);continue}
            if(Test-CFCheckHasInputs $check){
                $inputDigest=Get-CFCheckInputDigest $RepoRoot $check
                if(-not $capture.ContainsKey('input_before') -or -not $capture.ContainsKey('input_after') -or $capture.input_before -cne $inputDigest -or $capture.input_after -cne $inputDigest){$reasons.Add('CHECK_STALE:'+$check.id);continue}
                $inputDigests[$check.id]=$inputDigest
            }
            if($contract.schema_version -ceq '4.0.0' -and -not (Test-CFV4MutationScope $check $capture)){$reasons.Add('CHECK_MUTATION_SCOPE_UNVERIFIED:'+$check.id);continue}
            $fresh[$check.id]=$true
        }
        foreach($criterion in $contract.criteria) {
            if($contract.schema_version -ceq '4.0.0' -and -not (Test-CFV4CodeCriterion $contract $criterion.id)){continue}
            $coverage=@($e.events|Where-Object {$_.type -ceq 'coverage' -and $_.criterion_id -ceq $criterion.id})
            $valid=$false
            if($coverage.Count -gt 0) {
                $coverage=$coverage[-1]
                if($coverage.contract_digest -ceq $c.digest -and $coverage.source_digest -ceq $source.digest){
                    foreach($checkId in $coverage.check_ids){$definition=@($contract.checks|Where-Object {$_.id -ceq $checkId});if($fresh.ContainsKey($checkId) -and $definition.Count -eq 1 -and $criterion.id -cin $definition[0].criteria){$valid=$true}}
                }
            }
            if(-not $valid){$reasons.Add('CRITERION_UNCOVERED:'+$criterion.id)}
        }
        if($contract.schema_version -ceq '4.0.0'){foreach($reason in @(Get-CFV4GateReasons $read $c $source $fresh $inputDigests)){$reasons.Add($reason)}}
        $blockers=Get-CFMap;foreach($event in $e.events){if($event.type -ceq 'blocker'){$blockers[$event.id]=$event.status}}
        foreach($id in $blockers.Keys){if($blockers[$id] -eq 'OPEN'){$reasons.Add('OPEN_BLOCKER:'+$id)}}
        $current=Get-ControlFlowGitSnapshot $RepoRoot $RunPath $s.binding.session_id
        $oldEntries=Get-CFEntriesMap $initial.source.entries;$newEntries=Get-CFEntriesMap $source.entries
        $oldIndex=Get-CFEntriesMap $initial.index;$newIndex=Get-CFEntriesMap $current.index
        $foreign=[Collections.Generic.HashSet[string]]::new([string[]]@($initial.dirty_paths),[StringComparer]::Ordinal)
        foreach($path in $foreign) {
            $before=if($oldEntries.ContainsKey($path)){$oldEntries[$path]}else{$null};$after=if($newEntries.ContainsKey($path)){$newEntries[$path]}else{$null}
            if((Get-CFEntryIdentity $before) -cne (Get-CFEntryIdentity $after)){$reasons.Add('FOREIGN_WORKTREE_CHANGED:'+$path)}
            $before=if($oldIndex.ContainsKey($path)){$oldIndex[$path]}else{$null};$after=if($newIndex.ContainsKey($path)){$newIndex[$path]}else{$null}
            if((Get-CFIndexIdentity $before) -cne (Get-CFIndexIdentity $after)){$reasons.Add('FOREIGN_INDEX_CHANGED:'+$path)}
        }
        $allPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($path in $oldEntries.Keys){[void]$allPaths.Add($path)};foreach($path in $newEntries.Keys){[void]$allPaths.Add($path)}
        $owned=[Collections.Generic.List[string]]::new()
        foreach($path in (Get-CFSorted $allPaths)) {
            $before=if($oldEntries.ContainsKey($path)){$oldEntries[$path]}else{$null};$after=if($newEntries.ContainsKey($path)){$newEntries[$path]}else{$null}
            if((Get-CFEntryIdentity $before) -ceq (Get-CFEntryIdentity $after)){continue}
            if($foreign.Contains($path)){$reasons.Add('FOREIGN_OWNERSHIP_OVERLAP:'+$path);continue}
            if(-not (Test-ControlFlowScope $path $contract.scope)){$reasons.Add('OUT_OF_SCOPE:'+$path);continue}
            $owned.Add($path)
        }
        $indexPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($path in $oldIndex.Keys){[void]$indexPaths.Add($path)}
        foreach($path in $newIndex.Keys){[void]$indexPaths.Add($path)}
        foreach($path in (Get-CFSorted $indexPaths)) {
            if($foreign.Contains($path) -or $path -cin $owned){continue}
            $old=if($oldIndex.ContainsKey($path)){$oldIndex[$path]}else{$null}
            $new=if($newIndex.ContainsKey($path)){$newIndex[$path]}else{$null}
            if((Get-CFIndexIdentity $old) -cne (Get-CFIndexIdentity $new)){$reasons.Add('UNOWNED_INDEX_CHANGED:'+$path)}
        }
        if($Kind -eq 'Completion' -and $contract.commit.mode -eq 'required') {
            $candidate=$e.candidate
            if(-not $candidate){$reasons.Add('COMMIT_GATE_PROOF_MISSING')}
            elseif($candidate.contract_digest -cne $c.digest -or $candidate.source_digest -cne $source.digest){$reasons.Add('COMMIT_GATE_PROOF_STALE')}
            else {
                if(-not $CommitSha){$CommitSha=$current.head}
                if($CommitSha -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$'){$reasons.Add('INVALID_COMMIT_SHA')}
                else {
                    $actual=Get-CFGitText $RepoRoot @('rev-parse','--verify',"$CommitSha^{commit}")
                    $tree=Get-CFGitText $RepoRoot @('rev-parse',"$CommitSha^{tree}")
                    $parents=Get-CFGitText $RepoRoot @('show','-s','--format=%P',$CommitSha)
                    if($actual -cne $CommitSha -or $current.head -cne $CommitSha -or $tree -cne $candidate.tree -or $parents -cne $candidate.parent){$reasons.Add('COMMIT_TREE_OR_PARENT_MISMATCH')}
                    $diff=@(Get-CFNul (Invoke-CFGit $RepoRoot @('diff-tree','--no-commit-id','--name-only','--no-renames','-r','-z',$CommitSha)))
                    if((Get-CFJsonHash @(Get-CFSorted $diff)) -cne (Get-CFJsonHash @(Get-CFSorted $candidate.owned_paths))){$reasons.Add('COMMIT_OWNED_PATHS_MISMATCH')}
                }
            }
        }
        if($Kind -eq 'Commit' -and $reasons.Count -eq 0) {
            if($owned.Count -eq 0){$reasons.Add('NO_OWNED_CHANGES')}
            else {
                $candidate=New-CFCandidate $RepoRoot $RunPath $owned.ToArray() $s $source.digest $c.digest
                $e.candidate=$candidate;$s.revision++;Publish-CFState $RunPath $s $e;$result.candidate=$candidate
            }
        }
        if($Kind -eq 'Completion' -and $reasons.Count -eq 0){
            $finalSource=Get-CFRunSource $RepoRoot $RunPath $s
            $finalContract=Read-ControlFlowContract $s.contract_path
            if($finalSource.digest -cne $source.digest){$reasons.Add('SOURCE_CHANGED_DURING_GATE')}
            if($finalContract.digest -cne $c.digest){$reasons.Add('CONTRACT_CHANGED_DURING_GATE')}
            foreach($id in $inputDigests.Keys){
                $definition=@($contract.checks|Where-Object {$_.id -ceq $id})[0]
                if((Get-CFCheckInputDigest $RepoRoot $definition) -cne $inputDigests[$id]){$reasons.Add('CHECK_INPUT_CHANGED_DURING_GATE:'+$id)}
            }
            $pending=Read-CFPendingInterrupt $RunPath $s
            $ack=if($s.ContainsKey('acknowledged_interrupt_id')){$s.acknowledged_interrupt_id}else{$null}
            if($null -ne $pending -and $pending.interrupt_id -cne $ack){$reasons.Add('INTERRUPT_PENDING')}
        }
        $result.input_digests=$inputDigests
        $result.reasons=@($reasons);$result.status=if($reasons.Count -eq 0){'PASS'}else{'FAIL'}
    }catch{$result.status='ERROR';$result.reasons=@('UNVERIFIABLE');$result.error=$_.Exception.Message}
    finally{if($lock){$lock.Dispose()}}
    return $result
}
