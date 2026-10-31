. (Join-Path $PSScriptRoot 'core-test-helpers.ps1')
LoadCore
. (Join-Path $PSScriptRoot '../scripts/lib/Git.ps1')
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
    $p=Contract $r 'SMALL' 'none' '[Console]::Out.WriteLine("capture-out"); [Console]::Error.WriteLine("capture-error")' 'capture-streams'
    $run=Start-ControlFlowRun $r $p 'capture-streams'
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
    $p=Contract $r 'SMALL' 'none' $command 'inherited-output'
    $c=Get-Content $p -Raw | ConvertFrom-Json -AsHashtable;$c.checks[0].timeout_seconds=5
    [IO.File]::WriteAllText($p,($c | ConvertTo-Json -Depth 20))
    $run=Start-ControlFlowRun $r $p 'inherited-output'
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
    $p=Contract $r 'SMALL' 'none' $command 'silent-child'
    $run=Start-ControlFlowRun $r $p 'silent-child'
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
