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
    if($Reference.path -cnotmatch '^(initial|evidence|output)/[a-f0-9]{32}\.(json|stdout\.bin|stderr\.bin)$' -or $Reference.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'INVALID_LEDGER_REFERENCE'}
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
    $state=@{schema_version='3.0.0';task_id=$contract.task_id;run_id=$id;binding=$identity;revision=0;status='ACTIVE';contract_path=$canonical;initial_contract_digest=$read.digest;baseline_commit=$contract.baseline.commit;manual_fallback=[bool]$ManualFallback;continuations=@{total=0;signature='';repeated=0};structured_reason=$null;acknowledged_interrupt_id=$null;initial_ref=(Write-CFImmutable $runPath 'initial' $script:Utf8.GetBytes(($initial|ConvertTo-Json -Depth 80 -Compress)));evidence_ref=$null}
    Publish-CFState $runPath $state @{events=@();checks=@();candidate=$null}
    if($SessionId){
        $active=Get-CFActivePath $RepoRoot $SessionId;Assert-CFNoLinks $active;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($active))|Out-Null
        Assert-CFNoLinks ($active+'.lock')
        $activeLock=[IO.File]::Open($active+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            if([IO.File]::Exists($active)) { $prior=Get-ControlFlowActiveRun $RepoRoot $SessionId;if($prior.state.status -notin @('COMPLETED','CANCELLED')){throw 'SESSION_ALREADY_ACTIVE'} }
            $pointer=@{schema_version='3.0.0';run_path=$runPath;run_id=$id;task_id=$contract.task_id;binding=$identity}
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
    $initial=Read-CFReference $RunPath $state.initial_ref;$evidence=Read-CFReference $RunPath $state.evidence_ref
    foreach($check in $evidence.checks){Read-CFReference $RunPath $check.stdout_ref -Binary|Out-Null;Read-CFReference $RunPath $check.stderr_ref -Binary|Out-Null}
    $pending=Read-CFPendingInterrupt $RunPath $state
    $ack=if($state.ContainsKey('acknowledged_interrupt_id')){$state.acknowledged_interrupt_id}else{$null}
    if($null -ne $pending -and $pending.interrupt_id -cne $ack){
        $state.status='INTERRUPTED'
        $state.structured_reason=@{reason='INTERRUPT';evidence='NATIVE_PENDING_INTERRUPT';interrupt_id=$pending.interrupt_id;native_evidence=$pending.native_evidence}
    }
    return @{state=$state;evidence=$evidence;initial_snapshot=$initial;run_path=$RunPath;pending_interrupt=$pending}
}
function Get-ControlFlowActiveRun {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$SessionId)
    $header=Resolve-CFActiveHeader $RepoRoot $SessionId
    if($null -eq $header){return $null}
    return Read-ControlFlowRun $header.state.binding.worktree_realpath $header.run_path $SessionId
}
function Get-CFRunSource([string]$RepoRoot,[string]$RunPath,$State) { Get-ControlFlowSourceDigest $RepoRoot $State.baseline_commit $RunPath $State.binding.session_id }
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
        switch -CaseSensitive ($Event.type) {
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
                if($Event.reason -cnotin @('CLARIFICATION','PERMISSION_DENIED','CANCEL','PLAN_MODE','BLOCKED','INTERRUPT') -or -not $Event.evidence){throw 'INVALID_STOP_REASON'}
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
                $s.status='COMPLETED';$eventCopy.gate=$gate
            }
            default {throw 'UNSUPPORTED_EVENT'}
        }
        $e.events=@($e.events)+@($eventCopy);$s.revision++;Publish-CFState $RunPath $s $e
        return Read-ControlFlowRun $RepoRoot $RunPath
    }finally{$lock.Dispose()}
}
function Capture-ControlFlowCheck {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[Parameter(Mandatory)][string]$CheckId)
    $lock=Open-CFWriter $RunPath $RepoRoot
    try {
        $read=Read-ControlFlowRun $RepoRoot $RunPath;$state=$read.state
        if($state.status -ne 'ACTIVE'){throw 'RUN_NOT_ACTIVE'}
        $c=Read-ControlFlowContract $state.contract_path;$check=@($c.contract.checks|Where-Object {$_.id -ceq $CheckId})
        if($check.Count -ne 1){throw 'UNKNOWN_CHECK'};$check=$check[0]
        $cwd=[IO.Path]::GetFullPath((Join-Path $RepoRoot $check.working_directory));$rel=[IO.Path]::GetRelativePath($RepoRoot,$cwd)
        if([IO.Path]::IsPathRooted($rel) -or $rel -eq '..' -or $rel.StartsWith('../') -or $rel.StartsWith('..\')){throw 'CHECK_CWD_OUTSIDE_REPOSITORY'}
        Assert-CFNoLinks $cwd
        $before=Get-CFRunSource $RepoRoot $RunPath $state
        $timeout=if($check.ContainsKey('timeout_seconds')){[int]$check.timeout_seconds}else{120}
        $command='& { '+$check.command+"`n"+' }; if (-not $?) { exit 1 }; if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
        $result=Invoke-CFProcess (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) @('-NoProfile','-NonInteractive','-Command',$command) $cwd @{} $timeout
        $after=Get-CFRunSource $RepoRoot $RunPath $state;$afterContract=Read-ControlFlowContract $state.contract_path
        $status=if($result.timed_out){'TIMEOUT'}elseif($before.digest -cne $after.digest -or $c.digest -cne $afterContract.digest){'STALE'}elseif($result.exit_code -ne 0){'FAIL'}else{'PASS'}
        $capture=@{capture_id=[guid]::NewGuid().ToString('N');check_id=$CheckId;status=$status;exit_code=$result.exit_code;timed_out=$result.timed_out;command=$check.command;working_directory=$check.working_directory;command_digest=(Get-CFJsonHash $check);contract_digest=$c.digest;source_before=$before.digest;source_after=$after.digest;recorded_at=[DateTime]::UtcNow.ToString('o');stdout_ref=(Write-CFImmutable $RunPath 'output' $result.stdout 'stdout.bin');stderr_ref=(Write-CFImmutable $RunPath 'output' $result.stderr 'stderr.bin')}
        $read.evidence.checks=@($read.evidence.checks)+@($capture);$state.revision++;Publish-CFState $RunPath $state $read.evidence
        return $capture
    }finally{$lock.Dispose()}
}
