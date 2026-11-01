$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'e2e-fixtures.ps1')
. (Join-Path $PSScriptRoot 'e2e-protocol.ps1')

if($IsWindows -and -not ('E2EOwnedJob' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public sealed class E2EOwnedJob : IDisposable {
 [StructLayout(LayoutKind.Sequential)] struct Basic { public long a,b; public uint flags; public UIntPtr min,max; public uint active; public UIntPtr affinity; public uint priority,scheduling; }
 [StructLayout(LayoutKind.Sequential)] struct IO { public ulong a,b,c,d,e,f; }
 [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic basic; public IO io; public UIntPtr processMemory,jobMemory,peakProcess,peakJob; }
 [StructLayout(LayoutKind.Sequential)] struct Accounting { public long a,b,c,d; public uint faults,total,active,terminated; }
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security,string name);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,ref Extended info,uint size);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint exit);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int kind,out Accounting info,uint size,IntPtr length);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 IntPtr handle;
 public E2EOwnedJob() { handle=CreateJobObject(IntPtr.Zero,null); if(handle==IntPtr.Zero) throw new Win32Exception(); var info=new Extended();info.basic.flags=0x2000; if(!SetInformationJobObject(handle,9,ref info,(uint)Marshal.SizeOf<Extended>())) { Dispose();throw new Win32Exception(); } }
 public void Attach(IntPtr process) { if(!AssignProcessToJobObject(handle,process)) throw new Win32Exception(); }
 public void Kill() { if(!TerminateJobObject(handle,1)) throw new Win32Exception(); }
 public bool IsEmpty() { Accounting info; if(!QueryInformationJobObject(handle,1,out info,(uint)Marshal.SizeOf<Accounting>(),IntPtr.Zero)) throw new Win32Exception();return info.active==0; }
 public void Dispose() { if(handle!=IntPtr.Zero) {CloseHandle(handle);handle=IntPtr.Zero;} }
}
'@
}

function Get-E2EProcessCore {
    # Reuse the runtime's atomic, ESRCH-only group signal implementation.
    # Module loading is model-free and happens before any Unix process launch.
    return Import-Module (Join-Path $PSScriptRoot '../scripts/ControlFlow.Core.psm1') -PassThru -DisableNameChecking
}
function Invoke-E2EGroupSignal([int]$GroupId,[int]$Signal) {
    $core=Get-E2EProcessCore
    return & $core {param($Id,$Value) Invoke-CFGroupSignal $Id $Value} $GroupId $Signal
}
function Invoke-E2EProcess {
    param([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[double]$TimeoutSeconds,[hashtable]$Environment=@{},[string]$InputText='', [string]$RawPath='', [scriptblock]$Observe)
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable;$start.WorkingDirectory=$WorkingDirectory;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $job=$null;$group=$false
    if($IsWindows){$job=[E2EOwnedJob]::new()}
    elseif($IsLinux){$null=Get-E2EProcessCore;$start.FileName=(Get-Command setsid -ErrorAction Stop).Source;$start.ArgumentList.Add('--wait');$start.ArgumentList.Add('--');$start.ArgumentList.Add($Executable);$group=$true}
    elseif($IsMacOS){$null=Get-E2EProcessCore;$start.FileName=(Get-Command python3 -ErrorAction Stop).Source;$start.ArgumentList.Add('-c');$start.ArgumentList.Add('import os,sys; os.setsid(); os.execv(sys.argv[1],sys.argv[1:])');$start.ArgumentList.Add($Executable);$group=$true}
    else{throw 'Process ownership unavailable on this platform'}
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.StandardInputEncoding=[Text.UTF8Encoding]::new($false,$true)
    $start.StandardOutputEncoding=[Text.Encoding]::UTF8;$start.StandardErrorEncoding=[Text.Encoding]::UTF8
    foreach($arg in $Arguments){$start.ArgumentList.Add($arg)}
    foreach($key in $Environment.Keys){if($key -in @('HOME','USERPROFILE','CODEX_HOME')){throw 'Identity/auth home overrides prohibited'};$start.Environment[$key]=[string]$Environment[$key]}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    $clock=[Diagnostics.Stopwatch]::StartNew();$stdout=[Text.StringBuilder]::new();$timedOut=$false;$budgetReason='';$writer=$null
    # Unix cleanup accepts ESRCH only; EPERM is never evidence of absence.
    $callerExitCode=$global:LASTEXITCODE
    try {
        if($RawPath){[IO.Directory]::CreateDirectory((Split-Path $RawPath -Parent)) | Out-Null;$writer=[IO.StreamWriter]::new($RawPath,$false,[Text.UTF8Encoding]::new($false));$writer.AutoFlush=$true}
        if(-not $process.Start()){throw 'Could not start child process'}
        if($job){try{$job.Attach($process.Handle)}catch{try{$process.Kill($true)}catch{};throw 'Could not establish owned Windows job; refusing uncontained process'}}
        $stderrTask=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($InputText);$process.StandardInput.Close()
        $lineTask=$process.StandardOutput.ReadLineAsync();$eof=$false
        while(-not $eof -or -not $process.HasExited -or -not $stderrTask.IsCompleted){
            if($lineTask.IsCompleted -and -not $eof){
                $line=$lineTask.GetAwaiter().GetResult()
                if($null -eq $line){$eof=$true}else{[void]$stdout.AppendLine($line);if($writer){$writer.WriteLine($line)};$lineTask=$process.StandardOutput.ReadLineAsync()}
            }
            if($Observe -and -not $process.HasExited){$reason=& $Observe $stdout.ToString();if($reason){$budgetReason=[string]$reason;break}}
            if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;break}
            [Threading.Thread]::Sleep(20)
        }
        # Terminate the ownership boundary even after its original parent exits.
        $cleanup=$true
        try{if($job){$job.Kill()}elseif($group){Invoke-E2EGroupSignal $process.Id 9 | Out-Null}}catch{$cleanup=$false}
        $drain=[Diagnostics.Stopwatch]::StartNew()
        $ownedEmpty=$false
        while($drain.ElapsedMilliseconds -lt 750){
            if(-not $eof -and $lineTask.IsCompleted){$line=$lineTask.GetAwaiter().GetResult();if($null -eq $line){$eof=$true}else{[void]$stdout.AppendLine($line);if($writer){$writer.WriteLine($line)};$lineTask=$process.StandardOutput.ReadLineAsync()}}
            [Threading.Thread]::Sleep(10)
            # Every observation replaces the prior result. An unknown latest
            # probe must not retain an earlier successful absence observation.
            $ownedEmpty=$false
            try{if($job){$ownedEmpty=$job.IsEmpty()}elseif($group){$ownedEmpty=-not (Invoke-E2EGroupSignal $process.Id 0)}}catch{
                # A transient EPERM can be retried within this same deadline;
                # only a later ESRCH can make ownedEmpty true.
                if(-not $group -or $_.Exception.Message -cne 'PROCESS_GROUP_SIGNAL_UNVERIFIABLE: errno=1'){$cleanup=$false}
            }
            if($eof -and $stderrTask.IsCompleted -and $process.HasExited -and $ownedEmpty){break}
        }
        $streams=$eof -and $stderrTask.IsCompleted
        return @{exit_code=if($process.HasExited){$process.ExitCode}else{-1};stdout=$stdout.ToString();stderr=if($stderrTask.IsCompleted){$stderrTask.GetAwaiter().GetResult()}else{''};wall_ms=$clock.ElapsedMilliseconds;timed_out=$timedOut;budget_reason=$budgetReason;streams_complete=$streams;cleanup_verified=$cleanup -and $process.HasExited -and $ownedEmpty}
    } finally {$global:LASTEXITCODE=$callerExitCode;if($writer){$writer.Dispose()};if($job){$job.Dispose()};$process.Dispose()}
}

function Read-E2EEvents([string]$Text) {
    $events=[Collections.Generic.List[object]]::new()
    foreach($line in ($Text -split '\r?\n')){if(-not [string]::IsNullOrWhiteSpace($line)){try{$events.Add(($line | ConvertFrom-Json -AsHashtable -Depth 100))}catch{throw 'Invalid exec JSONL event'}}}
    return $events.ToArray()
}


function Get-E2ETrialPrompt {
    param([hashtable]$Case,[ValidateSet('native','v4')][string]$Variant='v4')
    $Variant=$Variant.ToLowerInvariant()
    if($Variant -cnotin @('native','v4')){throw 'Unknown E2E treatment'}
    $prefix=if($Variant -cin @('v4')){'$controlflow-codex:controlflow '}else{''}
    if($Variant -ceq 'v4'){$prefix+='Use contract/runtime 4.0.0. Use the fixed proportional V4 route for this task. '}
    return $prefix+$Case.task+"`nReturn the requested final JSON. If a product choice is required, use status needs_clarification with the actual question and a stable question_id. Never invent an answer. Mark a lawful stop blocked or cancelled. Commit only when this task explicitly asks for a commit."
}
function Write-E2EProcessReceipt {
    param([hashtable]$Capture,[string]$Path)
    $receipt=[ordered]@{}
    foreach($key in @('exit_code','wall_ms','timed_out','budget_reason','streams_complete','cleanup_verified')){$receipt[$key]=$Capture[$key]}
    $receipt.stdout_bytes=[Text.Encoding]::UTF8.GetByteCount($Capture.stdout);$receipt.stderr_bytes=[Text.Encoding]::UTF8.GetByteCount($Capture.stderr)
    Write-E2EText $Path ($receipt | ConvertTo-Json)
}


function Get-E2EPluginDigest {
    param([object[]]$Inventory)
    $files=[Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($file in $Inventory){
        $path=[string]$file.path;$hash=[string]$file.sha256
        if([string]::IsNullOrWhiteSpace($path) -or $hash -cnotmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid plugin inventory entry'}
        $files.Add($path.Replace('\','/'),$hash.ToLowerInvariant())
    }
    $canonical=@(foreach($path in $files.Keys){[ordered]@{path=$path;sha256=$files[$path]}})
    return Get-E2EHash (ConvertTo-Json -InputObject $canonical -Depth 5 -Compress)
}
function Get-E2EMarketplaceName([hashtable]$Config) {
    $name=if($Config.MarketplaceName){$Config.MarketplaceName}else{'controlflow-eval'}
    if($name -isnot [string] -or $name -cnotmatch '^[a-z0-9][a-z0-9_-]{0,95}$'){throw 'Explicit marketplace name must be a bounded native identity without dots, quotes or path separators'}
    return $name
}
function Get-E2EConfigArguments([hashtable]$Config) {
    if($Config.Variant -isnot [string] -or $Config.Variant.ToLowerInvariant() -cnotin @('native','v4')){throw 'Unknown or retired E2E treatment'}
    $variant=$Config.Variant.ToLowerInvariant()
    $marketplace=Get-E2EMarketplaceName $Config
    $args=[Collections.Generic.List[string]]::new()
    $args.Add('-c');$args.Add('plugins={}')
    $args.Add('-c');$args.Add('marketplaces={}')
    # An empty TOML table merges; explicitly disable the identities observed in
    # the native account catalog. The actual context guard still rejects any
    # unexpected or remotely re-enabled extension.
    foreach($ambient in @('pages','plugin-management','sites','superpowers','work-pets')){
        $args.Add('-c');$args.Add('plugins.'+$ambient+'@openai-curated-remote.enabled=false')
    }
    $nativeOverrides=[ordered]@{model_reasoning_effort=$Config.Effort;approval_policy=$Config.ApprovalPolicy;approvals_reviewer=$Config.ApprovalReviewer;sandbox_mode=$Config.Sandbox}
    foreach($key in $nativeOverrides.Keys){$args.Add('-c');$args.Add($key+'='+($nativeOverrides[$key] | ConvertTo-Json -Compress))}
    if($Config.WindowsSandbox){
        if($Config.WindowsSandbox -notin @('elevated','unelevated')){throw 'Bounded Windows sandbox implementation required'}
        $args.Add('-c');$args.Add('windows.sandbox='+($Config.WindowsSandbox | ConvertTo-Json -Compress))
    }
    foreach($pair in $Config.Settings){
        if($pair -notmatch '^(model_provider|model_providers\.[A-Za-z0-9_-]+\.(name|base_url|env_key|wire_api|requires_openai_auth))=' -or $pair -match '(?i)(authorization|password|://[^/\s]+@)'){throw 'Settings must be provider metadata only; credentials and execution/security overrides prohibited'}
        $args.Add('-c');$args.Add($pair)
    }
    if($Config.MarketplaceRoot){
        $args.Add('-c');$args.Add('marketplaces.'+$marketplace+'.source_type="local"')
        $args.Add('-c');$args.Add('marketplaces.'+$marketplace+'.source='+($Config.MarketplaceRoot.Replace('\','/') | ConvertTo-Json -Compress))
    }
    # Native -c paths split on literal dots; TOML key quotes become literal key bytes.
    $args.Add('-c');$args.Add('plugins.controlflow-codex@'+$marketplace+'.enabled='+ $(if($variant -ceq 'v4'){'true'}else{'false'}))
    return $args.ToArray()
}



function Assert-E2ENativePolicy([hashtable]$Config) {
    if($Config.Sandbox -notin @('read-only','workspace-write') -or $Config.ApprovalPolicy -notin @('on-request','never') -or $Config.ApprovalReviewer -notin @('user','auto_review')){throw 'Explicit native bounded sandbox, approval policy and reviewer required'}
    if($Config.ApprovalPolicy -eq 'on-request' -and ($Config.ApprovalReviewer -ne 'auto_review' -or $Config.Sandbox -ne 'workspace-write')){throw 'Headless on-request requires explicit auto_review and workspace-write; user approval is unsupported by exec'}
    if($Config.WindowsSandbox -and $Config.WindowsSandbox -notin @('elevated','unelevated')){throw 'Bounded Windows sandbox implementation required'}
    if($IsWindows -and $Config.Sandbox -eq 'workspace-write' -and -not $Config.WindowsSandbox){throw 'Explicit WindowsSandbox elevated or unelevated required for isolated Windows workspace-write; disabled implementation downgrades to read-only'}
}
function Get-E2EExecArguments {
    param([hashtable]$Config,[string]$Schema,[string]$Session='',[string]$FixtureRoot='')
    Assert-E2ENativePolicy $Config
    if([string]::IsNullOrWhiteSpace($FixtureRoot)){throw 'Explicit fixture root required for session-only untrusted project state'}
    # SDK trust lookup retains native separators; forward-slash Windows keys do not match cwd.
    $fixturePath=[IO.Path]::GetFullPath($FixtureRoot)
    # Native dotted -c paths retain key quotes. Supply one whole map, never a trusted grant.
    $projectState='projects={'+($fixturePath | ConvertTo-Json -Compress)+'={trust_level="untrusted"}}'
    $argv=@($Config.CliPrefix)+@('--no-daemon','--sandbox',$Config.Sandbox)
    $argv+=@('exec')
    if($Session){$argv+=@('resume',$Session)}
    return $argv+@('--json','--ignore-user-config','-m',$Config.Model,'--output-schema',$Schema)+@(Get-E2EConfigArguments $Config)+@('-c',$projectState,'-')
}
function Invoke-E2EPolicyPreflight {
    param([hashtable]$Config,[string]$Directory)
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $schema=Join-Path $Directory 'policy-preflight-schema.json'
    @{type='object';properties=@{status=@{type='string';enum=@('done','needs_clarification','blocked','cancelled')};question_id=@{type='string'};question=@{type='string'};summary=@{type='string'}};required=@('status','question_id','question','summary');additionalProperties=$false} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $schema -Encoding utf8
    $checks=[Collections.Generic.List[object]]::new()
    foreach($session in @('','11111111-1111-7111-8111-111111111111')){
        $mode=if($session){'resume'}else{'initial'}
        $argv=@(Get-E2EExecArguments -Config $Config -Schema $schema -Session $session -FixtureRoot $Directory)
        Write-E2EText (Join-Path $Directory ($mode+'.argv.json')) ($argv | ConvertTo-Json)
        $capture=Invoke-E2EProcess -Executable $Config.CliPath -Arguments $argv -WorkingDirectory $Directory -TimeoutSeconds 15 -Environment $Config.Environment -InputText ''
        Write-E2EText (Join-Path $Directory ($mode+'.stdout.txt')) $capture.stdout
        Write-E2EText (Join-Path $Directory ($mode+'.stderr.txt')) $capture.stderr
        $valid=$capture.exit_code -eq 1 -and $capture.stdout.Length -eq 0 -and $capture.stderr.Trim() -ceq 'No prompt provided via stdin.' -and -not $capture.timed_out -and $capture.streams_complete -and $capture.cleanup_verified
        $checks.Add(@{mode=$mode;session_id=$session;verified=$valid;exit_code=$capture.exit_code;wall_ms=$capture.wall_ms;timed_out=$capture.timed_out;streams_complete=$capture.streams_complete;cleanup_verified=$capture.cleanup_verified;stdout_bytes=[Text.Encoding]::UTF8.GetByteCount($capture.stdout);stderr_sha256=Get-E2EHash $capture.stderr})
    }
    $report=@{verified=@($checks | Where-Object {-not $_.verified}).Count -eq 0;method='exact exec argv with empty stdin; requires native pre-generation guard, not help';checks=$checks.ToArray()}
    Write-E2EText (Join-Path $Directory 'result.json') ($report | ConvertTo-Json -Depth 10)
    return $report
}

function Invoke-E2ETrial {
    param([hashtable]$Case,[hashtable]$Config,[string]$TrialDirectory)
    # Readiness is checked before any CLI, history, profile, cache or model access.
    $readiness=Get-E2EProtocolReadiness $Config
    if($readiness.may_launch){throw 'No supported native V4 execution verifier is implemented'}
    return New-E2EProtocolBlockedResult $Case $Config $TrialDirectory
}

function New-E2EReviewMetrics([hashtable]$Measurements=@{},[ValidateSet('missing','manual','instrumented')][string]$Source='missing') {
    $fields=@('active_human_review_ms','decision_wait_ms','substantive_reentries','review_packet_bytes','rework_ms','lead_time_ms')
    $result=@{source=$Source}
    if($Source -ceq 'missing' -and $Measurements.Count -gt 0){throw 'MEASUREMENT_SOURCE_REQUIRED'}
    foreach($key in $Measurements.Keys){if($key -cnotin $fields){throw 'UNKNOWN_REVIEW_METRIC'}}
    foreach($field in $fields){
        $value=if($Measurements.ContainsKey($field)){$Measurements[$field]}else{$null}
        if($null -ne $value -and ($value -isnot [ValueType] -or [double]::IsNaN([double]$value) -or [double]::IsInfinity([double]$value) -or [double]$value -lt 0)){throw 'INVALID_REVIEW_METRIC'}
        $result[$field]=$value
    }
    return $result
}
function Measure-E2EReviewMetrics([object[]]$Records) {
    $result=@{record_count=$Records.Count;manual_count=@($Records|Where-Object {$_.source -ceq 'manual'}).Count;instrumented_count=@($Records|Where-Object {$_.source -ceq 'instrumented'}).Count;fields=@{}}
    foreach($field in @('active_human_review_ms','decision_wait_ms','substantive_reentries','review_packet_bytes','rework_ms','lead_time_ms')){
        $values=@($Records|Where-Object {$null -ne $_[$field]}|ForEach-Object {[double]$_[$field]})
        $result.fields[$field]=@{measured_count=$values.Count;missing_count=$Records.Count-$values.Count;median=$(if($values.Count -gt 0){Get-E2EMedian $values}else{$null})}
    }
    return $result
}
function Get-E2EMedian([double[]]$Values) {
    if(-not $Values.Count){return $null};$s=@($Values | Sort-Object);$n=$s.Count
    if($n % 2){return $s[[int][Math]::Floor($n/2)]};return ($s[$n/2-1]+$s[$n/2])/2
}

function Set-E2EDiagnosticCollectionResult {
    param([hashtable]$Result,[hashtable]$Case,[hashtable]$Fixture)
    $Result.risk_diagnostics=Test-E2ECriticalRiskDiagnostics -Case $Case -Fixture $Fixture
    if(-not $Result.risk_diagnostics.collection_complete){
        if($Result.outcome){$Result.false_completion=$true}
        $prior=$Result.reason;$Result.status='incomplete'
        $Result.reason=$prior+';critical diagnostic collection incomplete:'+($Result.risk_diagnostics.failures -join ',')
    }
    return $Result
}
function Test-E2EProvenance($Provenance) {
    if($Provenance.project_trust -cne 'untrusted'){return $false}
    if($Provenance -isnot [Collections.IDictionary]){return $false}
    foreach($field in @('model','host','cli_version')){if($Provenance[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($Provenance[$field])){return $false}}
    if($Provenance.fixture_hash -isnot [string] -or $Provenance.fixture_hash -cnotmatch '^[a-fA-F0-9]{64}$'){return $false}
    if($Provenance.effort -notin @('none','minimal','low','medium','high','xhigh','max') -or $Provenance.sandbox -notin @('read-only','workspace-write') -or $Provenance.approval_policy -notin @('never','on-request') -or $Provenance.approvals_reviewer -notin @('user','auto_review')){return $false}
    if($null -ne $Provenance.windows_sandbox -and $Provenance.windows_sandbox -ne '' -and $Provenance.windows_sandbox -notin @('elevated','unelevated')){return $false}
    if($Provenance.settings -isnot [Collections.IList]){return $false}
    foreach($setting in $Provenance.settings){if($setting -isnot [string] -or [string]::IsNullOrWhiteSpace($setting)){return $false}}
    if($Provenance.budget -isnot [Collections.IDictionary]){return $false}
    foreach($field in @('tokens','tools','wall_seconds')){
        $value=$Provenance.budget[$field]
        if(($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) -or $value -le 0 -or -not [double]::IsFinite([double]$value) -or [Math]::Floor([double]$value) -ne $value){return $false}
    }
    return $true
}
function Test-E2EResultEnvelope($Result) {
    if($Result.status -notin @('success','failed')){return $false}
    if(-not (Test-E2EProvenance $Result.provenance)){return $false}
    $u=$Result.usage
    if($u.complete -isnot [bool] -or -not $u.complete){return $false}
    foreach($field in @('input_tokens','output_tokens','cached_input_tokens','total_tokens','tool_calls')){
        if(($u[$field] -isnot [int] -and $u[$field] -isnot [long]) -or $u[$field] -lt 0){return $false}
    }
    if($u.total_tokens -ne ($u.input_tokens+$u.output_tokens) -or $u.cached_input_tokens -gt $u.input_tokens){return $false}
    if($Result.status -in @('success','failed')){
        $o=$Result.outcome
        if($o.pass -isnot [bool] -or $o.collection_complete -isnot [bool] -or -not $o.collection_complete -or $o.receipt.verified -isnot [bool] -or -not $o.receipt.verified -or -not $o.receipt.nonce){return $false}
        if(($o.check_count -isnot [int] -and $o.check_count -isnot [long]) -or ($o.planned_check_count -isnot [int] -and $o.planned_check_count -isnot [long]) -or $o.check_count -le 0 -or $o.check_count -ne $o.planned_check_count){return $false}
        if(($Result.status -eq 'success') -ne $o.pass){return $false}
    }
    return $true
}
function Measure-E2EPairs {
    param([object[]]$Results,[ValidateSet('v4')][string]$Treatment='v4')
    return Measure-E2EV4Pairs $Results
}
