# Interrupt notification is a native event mailbox, not certified run evidence.
# A writer already holding writer.lock cannot prevent or erase this notification.
function Open-CFMutableRead([string]$Path) {
    # Publishers replace complete generations. Readers may retain the old file
    # while rename/delete proceeds, but never admit an in-place writer.
    return [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
}
function Read-CFMutableText([string]$Path) {
    $stream=Open-CFMutableRead $Path;$reader=$null
    try {
        # Decode strictly as UTF8; accept its optional BOM without switching to
        # a permissive decoder or silently accepting a different encoding.
        $reader=[IO.StreamReader]::new($stream,$script:Utf8,$false,4096,$true)
        $text=$reader.ReadToEnd()
        if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){return $text.Substring(1)}
        return $text
    }finally{if($null -ne $reader){$reader.Dispose()};$stream.Dispose()}
}
function Move-CFMutableFile([string]$Source,[string]$Destination) {
    if([IO.Directory]::Exists($Source) -or [IO.Directory]::Exists($Destination)){throw [IO.IOException]::new('MUTABLE_FILE_PATH_IS_DIRECTORY')}
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true) {
        try {
            # Windows Move(overwrite) rejects an open destination even when its
            # readers share deletion. Replace atomically exchanges those files.
            if($IsWindows -and [IO.File]::Exists($Destination)){[IO.File]::Replace($Source,$Destination,[NullString]::Value)}
            else{[IO.File]::Move($Source,$Destination,$true)}
            return
        }
        catch {
            $failure=$_.Exception.GetBaseException();$code=$failure.HResult -band 0xFFFF
            # Only Windows sharing/lock violations and access denied can be
            # transient rename conflicts. Bad paths and all other errors escape.
            $retry=$IsWindows -and ($failure -is [IO.IOException] -or $failure -is [UnauthorizedAccessException]) -and $code -in @(5,32,33)
            $remaining=200-$watch.Elapsed.TotalMilliseconds
            if(-not $retry -or $remaining -le 0){throw}
            Start-Sleep -Milliseconds ([int][Math]::Min(20,[Math]::Ceiling($remaining)))
        }
    }
}
function Read-CFRunHeader([string]$RepoRoot,[string]$RunPath,[string]$SessionId,$Identity=$null) {
    if(-not [IO.Path]::IsPathFullyQualified($RunPath)){throw 'INVALID_RUN_PATH'}
    if($null -eq $Identity){$Identity=Get-CFIdentity $RepoRoot}
    $RepoRoot=$Identity.worktree_realpath;$RunPath=[IO.Path]::GetFullPath($RunPath)
    $location=Get-CFRunLocation $RepoRoot $RunPath $Identity
    $task=$location.task_id;$run=$location.run_id
    $statePath=[IO.Path]::Combine($RunPath,'state.json');Assert-CFNoLinks $statePath
    $state=ConvertFrom-Json -InputObject (Read-CFMutableText $statePath) -AsHashtable -Depth 80
    if($state.schema_version -cnotin @('3.0.0','4.0.0') -or $state.task_id -cne $task -or $state.run_id -cne $run -or $state.revision -lt 0){throw 'INVALID_RUN_STATE'}
    foreach($key in @('worktree_realpath','git_dir_realpath')){if($state.binding[$key] -cne $Identity[$key]){throw 'WORKTREE_BINDING_MISMATCH'}}
    if($SessionId -and $state.binding.session_id -cne $SessionId){throw 'SESSION_BINDING_MISMATCH'}
    $paths=Get-ControlFlowStoragePaths $RepoRoot $task $state.binding.session_id
    if($location.session_key -cne $paths.session_key){throw 'SESSION_BINDING_MISMATCH'}
    if($state.contract_path -cne $paths.contract_path){throw 'CONTRACT_PATH_BINDING_MISMATCH'}
    Assert-CFNoLinks $paths.contract_path
    if($state.ContainsKey('acknowledged_interrupt_id') -and $null -ne $state.acknowledged_interrupt_id -and $state.acknowledged_interrupt_id -cnotmatch '^[a-f0-9]{32}$'){throw 'INVALID_INTERRUPT_ACKNOWLEDGMENT'}
    return @{state=$state;run_path=$RunPath}
}
function Resolve-CFActiveHeader([string]$RepoRoot,[string]$SessionId) {
    if([string]::IsNullOrWhiteSpace($SessionId)){throw 'TRUSTED_SESSION_REQUIRED'}
    $cursor=Get-CFFullPath $RepoRoot;$found=$false
    while($cursor){$marker=Join-Path $cursor '.git';if([IO.File]::Exists($marker) -or [IO.Directory]::Exists($marker)){$found=$true;break};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
    if(-not $found){return $null}
    $identity=Get-CFIdentity $RepoRoot;$context=Get-CFStorageContext $identity.worktree_realpath $SessionId -Identity $identity -LookupOnly;$p=$context.active_path
    # Exists suppresses access errors, which could hide a managed session.
    try {$attributes=[IO.File]::GetAttributes($p)}
    catch [IO.FileNotFoundException] {return $null}
    catch [IO.DirectoryNotFoundException] {return $null}
    if($attributes -band [IO.FileAttributes]::Directory){throw 'INVALID_ACTIVE_POINTER'}
    Get-CFStorageContext $identity.worktree_realpath $SessionId -Identity $identity|Out-Null;Assert-CFNoLinks $p
    $pointer=ConvertFrom-Json -InputObject (Read-CFMutableText $p) -AsHashtable -Depth 80
    if($pointer.schema_version -cnotin @('3.0.0','4.0.0') -or $pointer.binding.session_id -cne $SessionId){throw 'INVALID_ACTIVE_POINTER'}
    $header=Read-CFRunHeader $identity.worktree_realpath $pointer.run_path $SessionId $identity
    if($pointer.schema_version -cne $header.state.schema_version){throw 'RUNTIME_VERSION_MISMATCH'}
    if($pointer.run_id -cne $header.state.run_id -or $pointer.task_id -cne $header.state.task_id){throw 'ACTIVE_POINTER_BINDING_MISMATCH'}
    foreach($key in @('worktree_realpath','git_dir_realpath','session_id')){if($pointer.binding[$key] -cne $header.state.binding[$key]){throw 'ACTIVE_POINTER_BINDING_MISMATCH'}}
    return $header
}
function Read-CFPendingInterrupt([string]$RunPath,$State) {
    # A publisher may have observed ACTIVE just before terminal publication.
    # Its late mailbox generation cannot reopen a closed V4 lifecycle.
    if(Test-CFV4TerminalState $State){return $null}
    $path=[IO.Path]::Combine($RunPath,'pending-interrupt.json');Assert-CFNoLinks $path
    if(-not [IO.File]::Exists($path)){if([IO.Directory]::Exists($path)){throw 'INVALID_INTERRUPT_NOTIFICATION'};return $null}
    $text=Read-CFMutableText $path
    $schema=Join-Path $script:CoreModuleRoot '../schemas/pending-interrupt.schema.json'
    if(-not (Test-Json -Json $text -SchemaFile $schema -ErrorAction Stop)){throw 'INVALID_INTERRUPT_NOTIFICATION'}
    $notice=ConvertFrom-Json -InputObject $text -AsHashtable -Depth 20
    if($notice.task_id -cne $State.task_id -or $notice.run_id -cne $State.run_id){throw 'INTERRUPT_BINDING_MISMATCH'}
    foreach($key in @('worktree_realpath','git_dir_realpath','session_id')){if($notice.binding[$key] -cne $State.binding[$key]){throw 'INTERRUPT_BINDING_MISMATCH'}}
    return $notice
}
function Request-ControlFlowInterrupt {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$SessionId,[string]$TurnId)
    $header=Resolve-CFActiveHeader $RepoRoot $SessionId
    if($null -eq $header){return $null}
    $state=$header.state;$runPath=$header.run_path
    if(Test-CFV4TerminalState $state){return $null}
    # Never silently repair a corrupt notification or consult potentially huge
    # evidence outputs on the native three-second interrupt path.
    $existing=Read-CFPendingInterrupt $runPath $state
    $notice=[ordered]@{schema_version='3.0.0';interrupt_id=[guid]::NewGuid().ToString('N');task_id=$state.task_id;run_id=$state.run_id;binding=$state.binding;reason='INTERRUPT';native_evidence=@{event='Interrupt';turn_id=$(if($TurnId){$TurnId}else{$null});received_at=[DateTime]::UtcNow.ToString('o')}}
    if($state.schema_version -ceq '4.0.0'){
        $unacknowledged=$null -ne $existing -and $existing.interrupt_id -cne $state.acknowledged_interrupt_id
        $notice.observed_source_digest=if($state.stop_source_digest){$state.stop_source_digest}elseif($unacknowledged){$existing.observed_source_digest}else{$state.last_observed_source_digest}
    }
    $text=ConvertTo-Json -InputObject $notice -Depth 20 -Compress
    if(-not (Test-Json -Json $text -SchemaFile (Join-Path $script:CoreModuleRoot '../schemas/pending-interrupt.schema.json') -ErrorAction Stop)){throw 'INVALID_INTERRUPT_NOTIFICATION'}
    $target=[IO.Path]::Combine($runPath,'pending-interrupt.json');Assert-CFNoLinks $target
    $tmp=[IO.Path]::Combine($runPath,([guid]::NewGuid().ToString('N')+'.interrupt.tmp'))
    Write-CFFlushed $tmp $script:Utf8.GetBytes($text)
    try{Move-CFMutableFile $tmp $target}finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
    return @{status='INTERRUPTED';run_path=$runPath;run_id=$state.run_id;task_id=$state.task_id;interrupt_id=$notice.interrupt_id;revision=$state.revision}
}
