# Interrupt notification is a native event mailbox, not certified run evidence.
# A writer already holding writer.lock cannot prevent or erase this notification.
function Read-CFRunHeader([string]$RepoRoot,[string]$RunPath,[string]$SessionId,$Identity=$null) {
    if($null -eq $Identity){$Identity=Get-CFIdentity $RepoRoot}
    $RepoRoot=$Identity.worktree_realpath;$RunPath=[IO.Path]::GetFullPath($RunPath)
    $relative=[IO.Path]::GetRelativePath($RepoRoot,$RunPath).Replace('\','/')
    if($relative -cnotmatch '^plans/artifacts/([a-z0-9][a-z0-9-]{0,63})/runs/([a-f0-9]{32})$'){throw 'INVALID_RUN_PATH'}
    $task=$Matches[1];$run=$Matches[2]
    $statePath=Join-Path $RunPath 'state.json';Assert-CFNoLinks $statePath
    $state=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($statePath,$script:Utf8)) -AsHashtable -Depth 80
    if($state.schema_version -cne '3.0.0' -or $state.task_id -cne $task -or $state.run_id -cne $run -or $state.revision -lt 0){throw 'INVALID_RUN_STATE'}
    foreach($key in @('worktree_realpath','git_dir_realpath')){if($state.binding[$key] -cne $Identity[$key]){throw 'WORKTREE_BINDING_MISMATCH'}}
    if($SessionId -and $state.binding.session_id -cne $SessionId){throw 'SESSION_BINDING_MISMATCH'}
    $expected=Join-Path $RepoRoot "plans/artifacts/$task/plan.meta.json"
    if($state.contract_path -cne $expected){throw 'CONTRACT_PATH_BINDING_MISMATCH'}
    if($state.ContainsKey('acknowledged_interrupt_id') -and $null -ne $state.acknowledged_interrupt_id -and $state.acknowledged_interrupt_id -cnotmatch '^[a-f0-9]{32}$'){throw 'INVALID_INTERRUPT_ACKNOWLEDGMENT'}
    return @{state=$state;run_path=$RunPath}
}
function Resolve-CFActiveHeader([string]$RepoRoot,[string]$SessionId) {
    if([string]::IsNullOrWhiteSpace($SessionId)){throw 'TRUSTED_SESSION_REQUIRED'}
    $cursor=[IO.Path]::GetFullPath($RepoRoot);$found=$false
    while($cursor){if(Test-Path -LiteralPath (Get-CFActivePath $cursor $SessionId)){$found=$true;break};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
    if(-not $found){return $null}
    $identity=Get-CFIdentity $RepoRoot;$p=Get-CFActivePath $identity.worktree_realpath $SessionId;Assert-CFNoLinks $p
    if(-not [IO.File]::Exists($p)){if(Test-Path -LiteralPath $p){throw 'INVALID_ACTIVE_POINTER'};return $null}
    $pointer=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($p,$script:Utf8)) -AsHashtable -Depth 80
    if($pointer.schema_version -cne '3.0.0' -or $pointer.binding.session_id -cne $SessionId){throw 'INVALID_ACTIVE_POINTER'}
    $header=Read-CFRunHeader $identity.worktree_realpath $pointer.run_path $SessionId $identity
    if($pointer.run_id -cne $header.state.run_id -or $pointer.task_id -cne $header.state.task_id){throw 'ACTIVE_POINTER_BINDING_MISMATCH'}
    foreach($key in @('worktree_realpath','git_dir_realpath','session_id')){if($pointer.binding[$key] -cne $header.state.binding[$key]){throw 'ACTIVE_POINTER_BINDING_MISMATCH'}}
    return $header
}
function Read-CFPendingInterrupt([string]$RunPath,$State) {
    $path=Join-Path $RunPath 'pending-interrupt.json';Assert-CFNoLinks $path
    if(-not [IO.File]::Exists($path)){if(Test-Path -LiteralPath $path){throw 'INVALID_INTERRUPT_NOTIFICATION'};return $null}
    $text=[IO.File]::ReadAllText($path,$script:Utf8)
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
    # Never silently repair a corrupt notification or consult potentially huge
    # evidence outputs on the native three-second interrupt path.
    Read-CFPendingInterrupt $runPath $state|Out-Null
    $notice=[ordered]@{schema_version='3.0.0';interrupt_id=[guid]::NewGuid().ToString('N');task_id=$state.task_id;run_id=$state.run_id;binding=$state.binding;reason='INTERRUPT';native_evidence=@{event='Interrupt';turn_id=$(if($TurnId){$TurnId}else{$null});received_at=[DateTime]::UtcNow.ToString('o')}}
    $text=ConvertTo-Json -InputObject $notice -Depth 20 -Compress
    if(-not (Test-Json -Json $text -SchemaFile (Join-Path $script:CoreModuleRoot '../schemas/pending-interrupt.schema.json') -ErrorAction Stop)){throw 'INVALID_INTERRUPT_NOTIFICATION'}
    $target=Join-Path $runPath 'pending-interrupt.json';Assert-CFNoLinks $target
    $tmp=Join-Path $runPath ([guid]::NewGuid().ToString('N')+'.interrupt.tmp')
    Write-CFFlushed $tmp $script:Utf8.GetBytes($text)
    try{[IO.File]::Move($tmp,$target,$true)}finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
    return @{status='INTERRUPTED';run_path=$runPath;run_id=$state.run_id;task_id=$state.task_id;interrupt_id=$notice.interrupt_id;revision=$state.revision}
}
