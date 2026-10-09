function Get-CFStorageContext([string]$RepoRoot,[string]$SessionId='', $Identity=$null,[switch]$LookupOnly) {
    if($null -eq $Identity){$Identity=Get-CFIdentity $RepoRoot}
    $configured=[Environment]::GetEnvironmentVariable('CONTROLFLOW_STATE_ROOT')
    if(-not [string]::IsNullOrWhiteSpace($configured)){$root=$configured}
    else {
        $codexHome=[Environment]::GetEnvironmentVariable('CODEX_HOME')
        if([string]::IsNullOrWhiteSpace($codexHome)){$codexHome=[IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'),'.codex')}
        if(-not [IO.Path]::IsPathFullyQualified($codexHome)){throw 'INVALID_CODEX_HOME: absolute path required'}
        $root=[IO.Path]::Combine($codexHome,'controlflow')
    }
    if(-not [IO.Path]::IsPathFullyQualified($root)){throw 'INVALID_STATE_ROOT: absolute path required'}
    $root=[IO.Path]::GetFullPath($root)
    if(-not $LookupOnly) {
        Assert-CFNoLinks $root
        $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
        $commonDir=[IO.Path]::GetFullPath((Get-CFGitText $Identity.worktree_realpath @('rev-parse','--path-format=absolute','--git-common-dir')))
        foreach($boundary in @($Identity.worktree_realpath,$Identity.git_dir_realpath,$commonDir)) {
            $relative=[IO.Path]::GetRelativePath($boundary,$root)
            if($relative -eq '.' -or (-not [IO.Path]::IsPathRooted($relative) -and $relative -ne '..' -and -not $relative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar,$comparison))){throw 'STATE_ROOT_INSIDE_PROJECT'}
        }
        # A configured root inside another checkout would clutter that project too.
        $cursor=$root
        while($cursor) {
            $marker=[IO.Path]::Combine($cursor,'.git')
            if([IO.Directory]::Exists($marker) -or [IO.File]::Exists($marker)){throw 'STATE_ROOT_INSIDE_PROJECT'}
            $next=[IO.Path]::GetDirectoryName($cursor);if($next -eq $cursor){break};$cursor=$next
        }
    }
    $key=Get-CFJsonHash ([ordered]@{worktree=$Identity.worktree_realpath;git_dir=$Identity.git_dir_realpath})
    $worktree=[IO.Path]::Combine($root,'worktrees',$key)
    $sessionKey=if($SessionId){'native-'+(Get-CFHash $script:Utf8.GetBytes($SessionId))}else{'manual'}
    $session=[IO.Path]::Combine($worktree,'sessions',$sessionKey)
    return @{root=$root;worktree_path=$worktree;session_path=$session;session_key=$sessionKey;active_path=[IO.Path]::Combine($session,'active.json');binding=$Identity}
}
function Get-ControlFlowStoragePaths {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$TaskId,[string]$SessionId,[switch]$Create)
    if($TaskId -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$'){throw 'INVALID_TASK_ID'}
    $paths=Get-CFStorageContext $RepoRoot $SessionId
    $paths.task_path=[IO.Path]::Combine($paths.session_path,'tasks',$TaskId)
    $paths.contract_path=[IO.Path]::Combine($paths.task_path,'plan.meta.json')
    if($Create) {
        $probe=[IO.Path]::Combine($paths.task_path,([guid]::NewGuid().ToString('N')+'.write-probe'))
        try {
            Assert-CFNoLinks $paths.task_path
            [IO.Directory]::CreateDirectory($paths.task_path)|Out-Null
            Write-CFFlushed $probe ([byte[]]@())
        } catch {throw "STATE_STORAGE_UNAVAILABLE: $($_.Exception.Message)"}
        finally {if([IO.File]::Exists($probe)){[IO.File]::Delete($probe)}}
    }
    return $paths
}
function Get-CFRunLocation([string]$RepoRoot,[string]$RunPath,$Identity=$null) {
    if(-not [IO.Path]::IsPathFullyQualified($RunPath)){throw 'INVALID_RUN_PATH'}
    $context=Get-CFStorageContext $RepoRoot -Identity $Identity
    $full=[IO.Path]::GetFullPath($RunPath)
    $relative=[IO.Path]::GetRelativePath($context.worktree_path,$full).Replace('\','/')
    if($relative -cnotmatch '^sessions/(manual|native-[a-f0-9]{64})/tasks/([a-z0-9][a-z0-9-]{0,63})/runs/([a-f0-9]{32})$'){throw 'INVALID_RUN_PATH'}
    return @{run_path=$full;session_key=$Matches[1];task_id=$Matches[2];run_id=$Matches[3];context=$context}
}
