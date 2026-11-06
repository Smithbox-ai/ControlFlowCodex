. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$script:InterruptFailures=[Collections.Generic.List[string]]::new()
function Test-InterruptSafety([string]$Name,[scriptblock]$Body) {
    try {& $Body;Write-Output "PASS $Name"}
    catch {$script:InterruptFailures.Add("${Name}: $($_.Exception.Message)");Write-Output "FAIL ${Name}: $($_.Exception.Message)"}
}
function Invoke-InterruptWithoutTurn([string]$Root,[string]$Session) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-File',"$script:CoreRoot/scripts/invoke-hook.ps1",'-Event','Interrupt')){$info.ArgumentList.Add($arg)}
    $child=[Diagnostics.Process]::new();$child.StartInfo=$info
    try {
        [void]$child.Start();$stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $child.StandardInput.WriteLine((@{session_id=$Session;cwd=$Root}|ConvertTo-Json -Compress));$child.StandardInput.Close()
        if(-not $child.WaitForExit(3000)){$child.Kill($true);throw 'Interrupt callback exceeded native three-second budget'}
        $watch.Stop();$output=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
        Assert ($child.ExitCode -eq 0 -and -not $errorText) "Interrupt callback emits valid protocol: $errorText"
        return @{reply=($output|ConvertFrom-Json -AsHashtable);elapsed_ms=$watch.Elapsed.TotalMilliseconds}
    }finally{if(-not $child.HasExited){$child.Kill($true)};$child.Dispose()}
}
# The release happens on a CLR timer, independently of the PowerShell thread
# blocked inside the publisher. Every held handle is disposed in finally.
if(-not ('CFInterruptReaderHold' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public sealed class CFInterruptReaderHold : IDisposable {
    private FileStream stream;
    private Timer timer;
    public CFInterruptReaderHold(string path, int milliseconds) {
        stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        timer = new Timer(_ => Interlocked.Exchange(ref stream, null)?.Dispose(), null, milliseconds, Timeout.Infinite);
    }
    public void Dispose() {
        timer.Dispose();
        Interlocked.Exchange(ref stream, null)?.Dispose();
    }
}
'@
}
$r=NewFixture
try {
    $module=Get-TestControlFlowModule
    $session='interrupt-safety';$contract=LegacyContract $r -SessionId $session
    $run=New-HistoricalV3RunFixture $r $contract $session;$path=$run.run_path
    Test-InterruptSafety 'optional turn_id callback persists interruption' {
        $callback=Invoke-InterruptWithoutTurn $r $session
        Assert ($callback.reply.systemMessage -eq 'ControlFlow INTERRUPTED. Explicit user resumption is required.') 'missing optional turn_id still reports durable interruption'
        $read=Read-ControlFlowRun $r $path
        Assert ($read.state.status -eq 'INTERRUPTED') 'callback without turn_id persists INTERRUPTED'
        Assert ($null -eq $read.pending_interrupt.native_evidence.turn_id) 'omitted turn identifier is recorded as null'
        Assert ($callback.elapsed_ms -lt 3000) 'callback stays inside native budget'
    }
    Test-InterruptSafety 'cooperating mutable reader permits atomic replacement' {
        $target=Join-Path $r 'mutable.json';$source=Join-Path $r 'mutable.tmp'
        [IO.File]::WriteAllText($target,'{"generation":"old"}');[IO.File]::WriteAllText($source,'{"generation":"new"}')
        $reader=& $module {param($p) Open-CFMutableRead $p} $target
        try {
            & $module {param($s,$d) Move-CFMutableFile $s $d} $source $target
            $old=[IO.StreamReader]::new($reader,[Text.UTF8Encoding]::new($false,$true),$false,1024,$true)
            try {Assert ($old.ReadToEnd() -eq '{"generation":"old"}') 'held reader retains complete old generation'}finally{$old.Dispose()}
            Assert ((& $module {param($p) Read-CFMutableText $p} $target) -eq '{"generation":"new"}') 'new reader sees complete replaced generation'
        }finally{$reader.Dispose()}
    }
    Test-InterruptSafety 'mutable text accepts UTF8 BOM and rejects invalid UTF8' {
        $target=Join-Path $r 'encoding.json'
        [IO.File]::WriteAllBytes($target,([byte[]]@(239,187,191)+[Text.Encoding]::UTF8.GetBytes('{"ok":true}')))
        Assert ((& $module {param($p) Read-CFMutableText $p} $target) -eq '{"ok":true}') 'UTF8 BOM is not JSON content'
        [IO.File]::WriteAllBytes($target,[byte[]]@(123,34,255,34,125))
        Throws {& $module {param($p) Read-CFMutableText $p} $target} 'mutable JSON rejects malformed UTF8 instead of replacing bytes'
    }
    Test-InterruptSafety 'run readers require explicitly absolute run paths' {
        $processDirectory=[Environment]::CurrentDirectory;$relative=[IO.Path]::GetFileName($path);$failure=$null
        try {
            [Environment]::CurrentDirectory=[IO.Path]::GetDirectoryName($path)
            try {Read-ControlFlowRun $r $relative $session|Out-Null}catch{$failure=$_}
        }finally{[Environment]::CurrentDirectory=$processDirectory}
        Assert ($null -ne $failure -and $failure.Exception.Message -match 'INVALID_RUN_PATH') 'relative spelling cannot bypass run storage absolute-path policy'
    }
    Test-InterruptSafety 'resume and subsequent interrupt survive cooperating readers' {
        $first=Request-ControlFlowInterrupt $r $session
        $pending=Join-Path $path 'pending-interrupt.json';$statePath=Join-Path $path 'state.json'
        $mailReader=& $module {param($p) Open-CFMutableRead $p} $pending
        $stateReader=& $module {param($p) Open-CFMutableRead $p} $statePath
        try {
            $resumed=Update-ControlFlowRun $r $path @{type='resume';user_decision_ref='user:resume-reader-fixture'}
            Assert ($resumed.state.status -eq 'ACTIVE' -and $resumed.state.acknowledged_interrupt_id -eq $first.interrupt_id) 'state publisher acknowledges mailbox while state reader is open'
            $second=Request-ControlFlowInterrupt $r $session
            Assert ($second.interrupt_id -ne $first.interrupt_id) 'new interrupt replaces held acknowledged mailbox'
            $read=Read-ControlFlowRun $r $path
            Assert ($read.state.status -eq 'INTERRUPTED' -and $read.pending_interrupt.interrupt_id -eq $second.interrupt_id) 'replacement remains durable while old mailbox reader is open'
        }finally{$mailReader.Dispose();$stateReader.Dispose()}
    }
    Test-InterruptSafety 'replacement retries a transient Windows sharing conflict' {
        if(-not $IsWindows){return}
        $target=Join-Path $r 'retry.json';$source=Join-Path $r 'retry.tmp'
        [IO.File]::WriteAllText($target,'old');[IO.File]::WriteAllText($source,'new')
        $hold=[CFInterruptReaderHold]::new($target,125)
        try {
            $watch=[Diagnostics.Stopwatch]::StartNew()
            & $module {param($s,$d) Move-CFMutableFile $s $d} $source $target
            $watch.Stop()
            Assert ($watch.Elapsed.TotalMilliseconds -ge 50 -and $watch.Elapsed.TotalMilliseconds -lt 500) 'transient reader is retried within bounded publication budget'
            Assert ([IO.File]::ReadAllText($target) -eq 'new' -and -not [IO.File]::Exists($source)) 'retry publishes replacement rather than returning false success'
        }finally{$hold.Dispose()}
    }
    Test-InterruptSafety 'persistent Windows sharing conflict fails within bound' {
        if(-not $IsWindows){return}
        $target=Join-Path $r 'conflict.json';$source=Join-Path $r 'conflict.tmp'
        [IO.File]::WriteAllText($target,'old');[IO.File]::WriteAllText($source,'new')
        # Keep the conflict well beyond the publication budget, but release it
        # independently so a retry-bound regression cannot hang this fixture.
        $reader=[CFInterruptReaderHold]::new($target,2000)
        try {
            $failure=$null;$watch=[Diagnostics.Stopwatch]::StartNew()
            try {& $module {param($s,$d) Move-CFMutableFile $s $d} $source $target}catch{$failure=$_}
            $watch.Stop()
            Assert ($null -ne $failure -and ($failure.Exception.GetBaseException().HResult -band 0xFFFF) -in @(5,32,33) -and $failure.Exception.Message) 'persistent conflict preserves the final native file error'
            Assert ($watch.Elapsed.TotalMilliseconds -ge 100 -and $watch.Elapsed.TotalMilliseconds -lt 500) 'permanent conflict retries and stops well within callback budget'
            Assert ([IO.File]::ReadAllText($target) -eq 'old' -and [IO.File]::Exists($source)) 'failed replacement preserves target and source without false success'
            Write-Output ("persistent sharing conflict elapsed_ms="+[math]::Round($watch.Elapsed.TotalMilliseconds))
        }finally{$reader.Dispose()}
    }
    Test-InterruptSafety 'replacement rejects bad paths without retrying' {
        $source=Join-Path $r 'bad-path.tmp';[IO.File]::WriteAllText($source,'new')
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $failure=$null
        try {& $module {param($s,$d) Move-CFMutableFile $s $d} $source $r}catch{$failure=$_}
        $watch.Stop()
        Assert ($null -ne $failure -and $failure.Exception.GetBaseException() -is [IO.IOException]) 'directory destination produces a file error'
        Assert ($watch.Elapsed.TotalMilliseconds -lt 150) 'invalid directory destination does not consume sharing retry budget'
        Assert ([IO.File]::ReadAllText($source) -eq 'new') 'bad destination leaves source intact'
        $missing=Join-Path $r 'missing-source.tmp';$target=Join-Path $r 'missing-result.json';$watch.Restart()
        $failure=$null
        try {& $module {param($s,$d) Move-CFMutableFile $s $d} $missing $target}catch{$failure=$_}
        Assert ($null -ne $failure -and $failure.Exception.GetBaseException() -is [IO.FileNotFoundException]) 'missing source preserves its file-not-found error'
        $watch.Stop();Assert ($watch.Elapsed.TotalMilliseconds -lt 150 -and -not [IO.File]::Exists($target)) 'missing source does not retry or publish anything'
    }
}finally{RemoveFixture $r}
if($script:InterruptFailures.Count){throw ($script:InterruptFailures -join "`n")}
Write-Output "interrupt-safety: $script:Count assertions passed"
$global:LASTEXITCODE=0
