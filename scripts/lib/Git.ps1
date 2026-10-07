Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Utf8=[Text.UTF8Encoding]::new($false,$true)
function Get-CFHash([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant() }
function Get-CFJsonHash($Value) { Get-CFHash $script:Utf8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 80 -Compress)) }
function Invoke-CFProcess([string]$Executable,[string[]]$Arguments,[string]$Directory,[hashtable]$Environment=@{},[int]$TimeoutSeconds=120) {
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable;$info.WorkingDirectory=$Directory;$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
    foreach($arg in $Arguments){[void]$info.ArgumentList.Add($arg)}
    foreach($key in $Environment.Keys){$info.Environment[$key]=[string]$Environment[$key]}
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info
    $stdout=[IO.MemoryStream]::new();$stderr=[IO.MemoryStream]::new()
    try {
        if(-not $p.Start()){throw 'PROCESS_START_FAILED'}
        $outTask=$p.StandardOutput.BaseStream.CopyToAsync($stdout);$errTask=$p.StandardError.BaseStream.CopyToAsync($stderr)
        $timedOut=-not $p.WaitForExit($TimeoutSeconds*1000)
        if($timedOut){$p.Kill($true);$p.WaitForExit()}
        [void]$outTask.GetAwaiter().GetResult();[void]$errTask.GetAwaiter().GetResult()
        return @{exit_code=$p.ExitCode;stdout=$stdout.ToArray();stderr=$stderr.ToArray();timed_out=$timedOut}
    }finally{$p.Dispose();$stdout.Dispose();$stderr.Dispose()}
}
function Invoke-CFGit([string]$Root,[string[]]$Arguments,[hashtable]$Environment=@{}) {
    $r=Invoke-CFProcess 'git' (@('-C',$Root)+$Arguments) $Root $Environment
    if($r.timed_out -or $r.exit_code -ne 0){throw "GIT_OBSERVATION_FAILED: $($Arguments[0]): $($script:Utf8.GetString($r.stderr))"}
    return ,$r.stdout
}
function Get-CFGitText([string]$Root,[string[]]$Arguments,[hashtable]$Environment=@{}) { $script:Utf8.GetString((Invoke-CFGit $Root $Arguments $Environment)).TrimEnd("`r","`n") }
function Get-CFNul([byte[]]$Bytes) {
    if($Bytes.Length -eq 0){return @()}
    $text=$script:Utf8.GetString($Bytes)
    if(-not $text.EndsWith([string][char]0)){throw 'GIT_TRUNCATED_NUL_OUTPUT'}
    return @($text.Substring(0,$text.Length-1).Split([char]0))
}
function Get-CFMap { return ,[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal) }
function Get-CFSorted($Values) { $a=[string[]]@($Values);[Array]::Sort($a,[StringComparer]::Ordinal);return $a }
function Get-CFIdentity([string]$Root) {
    $rootFull=[IO.Path]::GetFullPath($Root)
    $top=Get-CFGitText $rootFull @('rev-parse','--path-format=absolute','--show-toplevel')
    $dir=Get-CFGitText $rootFull @('rev-parse','--absolute-git-dir')
    $item=Get-Item -LiteralPath $top -Force
    if($item.LinkType){$top=$item.ResolveLinkTarget($true).FullName}
    return @{worktree_realpath=[IO.Path]::GetFullPath($top);git_dir_realpath=[IO.Path]::GetFullPath($dir)}
}
function Get-CFTree([string]$Root,[string]$Commit) {
    $map=Get-CFMap
    foreach($record in (Get-CFNul (Invoke-CFGit $Root @('ls-tree','-rz','--full-tree',$Commit)))) {
        if($record -cnotmatch '^(\d{6}) (blob|commit) ([a-f0-9]+)\t([\s\S]+)$'){throw 'GIT_INVALID_TREE_RECORD'}
        $map.Add($Matches[4],@{mode=$Matches[1];oid=$Matches[3]})
    }
    return ,$map
}
function Assert-CFBaseline([string]$Root,[string]$Baseline) {
    if($Baseline -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$'){throw 'INVALID_BASELINE_COMMIT'}
    $resolved=Get-CFGitText $Root @('rev-parse','--verify',"$Baseline^{commit}")
    if($resolved -cne $Baseline){throw 'INVALID_BASELINE_COMMIT'}
    Invoke-CFGit $Root @('merge-base','--is-ancestor',$Baseline,'HEAD')|Out-Null
    return $resolved
}
function Get-CFEffective([string]$Root,[string]$Path,[string]$Mode='100644') {
    # Git paths are native filenames; the PowerShell provider rewrites Unix backslashes.
    $full=[IO.Path]::Combine($Root,$Path)
    $item=[IO.FileInfo]::new($full)
    if($null -ne $item.LinkTarget){return @{path=$Path;mode='120000';hash=(Get-CFHash $script:Utf8.GetBytes($item.LinkTarget))}}
    if([IO.Directory]::Exists($full)){throw "UNSUPPORTED_SOURCE_TYPE: $Path"}
    if(-not $item.Exists){return @{path=$Path;mode='deleted';hash='deleted'}}
    if(-not $IsWindows){$modeBits=[IO.File]::GetUnixFileMode($full);$Mode=if(([int]$modeBits -band 73) -ne 0){'100755'}else{'100644'}}
    return @{path=$Path;mode=$Mode;hash=(Get-CFHash ([IO.File]::ReadAllBytes($full)))}
}
function Get-ControlFlowGitSnapshot {
    param([Parameter(Mandatory)][string]$RepoRoot,[string]$ArtifactRoot,[string]$SessionId)
    $identity=Get-CFIdentity $RepoRoot;$root=$identity.worktree_realpath
    $index=Get-CFMap;$paths=Get-CFMap
    foreach($record in (Get-CFNul (Invoke-CFGit $root @('ls-files','--stage','-z')))) {
        if($record -cnotmatch '^(\d{6}) ([a-f0-9]+) ([0-3])\t([\s\S]+)$'){throw 'GIT_INVALID_INDEX_RECORD'}
        $path=$Matches[4];$entry=@{path=$path;mode=$Matches[1];oid=$Matches[2];stage=[int]$Matches[3]}
        if($entry.stage -ne 0){throw 'UNMERGED_INDEX'}
        if($entry.mode -eq '160000'){throw 'UNSUPPORTED_SUBMODULE'}
        $index.Add($path,$entry);$paths[$path]=$entry.mode
    }
    # Porcelain deliberately hides assume-unchanged and skip-worktree entries.
    # Refuse these index states rather than mistaking pre-existing user content
    # for clean task-owned files. Never mutate or clear the user's flags.
    foreach($record in (Get-CFNul (Invoke-CFGit $root @('ls-files','-v','-z')))) {
        if($record -cnotmatch '^([A-Za-z?]) ([\s\S]+)$'){throw 'GIT_INVALID_INDEX_FLAG_RECORD'}
        $flag=$Matches[1];$path=$Matches[2]
        if($flag -cmatch '^[a-z]$' -or $flag -ceq 'S'){throw "UNSUPPORTED_HIDDEN_INDEX_FLAG: $path"}
        if(-not $index.ContainsKey($path)){throw 'GIT_INDEX_OBSERVATION_CHANGED'}
    }
    $untracked=@(Get-CFNul (Invoke-CFGit $root @('ls-files','--others','--exclude-standard','-z')))
    foreach($path in $untracked){$paths[$path]='100644'}
    $dirty=Get-CFMap
    $status=@(Get-CFNul (Invoke-CFGit $root @('status','--porcelain=v1','-z','--untracked-files=all')))
    for($i=0;$i -lt $status.Count;$i++) {
        $record=$status[$i];if($record.Length -lt 4 -or $record[2] -ne ' '){throw 'GIT_INVALID_STATUS_RECORD'}
        $dirty[$record.Substring(3)]=$true
        if($record.Substring(0,2) -match '[RC]'){$i++;if($i -ge $status.Count){throw 'GIT_TRUNCATED_RENAME'};$dirty[$status[$i]]=$true}
    }
    $effective=@(foreach($path in (Get-CFSorted $paths.Keys)){if(-not (Test-CFReserved $path $root $ArtifactRoot $SessionId)){Get-CFEffective $root $path $paths[$path]}})
    return @{binding=$identity;head=(Get-CFGitText $root @('rev-parse','HEAD'));index=@(foreach($p in (Get-CFSorted $index.Keys)){$index[$p]});working=$effective;untracked=$untracked;dirty_paths=@(Get-CFSorted $dirty.Keys)}
}
function Test-CFReserved([string]$Path,[string]$RepoRoot,[string]$ArtifactRoot,[string]$SessionId='') {
    if(-not $ArtifactRoot){return $false}
    $rel=[IO.Path]::GetRelativePath($RepoRoot,[IO.Path]::GetFullPath($ArtifactRoot)).Replace('\','/')
    if($rel -cnotmatch '^plans/artifacts/([a-z0-9][a-z0-9-]{0,63})/runs/([a-f0-9]{32})$'){throw 'INVALID_ARTIFACT_ROOT'}
    $task=$Matches[1]
    if($Path.StartsWith($rel+'/',[StringComparison]::Ordinal) -or $Path -ceq "plans/artifacts/$task/plan.meta.json"){return $true}
    if($SessionId){$hash=Get-CFHash $script:Utf8.GetBytes($SessionId);if($Path -ceq "plans/artifacts/.controlflow/active/$hash.json" -or $Path -ceq "plans/artifacts/.controlflow/active/$hash.json.lock"){return $true}}
    return $false
}
function Get-ControlFlowSourceDigest {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Baseline,[string]$ArtifactRoot,[string]$SessionId)
    $base=if($Baseline -is [string]){$Baseline}else{$Baseline.commit}
    Assert-CFBaseline $RepoRoot $base|Out-Null
    $snapshot=Get-ControlFlowGitSnapshot $RepoRoot $ArtifactRoot $SessionId
    $tree=Get-CFTree $RepoRoot $base;$map=Get-CFMap
    foreach($entry in $snapshot.working){$map[$entry.path]=$entry}
    foreach($path in $tree.Keys){if(-not $map.ContainsKey($path)){$map[$path]=Get-CFEffective $RepoRoot $path $tree[$path].mode}}
    $entries=@(foreach($path in (Get-CFSorted $map.Keys)){
        if(Test-CFReserved $path $RepoRoot $ArtifactRoot $SessionId){continue}
        $e=$map[$path]
        # A path absent both now and in the fixed baseline has one canonical
        # identity, regardless of whether HEAD/index once introduced it.
        if($e.mode -ceq 'deleted' -and -not $tree.ContainsKey($path)){continue}
        [ordered]@{path=$e.path;mode=$e.mode;hash=$e.hash}
    })
    return @{digest=(Get-CFJsonHash $entries);entries=$entries}
}
function Test-ControlFlowScope {
    param([string]$Path,[string[]]$Scope)
    foreach($glob in $Scope){$regex=[regex]::Escape($glob).Replace('\*\*','\u0001').Replace('\*','[^/]*').Replace('\?','[^/]').Replace('\u0001','.*');if([regex]::IsMatch($Path,'^'+$regex+'$',[Text.RegularExpressions.RegexOptions]::CultureInvariant)){return $true}}
    return $false
}



function Get-ControlFlowChangedPaths {
    param([Parameter(Mandatory)][string]$RepoRoot,[string]$Baseline='HEAD')
    if($Baseline.StartsWith('-')){throw 'INVALID_BASELINE_COMMIT'}
    $base=Get-CFGitText $RepoRoot @('rev-parse','--verify',"$Baseline^{commit}");Assert-CFBaseline $RepoRoot $base|Out-Null
    $snapshot=Get-ControlFlowGitSnapshot $RepoRoot;$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($path in (Get-CFNul (Invoke-CFGit $RepoRoot @('diff','--name-only','--no-renames','-z',$base,$snapshot.head)))){[void]$paths.Add($path)}
    foreach($path in $snapshot.dirty_paths){[void]$paths.Add($path)}
    return @{base_commit=$base;head_commit=$snapshot.head;paths=@(Get-CFSorted $paths)}
}
