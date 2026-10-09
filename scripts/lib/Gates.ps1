function Get-CFEntriesMap($Entries) { $map=Get-CFMap;foreach($entry in $Entries){$map.Add($entry.path,$entry)};return ,$map }
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
    $result=@{schema_version='3.0.0';kind=$Kind;status='ERROR';reasons=@();run_id=$null;source_digest=$null;contract_hash=$null}
    $lock=$null
    try {
        if($Kind -eq 'Commit'){$lock=Open-CFWriter $RunPath $RepoRoot}
        $read=Read-ControlFlowRun $RepoRoot $RunPath;$s=$read.state;$e=$read.evidence;$initial=$read.initial_snapshot
        $result.run_id=$s.run_id
        $c=Read-ControlFlowContract $s.contract_path;$contract=$c.contract;$result.contract_hash=$c.digest
        $source=Get-CFRunSource $RepoRoot $RunPath $s;$result.source_digest=$source.digest
        $reasons=[Collections.Generic.List[string]]::new()
        if($s.status -notin @('ACTIVE','COMPLETED')){$reasons.Add('RUN_NOT_ACTIVE')}
        if($contract.task_id -cne $s.task_id -or $contract.baseline.commit -cne $s.baseline_commit){$reasons.Add('CONTRACT_BINDING_CHANGED')}
        if($Kind -eq 'Commit' -and $contract.commit.mode -ne 'required'){$reasons.Add('COMMIT_NOT_REQUESTED')}
        if($contract.tier -in @('MEDIUM','LARGE')) {
            foreach($type in @('preflight','review')) {
                $approvals=@($e.events|Where-Object {$_.type -ceq $type})
                if($approvals.Count -eq 0){$reasons.Add(($type.ToUpperInvariant()+'_MISSING'));continue}
                $approval=$approvals[-1]
                if($approval.status -cne 'APPROVED' -or $approval.contract_digest -cne $c.digest -or ($type -eq 'review' -and $approval.source_digest -cne $source.digest)){$reasons.Add(($type.ToUpperInvariant()+'_STALE'))}
            }
        }
        $fresh=Get-CFMap
        foreach($check in $contract.checks) {
            $captures=@($e.checks|Where-Object {$_.check_id -ceq $check.id})
            if($captures.Count -eq 0){$reasons.Add('CHECK_MISSING:'+$check.id);continue}
            $capture=$captures[-1]
            if($capture.status -cne 'PASS' -or $capture.exit_code -ne 0 -or $capture.timed_out){$reasons.Add('CHECK_FAILED:'+$check.id);continue}
            if($capture.contract_digest -cne $c.digest -or $capture.command_digest -cne (Get-CFJsonHash $check) -or $capture.source_before -cne $source.digest -or $capture.source_after -cne $source.digest){$reasons.Add('CHECK_STALE:'+$check.id);continue}
            $fresh[$check.id]=$true
        }
        foreach($criterion in $contract.criteria) {
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
        $result.reasons=@($reasons);$result.status=if($reasons.Count -eq 0){'PASS'}else{'FAIL'}
    }catch{$result.status='ERROR';$result.reasons=@('UNVERIFIABLE');$result.error=$_.Exception.Message}
    finally{if($lock){$lock.Dispose()}}
    return $result
}
