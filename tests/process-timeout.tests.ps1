. (Join-Path $PSScriptRoot 'core-test-helpers.ps1')
LoadCore
. (Join-Path $PSScriptRoot '../scripts/lib/Git.ps1')
# The shared stream-drain budget may already be exhausted before verification.
# Exercise the actual cleanup blocks with controlled observations, without OS signals.
$cleanupAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $script:CoreRoot 'scripts/lib/Git.ps1'),[ref]$null,[ref]$null)
$cleanupFunction=@($cleanupAst.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-CFProcess'},$true))[0]
$cleanupCases=@(@{ticks=749;mode='absent';prior=$true;expected=$true},@{ticks=750;mode='absent';prior=$true;expected=$true},@{ticks=751;mode='absent';prior=$true;expected=$true},@{ticks=750;mode='present';prior=$true;expected=$false},@{ticks=750;mode='error';prior=$true;expected=$false},@{ticks=750;mode='absent';prior=$false;expected=$false})
foreach($cleanupKind in @('job','group')){
    $cleanupNodes=@($cleanupFunction.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq ('$'+$cleanupKind) -and $n.Extent.Text.Contains('$empty=$false') -and $n.Extent.Text.Contains('$drain.ElapsedMilliseconds')},$true))
    if($cleanupNodes.Count -ne 1){throw "Cleanup verification block is ambiguous: $cleanupKind"}
    $cleanupBlock=[scriptblock]::Create($cleanupNodes[0].Extent.Text)
    foreach($cleanupCase in $cleanupCases){
        $cleanupObserved=& {
            param($code,$kind,$case)
            $script:CFTestCleanupProbeCount=0;$script:CFTestCleanupProbeMode=$case.mode
            function Get-CFTestPresence {$script:CFTestCleanupProbeCount++;if($script:CFTestCleanupProbeMode -ceq 'error'){throw 'OBSERVATION_DENIED'};return ($script:CFTestCleanupProbeMode -ceq 'present')}
            function Invoke-CFGroupSignal {param($GroupId,$Signal)Get-CFTestPresence}
            $job=$null;$group=$false
            if($kind -ceq 'group'){$group=$true}else{$job=[pscustomobject]@{};$job|Add-Member -MemberType ScriptMethod -Name IsEmpty -Value {-not(Get-CFTestPresence)}}
            $p=[pscustomobject]@{Id=424242};$drain=[pscustomobject]@{ElapsedMilliseconds=$case.ticks};$cleanupOk=$case.prior
            . $code
            @{cleanup_ok=$cleanupOk;probes=$script:CFTestCleanupProbeCount}
        } $cleanupBlock $cleanupKind $cleanupCase
        Assert ($cleanupObserved.probes -eq 1 -and $cleanupObserved.cleanup_ok -eq $cleanupCase.expected) "cleanup $cleanupKind observes once at elapsed=$($cleanupCase.ticks), presence=$($cleanupCase.mode), prior=$($cleanupCase.prior)"
    }
}
# A transient EPERM must never pass without a later ESRCH in the same deadline.
$retryNodes=@($cleanupFunction.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '$group' -and $n.Extent.Text.Contains('$empty=$false') -and $n.Extent.Text.Contains('$drain.ElapsedMilliseconds')},$true))
if($retryNodes.Count -ne 1){throw 'Retry verification block is ambiguous'}
$block=[scriptblock]::Create($retryNodes[0].Extent.Text)
$cases=@(
 @{name='transient EPERM requires subsequent ESRCH';sequence=@('EPERM','absent');limit=2;prior=$true;expected=$true;probes=2},
 @{name='prior kill failure remains failure';sequence=@('EPERM','absent');limit=2;prior=$false;expected=$false;probes=2},
 @{name='persistent EPERM never proves absence';sequence=@('EPERM','EPERM');limit=2;prior=$true;expected=$false;probes=2},
 @{name='expired deadline forbids retry';sequence=@('EPERM');limit=1;prior=$true;expected=$false;probes=1},
 @{name='unexpected errno remains fail closed';sequence=@('EINVAL','absent');limit=2;prior=$true;expected=$false;probes=1},
 @{name='live group after EPERM remains failure';sequence=@('EPERM','present');limit=2;prior=$true;expected=$false;probes=2},
 @{name='ESRCH after EPERM and live observation permits pass';sequence=@('EPERM','present','absent');limit=3;prior=$true;expected=$true;probes=3}
)
foreach($case in $cases){
 $actual=& {
  param($code,$case)
  $script:RetryProbeCount=0;$script:RetryCase=$case
  function Invoke-CFGroupSignal {
   param($GroupId,$Signal)
   $next=$script:RetryCase.sequence[[math]::Min($script:RetryProbeCount,$script:RetryCase.sequence.Count-1)];$script:RetryProbeCount++
   switch -CaseSensitive ($next){'EPERM'{throw 'PROCESS_GROUP_SIGNAL_UNVERIFIABLE: errno=1'}'EINVAL'{throw 'PROCESS_GROUP_SIGNAL_UNVERIFIABLE: errno=22'}'absent'{return $false}'present'{return $true}default{throw 'BAD_FIXTURE'}}
  }
  $p=[pscustomobject]@{Id=424242};$group=$true;$cleanupOk=$case.prior
  $drain=[pscustomobject]@{};$drain|Add-Member -MemberType ScriptProperty -Name ElapsedMilliseconds -Value {if($script:RetryProbeCount-ge$script:RetryCase.limit){750}else{0}}
  . $code
  @{cleanup_ok=$cleanupOk;probes=$script:RetryProbeCount}
 } $block $case
 Assert ($actual.cleanup_ok-eq$case.expected-and$actual.probes-eq$case.probes) $case.name
}
Assert ($null -ne (Get-Command Resolve-CFGroupSignalResult -ErrorAction SilentlyContinue)) 'group signal distinguishes absence from denied observation'
Assert ((Resolve-CFGroupSignalResult 0 0) -eq $true) 'successful signal means group exists'
Assert ((Resolve-CFGroupSignalResult -1 3) -eq $false) 'ESRCH confirms group absent'
Throws {Resolve-CFGroupSignalResult -1 1} 'EPERM leaves group state unverifiable'
Throws {Resolve-CFGroupSignalResult -1 22} 'unexpected group observation error is unverifiable'
if($IsLinux -or $IsMacOS){
    $readyFile=Join-Path ([IO.Path]::GetTempPath()) ('cf-group-ready-'+[guid]::NewGuid().ToString('N'))
    $library=if($IsMacOS){'/usr/lib/libSystem.B.dylib'}else{'libc'}
    $source=@'
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class CFTestSession { [DllImport("__LIB__",SetLastError=true)] public static extern int setsid(); }'
if([CFTestSession]::setsid() -lt 0){exit 2}
[IO.File]::WriteAllText($env:CF_TEST_GROUP_READY,[string]$PID)
Start-Sleep -Seconds 30
'@
    $source=$source.Replace('__LIB__',$library)
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=(Get-Command pwsh).Source;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($arg in @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded)){[void]$start.ArgumentList.Add($arg)}
    $start.Environment['CF_TEST_GROUP_READY']=$readyFile
    $process=[Diagnostics.Process]::Start($start)
    try {
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while(-not (Test-Path -LiteralPath $readyFile) -and -not $process.HasExited -and $clock.Elapsed.TotalSeconds -lt 10){[Threading.Thread]::Sleep(20)}
        Assert ((Test-Path -LiteralPath $readyFile) -and [int][IO.File]::ReadAllText($readyFile) -eq $process.Id) 'owned POSIX process group is established before signalling'
        Assert (Invoke-CFGroupSignal $process.Id 0) 'live POSIX group is observable'
        $pair=[CFUnixGroupSignal]::Send(-2147483647,0)
        [Runtime.InteropServices.Marshal]::SetLastPInvokeError(1)
        Assert ($pair.Result -eq -1 -and $pair.ErrorNumber -eq 3) 'native signal result and errno remain paired after an unrelated last-error change'
        $pair=[CFUnixGroupSignal]::Send(-$process.Id,0)
        [Runtime.InteropServices.Marshal]::SetLastPInvokeError(22)
        Assert ($pair.Result -eq 0 -and $pair.ErrorNumber -eq 0) 'successful native signal pair reports zero errno independently of later calls'
        Assert (Invoke-CFGroupSignal $process.Id 9) 'owned POSIX group can be terminated'
        Assert ($process.WaitForExit(5000)) 'owned POSIX process exits after group termination'
        $clock.Restart();$absent=$false
        while($clock.Elapsed.TotalSeconds -lt 2){if(-not (Invoke-CFGroupSignal $process.Id 0)){$absent=$true;break};[Threading.Thread]::Sleep(20)}
        Assert $absent 'ESRCH confirms terminated POSIX group is absent'
    }finally{
        if(-not $process.HasExited){$process.Kill($true);$process.WaitForExit()}
        $process.Dispose()
        if(Test-Path -LiteralPath $readyFile){Remove-Item -LiteralPath $readyFile -Force}
    }
}
# A completed parent cannot leave an inherited output handle open indefinitely.
$r=NewFixture
$pidFile=Join-Path ([IO.Path]::GetTempPath()) ('cf-child-'+[guid]::NewGuid().ToString('N')+'.pid')
$marker=$null
try {
    $p=LegacyContract $r 'SMALL' 'none' '[Console]::Out.WriteLine("capture-out"); [Console]::Error.WriteLine("capture-error")' 'capture-streams'
    $run=New-HistoricalV3RunFixture $r $p 'capture-streams'
    for($i=0;$i -lt 6;$i++){
        $capture=Capture-ControlFlowCheck $r $run.run_path 'check-1'
        $out=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $run.run_path $capture.stdout_ref.path))).Trim()
        $err=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $run.run_path $capture.stderr_ref.path))).Trim()
        Assert ($capture.status -eq 'PASS' -and $out -ceq 'capture-out' -and $err -ceq 'capture-error') "successful check preserves output and does not randomly fail on job accounting (status=$($capture.status), incomplete=$($capture.process_incomplete), out=$out, err=$err)"
    }
    $spawn=@'
$p=[Diagnostics.ProcessStartInfo]::new();$p.FileName=(Get-Command pwsh).Source;$p.UseShellExecute=$false;$p.CreateNoWindow=$true
$p.ArgumentList.Add('-NoProfile');$p.ArgumentList.Add('-Command');$p.ArgumentList.Add('Start-Sleep -Seconds 15')
$child=[Diagnostics.Process]::Start($p);[IO.File]::WriteAllText($args[0],[string]$child.Id);exit 0
'@
    File $r 'spawn-child.ps1' $spawn
    $command="& ./spawn-child.ps1 '"+$pidFile.Replace("'","''")+"'"
    $p=LegacyContract $r 'SMALL' 'none' $command 'inherited-output'
    $c=Get-Content $p -Raw | ConvertFrom-Json -AsHashtable;$c.checks[0].timeout_seconds=5
    [IO.File]::WriteAllText($p,($c | ConvertTo-Json -Depth 20))
    $run=New-HistoricalV3RunFixture $r $p 'inherited-output'
    $clock=[Diagnostics.Stopwatch]::StartNew();$capture=Capture-ControlFlowCheck $r $run.run_path 'check-1';$clock.Stop()
    Assert ((($capture.status -eq 'TIMEOUT' -and $capture.timed_out) -or ($capture.status -eq 'FAIL' -and $capture.process_incomplete)) -and $clock.Elapsed.TotalSeconds -lt 8) 'unfinished inherited stream never passes or exceeds deadline'
    $childId=[int][IO.File]::ReadAllText($pidFile)
    Assert (-not (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'owned child is terminated after parent exits'
    Remove-Item -LiteralPath $pidFile -Force
    # A silent descendant may still contain unfinished assertions.
    $silent=@'
$inner="Start-Sleep -Seconds 12; [IO.File]::WriteAllText('"+$args[1].Replace("'","''")+"','failure'); exit 7"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
$child=Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -RedirectStandardOutput ($args[0]+'.out') -RedirectStandardError ($args[0]+'.err') -PassThru -NoNewWindow
[IO.File]::WriteAllText($args[0],[string]$child.Id);exit 0
'@
    File $r 'spawn-silent.ps1' $silent
    $marker=$pidFile+'.failure'
    $command="& ./spawn-silent.ps1 '"+$pidFile.Replace("'","''")+"' '"+$marker.Replace("'","''")+"'"
    $p=LegacyContract $r 'SMALL' 'none' $command 'silent-child'
    $run=New-HistoricalV3RunFixture $r $p 'silent-child'
    $clock=[Diagnostics.Stopwatch]::StartNew();$capture=Capture-ControlFlowCheck $r $run.run_path 'check-1';$clock.Stop()
    $childId=[int][IO.File]::ReadAllText($pidFile)
    $childAlive=$null -ne (Get-Process -Id $childId -ErrorAction SilentlyContinue)
    Assert ($capture.status -eq 'FAIL' -and $capture.process_incomplete -and -not $childAlive) "unfinished silent child fails the check and is terminated (status=$($capture.status), incomplete=$($capture.process_incomplete), timeout=$($capture.timed_out), child=$childId, alive=$childAlive, seconds=$([math]::Round($clock.Elapsed.TotalSeconds,2)), marker=$(Test-Path -LiteralPath $marker))"
    Start-Sleep -Seconds 1
    Assert (-not (Test-Path -LiteralPath $marker)) 'terminated child cannot later publish a failure side effect'
}finally {
    if(Test-Path -LiteralPath $pidFile){$childId=[int][IO.File]::ReadAllText($pidFile);$child=Get-Process -Id $childId -ErrorAction SilentlyContinue;if($child){$child.Kill($true);$child.Dispose()};Remove-Item -LiteralPath $pidFile -Force}
    if($marker -and (Test-Path -LiteralPath $marker)){Remove-Item -LiteralPath $marker -Force}
    foreach($file in @($pidFile+'.out',$pidFile+'.err')){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}}
    if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}
}
Write-Output "process timeout: $script:Count assertions passed"
$global:LASTEXITCODE=0
