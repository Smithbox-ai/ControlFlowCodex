Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Utf8=[Text.UTF8Encoding]::new($false,$true)
function Get-CFHash([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant() }
function Get-CFJsonHash($Value) { Get-CFHash $script:Utf8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 80 -Compress)) }
function Resolve-CFGroupSignalResult([int]$Result,[int]$ErrorNumber) {
    if($Result -eq 0){return $true}
    # POSIX ESRCH alone establishes that the target process group does not exist.
    if($Result -eq -1 -and $ErrorNumber -eq 3){return $false}
    throw "PROCESS_GROUP_SIGNAL_UNVERIFIABLE: errno=$ErrorNumber"
}
function Invoke-CFGroupSignal([int]$GroupId,[int]$Signal) {
    if($GroupId -le 0){throw 'PROCESS_GROUP_ID_INVALID'}
    if(-not ('CFUnixGroupSignal' -as [type])){
        if($IsWindows){throw 'PROCESS_OWNERSHIP_UNAVAILABLE'}
        $library=if($IsMacOS){'/usr/lib/libSystem.B.dylib'}elseif($IsLinux){'libc'}else{throw 'PROCESS_OWNERSHIP_UNAVAILABLE'}
        Add-Type -TypeDefinition "using System.Runtime.InteropServices; public static class CFUnixGroupSignal { [DllImport(`"$library`",SetLastError=true)] public static extern int kill(int pid,int signal); }"
    }
    $result=[CFUnixGroupSignal]::kill(-$GroupId,$Signal)
    $errorNumber=if($result -eq -1){[Runtime.InteropServices.Marshal]::GetLastWin32Error()}else{0}
    return Resolve-CFGroupSignalResult $result $errorNumber
}
function Test-CFGroupHasOtherProcess([int]$GroupId,[int]$RootId,[int]$MainId,[string]$Directory,[double]$RemainingSeconds) {
    # Observe the whole process group, not only the processes holding output.
    # Any incomplete or unparsable observation must reject the check.
    if($RemainingSeconds -le 0){throw 'PROCESS_CLEANUP_UNVERIFIABLE'}
    $snapshot=Invoke-CFProcess '/bin/ps' @('-axo','pid=,pgid=,stat=') $Directory @{} $RemainingSeconds $false
    if($snapshot.timed_out -or $snapshot.exit_code -ne 0){throw 'PROCESS_CLEANUP_UNVERIFIABLE'}
    $lines=$script:Utf8.GetString($snapshot.stdout) -split '\r?\n'
    foreach($line in $lines){
        if([string]::IsNullOrWhiteSpace($line)){continue}
        if($line -notmatch '^\s*(\d+)\s+(\d+)\s+(\S+)\s*$'){throw 'PROCESS_CLEANUP_UNVERIFIABLE'}
        $id=[int]$Matches[1];$group=[int]$Matches[2];$state=$Matches[3]
        if($group -eq $GroupId -and $id -ne $RootId -and $id -ne $MainId -and $state -cnotmatch '^Z'){return $true}
    }
    return $false
}
function Invoke-CFProcess([string]$Executable,[string[]]$Arguments,[string]$Directory,[hashtable]$Environment=@{},[double]$TimeoutSeconds=120,[bool]$OwnDescendants=$false) {
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Executable;$info.WorkingDirectory=$Directory;$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
    $job=$null;$group=$false;$payload=$null;$signalPipe=$null;$signalTask=$null;$signalReader=$null;$signalRead=$null;$signaled=$false
    if($OwnDescendants -and $IsWindows){
        if(-not ('CFOwnedJob' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
public sealed class CFOwnedJob : IDisposable {
 [StructLayout(LayoutKind.Sequential)] struct Basic { public long a,b; public uint flags; public UIntPtr min,max; public uint active; public UIntPtr affinity; public uint priority,scheduling; }
 [StructLayout(LayoutKind.Sequential)] struct IO { public ulong a,b,c,d,e,f; }
 [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic basic; public IO io; public UIntPtr processMemory,jobMemory,peakProcess,peakJob; }
 [StructLayout(LayoutKind.Sequential)] struct Accounting { public long a,b,c,d; public uint faults,total,active,terminated; }
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security,string name);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,ref Extended info,uint size);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint exit);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int kind,out Accounting info,uint size,IntPtr length);
 [DllImport("kernel32.dll",SetLastError=true,EntryPoint="QueryInformationJobObject")] static extern bool QueryProcessList(IntPtr job,int kind,IntPtr info,uint size,IntPtr length);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 IntPtr handle;
 public CFOwnedJob() { handle=CreateJobObject(IntPtr.Zero,null); if(handle==IntPtr.Zero) throw new Win32Exception(); var info=new Extended();info.basic.flags=0x2000; if(!SetInformationJobObject(handle,9,ref info,(uint)Marshal.SizeOf<Extended>())) { Dispose();throw new Win32Exception(); } }
 public void Attach(IntPtr process) { if(!AssignProcessToJobObject(handle,process)) throw new Win32Exception(); }
 public void Kill() { if(!TerminateJobObject(handle,1)) throw new Win32Exception(); }
 public bool IsEmpty() { Accounting info; if(!QueryInformationJobObject(handle,1,out info,(uint)Marshal.SizeOf<Accounting>(),IntPtr.Zero)) throw new Win32Exception();return info.active==0; }
 public bool HasLiveOtherProcess(int root,int main) {
  const int size=65536; IntPtr data=Marshal.AllocHGlobal(size);
  try {
   if(!QueryProcessList(handle,3,data,size,IntPtr.Zero)) throw new Win32Exception();
   int count=Marshal.ReadInt32(data,4);if(count<0 || count>(size-8)/IntPtr.Size) throw new InvalidOperationException();
   for(int i=0;i<count;i++) {
    int id=checked((int)Marshal.ReadIntPtr(data,8+i*IntPtr.Size).ToInt64());if(id==root || id==main) continue;
    try { using(var process=Process.GetProcessById(id)) {
      if(process.HasExited) continue;
      // Windows can keep its console host in the job briefly after the
      // command has exited; it is not a check process. Verify the full OS
      // executable path rather than trusting a process name alone.
      if(process.ProcessName.Equals("conhost",StringComparison.OrdinalIgnoreCase)) {
       string systemHost=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"conhost.exe");
       try { if(String.Equals(process.MainModule.FileName,systemHost,StringComparison.OrdinalIgnoreCase)) continue; }
       catch(InvalidOperationException) { if(process.HasExited) continue; throw; }
      }
      return true;
    } }
    catch(ArgumentException) { /* It exited after the job snapshot. */ }
   }
   return false;
  } finally {Marshal.FreeHGlobal(data);}
 }
 public void Dispose() { if(handle!=IntPtr.Zero) {CloseHandle(handle);handle=IntPtr.Zero;} }
}
'@
        }
        $job=[CFOwnedJob]::new();$info.FileName=Join-Path $PSHOME 'pwsh.exe';$info.RedirectStandardInput=$true
        # The wrapper waits for its payload until after it has joined the job.
        # Its child inherits the job and output handles, closing the launch race.
        $wrapper=@'
$data=[Console]::In.ReadLine() | ConvertFrom-Json -AsHashtable
if (-not $data) { exit 2 }
$start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$data.executable;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
foreach($a in $data.arguments){[void]$start.ArgumentList.Add([string]$a)}
$signal=[IO.Pipes.NamedPipeClientStream]::new('.',$data.signal_pipe,[IO.Pipes.PipeDirection]::Out);$signal.Connect(5000)
$writer=[IO.StreamWriter]::new($signal);$writer.AutoFlush=$true
$child=[Diagnostics.Process]::Start($start)
$out=$child.StandardOutput.BaseStream.CopyToAsync([Console]::OpenStandardOutput());$err=$child.StandardError.BaseStream.CopyToAsync([Console]::OpenStandardError())
$child.WaitForExit();$writer.WriteLine([string]$child.Id);$writer.Dispose();[void]$out.GetAwaiter().GetResult();[void]$err.GetAwaiter().GetResult();exit $child.ExitCode
'@
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapper))
        foreach($arg in @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded)){[void]$info.ArgumentList.Add($arg)}
        $pipeName='cf-check-'+[guid]::NewGuid().ToString('N')
        $signalPipe=[IO.Pipes.NamedPipeServerStream]::new($pipeName,[IO.Pipes.PipeDirection]::In,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous)
        $signalTask=$signalPipe.WaitForConnectionAsync()
        $payload=ConvertTo-Json -InputObject @{executable=$Executable;arguments=@($Arguments);signal_pipe=$pipeName} -Compress -Depth 5
    }elseif($OwnDescendants -and ($IsMacOS -or $IsLinux)){
        # Use PowerShell native interop when no standard setsid utility exists.
        $info.FileName=Join-Path $PSHOME 'pwsh';$info.RedirectStandardInput=$true
        $wrapper=@'
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class CFSession { [DllImport("libc",SetLastError=true)] public static extern int setsid(); }'
if ([CFSession]::setsid() -lt 0) { throw 'PROCESS_OWNERSHIP_FAILED' }
$data=[Console]::In.ReadLine() | ConvertFrom-Json -AsHashtable
if (-not $data) { exit 2 }
$start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$data.executable;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
foreach($a in $data.arguments){[void]$start.ArgumentList.Add([string]$a)}
$signal=[IO.Pipes.NamedPipeClientStream]::new('.',$data.signal_pipe,[IO.Pipes.PipeDirection]::Out);$signal.Connect(5000)
$writer=[IO.StreamWriter]::new($signal);$writer.AutoFlush=$true
$child=[Diagnostics.Process]::Start($start)
$out=$child.StandardOutput.BaseStream.CopyToAsync([Console]::OpenStandardOutput());$err=$child.StandardError.BaseStream.CopyToAsync([Console]::OpenStandardError())
$child.WaitForExit();$writer.WriteLine([string]$child.Id);$writer.Dispose();[void]$out.GetAwaiter().GetResult();[void]$err.GetAwaiter().GetResult();exit $child.ExitCode
'@
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapper))
        foreach($arg in @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded)){[void]$info.ArgumentList.Add($arg)}
        $pipeName='cf-check-'+[guid]::NewGuid().ToString('N')
        $signalPipe=[IO.Pipes.NamedPipeServerStream]::new($pipeName,[IO.Pipes.PipeDirection]::In,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous)
        $signalTask=$signalPipe.WaitForConnectionAsync()
        $payload=ConvertTo-Json -InputObject @{executable=$Executable;arguments=@($Arguments);signal_pipe=$pipeName} -Compress -Depth 5;$group=$true
    }elseif($OwnDescendants){throw 'PROCESS_OWNERSHIP_UNAVAILABLE'}
    else{foreach($arg in $Arguments){[void]$info.ArgumentList.Add($arg)}}
    foreach($key in $Environment.Keys){$info.Environment[$key]=[string]$Environment[$key]}
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info
    $stdout=[IO.MemoryStream]::new();$stderr=[IO.MemoryStream]::new()
    $callerExitCode=Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $savedExitCode=if($null -ne $callerExitCode){$callerExitCode.Value}else{$null}
    $started=$false;$cleanupAttempted=$false
    try {
        $clock=[Diagnostics.Stopwatch]::StartNew()
        if(-not $p.Start()){throw 'PROCESS_START_FAILED'}
        $started=$true
        if($job){try{$job.Attach($p.Handle)}catch{try{$p.Kill($true)}catch{};throw 'PROCESS_OWNERSHIP_FAILED'}}
        # The wrapper's input belongs to the same deadline as execution and
        # stream collection: a stalled reader must not block WriteLine.
        $inputTask=if($null -ne $payload){$p.StandardInput.WriteLineAsync($payload)}else{$null}
        $outTask=$p.StandardOutput.BaseStream.CopyToAsync($stdout);$errTask=$p.StandardError.BaseStream.CopyToAsync($stderr)
        $timedOut=$false;$processIncomplete=$false;$mainProcessId=0
        while(-not $p.HasExited -or -not $outTask.IsCompleted -or -not $errTask.IsCompleted -or ($null -ne $inputTask -and -not $inputTask.IsCompleted) -or ($signalPipe -and -not $signaled)){
            if($signalTask -and $signalTask.IsCompleted -and -not $signalReader){
                if($signalTask.IsFaulted){throw 'PROCESS_SIGNAL_UNVERIFIABLE'}
                $signalReader=[IO.StreamReader]::new($signalPipe);$signalRead=$signalReader.ReadLineAsync()
            }
            if($signalRead -and $signalRead.IsCompleted -and -not $signaled){
                if(-not [int]::TryParse($signalRead.GetAwaiter().GetResult(),[ref]$mainProcessId) -or $mainProcessId -le 0){throw 'PROCESS_SIGNAL_UNVERIFIABLE'}
                $signaled=$true
                try{if($job){$processIncomplete=$job.HasLiveOtherProcess($p.Id,$mainProcessId)}else{$processIncomplete=Test-CFGroupHasOtherProcess $p.Id $p.Id $mainProcessId $Directory ($TimeoutSeconds-$clock.Elapsed.TotalSeconds)}}catch{throw 'PROCESS_CLEANUP_UNVERIFIABLE'}
                if($processIncomplete){break}
            }
            if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;break}
            [Threading.Thread]::Sleep(20)
        }
        $cleanupOk=$true
        if($OwnDescendants){
            # Parent exit and closed output do not prove that a silent child
            # finished its assertions. Reject that outcome before cleanup.
            if(-not $timedOut){
                if($job -and -not $processIncomplete){try{$processIncomplete=$job.HasLiveOtherProcess($p.Id,$mainProcessId)}catch{throw 'PROCESS_CLEANUP_UNVERIFIABLE'}}
                elseif($group -and -not $processIncomplete){try{$processIncomplete=Test-CFGroupHasOtherProcess $p.Id $p.Id $mainProcessId $Directory ($TimeoutSeconds-$clock.Elapsed.TotalSeconds)}catch{throw 'PROCESS_CLEANUP_UNVERIFIABLE'}}
            }
            # Cleanup is limited to the job/group created for this check.
            $cleanupAttempted=$true
            try{if($job){$job.Kill()}elseif($group){Invoke-CFGroupSignal $p.Id 9 | Out-Null}}catch{$cleanupOk=$false}
            if(-not $p.HasExited){try{$p.Kill($true)}catch{}}
        }elseif($timedOut -and -not $p.HasExited){try{$p.Kill($true)}catch{}}
        $drain=[Diagnostics.Stopwatch]::StartNew()
        while($drain.ElapsedMilliseconds -lt 750 -and (-not $p.HasExited -or -not $outTask.IsCompleted -or -not $errTask.IsCompleted)){[Threading.Thread]::Sleep(10)}
        if(-not $p.HasExited -or -not $outTask.IsCompleted -or -not $errTask.IsCompleted -or ($null -ne $inputTask -and -not $inputTask.IsCompleted)){$timedOut=$true}
        if($job){
            $empty=$false
            while($drain.ElapsedMilliseconds -lt 750){
                try{if($job.IsEmpty()){$empty=$true;break}}catch{$cleanupOk=$false;break}
                [Threading.Thread]::Sleep(10)
            }
            if(-not $empty){$cleanupOk=$false}
        }
        if($group){
            $empty=$false
            while($drain.ElapsedMilliseconds -lt 750){
                try{if(-not (Invoke-CFGroupSignal $p.Id 0)){$empty=$true;break}}catch{$cleanupOk=$false;break}
                [Threading.Thread]::Sleep(10)
            }
            if(-not $empty){$cleanupOk=$false}
        }
        if(-not $cleanupOk){throw 'PROCESS_CLEANUP_UNVERIFIABLE'}
        if($null -ne $inputTask -and $inputTask.IsFaulted -and -not $timedOut){throw 'PROCESS_INPUT_DELIVERY_FAILED'}
        if($outTask.IsFaulted -or $errTask.IsFaulted){throw 'PROCESS_OUTPUT_COLLECTION_FAILED'}
        return @{exit_code=if($p.HasExited){$p.ExitCode}else{-1};stdout=$stdout.ToArray();stderr=$stderr.ToArray();timed_out=$timedOut;process_incomplete=$processIncomplete}
    }finally{
        if($group -and $started -and -not $cleanupAttempted){
            $cleanupAttempted=$true;$emergencyOk=$false
            try{
                Invoke-CFGroupSignal $p.Id 9 | Out-Null
                if(-not $p.HasExited){try{$p.Kill($true)}catch{}}
                $emergencyClock=[Diagnostics.Stopwatch]::StartNew()
                while($emergencyClock.ElapsedMilliseconds -lt 750){
                    if(-not (Invoke-CFGroupSignal $p.Id 0)){$emergencyOk=$true;break}
                    [Threading.Thread]::Sleep(10)
                }
            }catch{if(-not $p.HasExited){try{$p.Kill($true)}catch{}}}
            if(-not $emergencyOk){Write-Warning 'PROCESS_CLEANUP_UNVERIFIABLE: emergency process-group cleanup could not be confirmed'}
        }
        if($null -ne $callerExitCode){$global:LASTEXITCODE=$savedExitCode}else{Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue}
        if($signalReader){$signalReader.Dispose()}elseif($signalPipe){$signalPipe.Dispose()};if($job){$job.Dispose()};$p.Dispose();$stdout.Dispose();$stderr.Dispose()
    }
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
    if($ArtifactRoot){Get-CFRunLocation $root $ArtifactRoot $identity|Out-Null}
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
    $effective=@(foreach($path in (Get-CFSorted $paths.Keys)){Get-CFEffective $root $path $paths[$path]})
    return @{binding=$identity;head=(Get-CFGitText $root @('rev-parse','HEAD'));index=@(foreach($p in (Get-CFSorted $index.Keys)){$index[$p]});working=$effective;untracked=$untracked;dirty_paths=@(Get-CFSorted $dirty.Keys)}
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
