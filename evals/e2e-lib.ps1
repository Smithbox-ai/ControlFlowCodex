$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'e2e-fixtures.ps1')

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

function Invoke-E2EProcess {
    param([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[double]$TimeoutSeconds,[hashtable]$Environment=@{},[string]$InputText='', [string]$RawPath='', [scriptblock]$Observe)
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable;$start.WorkingDirectory=$WorkingDirectory;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $job=$null;$group=$false
    if($IsWindows){$job=[E2EOwnedJob]::new()}
    elseif($IsLinux){$start.FileName=(Get-Command setsid -ErrorAction Stop).Source;$start.ArgumentList.Add('--wait');$start.ArgumentList.Add('--');$start.ArgumentList.Add($Executable);$group=$true}
    elseif($IsMacOS){$start.FileName=(Get-Command python3 -ErrorAction Stop).Source;$start.ArgumentList.Add('-c');$start.ArgumentList.Add('import os,sys; os.setsid(); os.execv(sys.argv[1],sys.argv[1:])');$start.ArgumentList.Add($Executable);$group=$true}
    else{throw 'Process ownership unavailable on this platform'}
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.StandardInputEncoding=[Text.UTF8Encoding]::new($false,$true)
    $start.StandardOutputEncoding=[Text.Encoding]::UTF8;$start.StandardErrorEncoding=[Text.Encoding]::UTF8
    foreach($arg in $Arguments){$start.ArgumentList.Add($arg)}
    foreach($key in $Environment.Keys){if($key -in @('HOME','USERPROFILE','CODEX_HOME')){throw 'Identity/auth home overrides prohibited'};$start.Environment[$key]=[string]$Environment[$key]}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    $clock=[Diagnostics.Stopwatch]::StartNew();$stdout=[Text.StringBuilder]::new();$timedOut=$false;$budgetReason='';$writer=$null
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
        try{if($job){$job.Kill()}elseif($group){& /bin/kill -KILL -- (-$process.Id) 2>$null | Out-Null}}catch{$cleanup=$false}
        $drain=[Diagnostics.Stopwatch]::StartNew()
        $ownedEmpty=$false
        while($drain.ElapsedMilliseconds -lt 750){
            if(-not $eof -and $lineTask.IsCompleted){$line=$lineTask.GetAwaiter().GetResult();if($null -eq $line){$eof=$true}else{[void]$stdout.AppendLine($line);if($writer){$writer.WriteLine($line)};$lineTask=$process.StandardOutput.ReadLineAsync()}}
            [Threading.Thread]::Sleep(10)
            try{if($job){$ownedEmpty=$job.IsEmpty()}elseif($group){& /bin/kill -0 -- (-$process.Id) 2>$null | Out-Null;$ownedEmpty=$LASTEXITCODE -ne 0}}catch{$cleanup=$false}
            if($eof -and $stderrTask.IsCompleted -and $process.HasExited -and $ownedEmpty){break}
        }
        $streams=$eof -and $stderrTask.IsCompleted
        return @{exit_code=if($process.HasExited){$process.ExitCode}else{-1};stdout=$stdout.ToString();stderr=if($stderrTask.IsCompleted){$stderrTask.GetAwaiter().GetResult()}else{''};wall_ms=$clock.ElapsedMilliseconds;timed_out=$timedOut;budget_reason=$budgetReason;streams_complete=$streams;cleanup_verified=$cleanup -and $process.HasExited -and $ownedEmpty}
    } finally {if($writer){$writer.Dispose()};if($job){$job.Dispose()};$process.Dispose()}
}

function Read-E2EEvents([string]$Text) {
    $events=[Collections.Generic.List[object]]::new()
    foreach($line in ($Text -split '\r?\n')){if(-not [string]::IsNullOrWhiteSpace($line)){try{$events.Add(($line | ConvertFrom-Json -AsHashtable -Depth 100))}catch{throw 'Invalid exec JSONL event'}}}
    return $events.ToArray()
}
function Read-E2ESharedRollout {
    param([string]$Path,[switch]$HeaderOnly,[int]$MaxBytes=67108864)
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $memory=[IO.MemoryStream]::new()
    try{
        $observedLength=$stream.Length;$limit=[Math]::Min($observedLength,$(if($HeaderOnly){262144}else{$MaxBytes}))
        $buffer=[byte[]]::new(65536)
        while($memory.Length -lt $limit){
            $count=$stream.Read($buffer,0,[int][Math]::Min($buffer.Length,$limit-$memory.Length));if($count -eq 0){break}
            $memory.Write($buffer,0,$count)
            if($HeaderOnly -and [array]::IndexOf($buffer,[byte]10,0,$count) -ge 0){break}
        }
        $bytes=$memory.ToArray();$newline=-1
        if($HeaderOnly){$newline=[array]::IndexOf($bytes,[byte]10)}else{for($i=$bytes.Length-1;$i -ge 0;$i--){if($bytes[$i] -eq 10){$newline=$i;break}}}
        $text=if($newline -ge 0){[Text.Encoding]::UTF8.GetString($bytes,0,$newline+1).TrimStart([char]0xfeff)}else{''}
        $complete=$bytes.Length -eq $observedLength -and $stream.Length -eq $observedLength -and $newline -eq $bytes.Length-1
        return @{text=$text;complete=$complete;sha256=if($complete -and -not $HeaderOnly){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()}else{$null};observed_bytes=$observedLength;captured_bytes=$bytes.Length}
    }finally{$memory.Dispose();$stream.Dispose()}
}
function Test-E2ENativeSkillInjection {
    param([string]$Text,[string]$ExpectedPath,[string]$ExpectedContents)
    $answer=@{verified=$false;reason='native selected skill fragment missing or invalid';name=$null;path=$null;contents_sha256=$null}
    $match=[regex]::Match($Text,'(?s)^<skill>\r?\n<name>([^<]+)</name>\r?\n<path>([^<]+)</path>\r?\n(.*)\r?\n</skill>$')
    if(-not $match.Success -or -not $ExpectedPath -or -not $ExpectedContents){return $answer}
    $answer.name=$match.Groups[1].Value;$answer.path=$match.Groups[2].Value
    $answer.contents_sha256=Get-E2EHash $match.Groups[3].Value
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    try{$pathMatches=[string]::Equals([IO.Path]::GetFullPath($answer.path),[IO.Path]::GetFullPath($ExpectedPath),$comparison)}catch{return $answer}
    if($answer.name -cne 'controlflow-codex:controlflow' -or -not $pathMatches -or $match.Groups[3].Value -cne $ExpectedContents){$answer.reason='native selected entry identity, path or complete contents mismatch';return $answer}
    $answer.verified=$true;$answer.reason='native SDK selected entry matches immutable snapshot'
    return $answer
}
function Get-E2ETrialPrompt {
    param([hashtable]$Case,[string]$Variant)
    $prefix=if($Variant -eq 'v3'){'$controlflow-codex:controlflow '}else{''}
    return $prefix+$Case.task+"`nReturn the requested final JSON. If a product choice is required, use status needs_clarification with the actual question and a stable question_id. Never invent an answer. Mark a lawful stop blocked or cancelled. Commit only when this task explicitly asks for a commit."
}
function Write-E2EProcessReceipt {
    param([hashtable]$Capture,[string]$Path)
    $receipt=[ordered]@{}
    foreach($key in @('exit_code','wall_ms','timed_out','budget_reason','streams_complete','cleanup_verified')){$receipt[$key]=$Capture[$key]}
    $receipt.stdout_bytes=[Text.Encoding]::UTF8.GetByteCount($Capture.stdout);$receipt.stderr_bytes=[Text.Encoding]::UTF8.GetByteCount($Capture.stderr)
    Write-E2EText $Path ($receipt | ConvertTo-Json)
}
function Get-E2EUsage {
    param([string]$SessionRoot,[string]$RootSession,[string]$FixtureRoot,[datetime]$Since,[string]$Model='',[string]$Effort='',[string]$ExpectedCliVersion='', [string]$ExpectedApproval='', [string]$ExpectedReviewer='', [string]$ExpectedSandbox='', [string]$Variant='native',[string]$ExpectedEntryPath='',[string]$ExpectedEntryContents='')
    $records=@{};$missing=[Collections.Generic.List[string]]::new()
    if(-not (Test-Path -LiteralPath $SessionRoot)){return @{complete=$false;reason='session usage directory missing';total_tokens=0;tool_calls=0;sessions=@()}}
    foreach($file in Get-ChildItem -LiteralPath $SessionRoot -Recurse -Filter *.jsonl -File | Where-Object {$_.LastWriteTimeUtc -ge $Since.AddSeconds(-3)}){
        try {
            $header=Read-E2ESharedRollout -Path $file.FullName -HeaderOnly
            $first=$header.text.Trim() | ConvertFrom-Json -AsHashtable -Depth 100
            if($first.type -ne 'session_meta'){continue}
            $meta=$first.payload;$id=[string]$meta.id
            $parent=[string]$meta.parent_thread_id
            if(-not $parent -and $meta.source -is [hashtable]){$parent=[string]$meta.source.subagent.thread_spawn.parent_thread_id}
            # Do not parse or retain unrelated transcript content.
            $records[$id]=@{id=$id;parent=$parent;meta=$meta;path=$file.FullName;usage=$null;calls=@{};spawn_count=0;completed=$false;model=$null;effort=$null;approval=$null;reviewer=$null;sandbox=$null;catalog_present=$false;sampling_observed=$false;selected_skills=[Collections.Generic.List[string]]::new();skill_names=[Collections.Generic.List[string]]::new()}
        }catch{}
    }
    $selected=@{};$queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($RootSession)
    while($queue.Count -gt 0){
        $id=$queue.Dequeue();if($selected.ContainsKey($id)){continue}
        if(-not $records.ContainsKey($id)){$missing.Add("rollout:$id");continue}
        $r=$records[$id];$selected[$id]=$r
        foreach($child in $records.Values | Where-Object parent -eq $id){$queue.Enqueue($child.id)}
        try{$snapshot=Read-E2ESharedRollout -Path $r.path}catch{$missing.Add("unreadable-rollout:$id");continue}
        $r.snapshot_sha256=$snapshot.sha256
        if(-not $snapshot.complete){$missing.Add("partial-rollout-snapshot:$id")}
        foreach($line in ($snapshot.text -split '\r?\n' | Where-Object {$_ -ne ''})){
            try{$row=$line | ConvertFrom-Json -AsHashtable -Depth 100}catch{$missing.Add("malformed-rollout:$id");continue}
            $p=$row.payload
            if(($row.type -eq 'response_item' -and ($p.role -eq 'assistant' -or $p.type -in @('function_call','custom_tool_call'))) -or ($row.type -eq 'event_msg' -and $p.type -in @('token_count','task_complete'))){$r.sampling_observed=$true}
            if($row.type -eq 'response_item' -and $p.type -eq 'message' -and $p.role -eq 'user'){foreach($part in $p.content){if($part.text -match '^<skill>'){$r.selected_skills.Add([string]$part.text)}}}
            if($row.type -eq 'event_msg' -and $p.type -eq 'token_count' -and $p.info.total_token_usage){$r.usage=$p.info.total_token_usage}
            if($row.type -eq 'event_msg' -and $p.type -eq 'task_complete'){$r.completed=$true}
            if($row.type -eq 'response_item' -and $p.type -in @('function_call','custom_tool_call')){
                $call=[string]$p.call_id;if(-not $call){$call=Get-E2EHash $line};$r.calls[$call]=[string]$p.name
            }
            if($row.type -eq 'turn_context'){$r.model=$p.model;$r.effort=$p.effort;$r.approval=$p.approval_policy;$r.reviewer=$p.approvals_reviewer;$r.sandbox=$p.sandbox_policy.type}
            if($row.type -eq 'response_item' -and $p.type -eq 'message' -and $p.role -eq 'developer'){
                foreach($part in $p.content){
                    if($part.text -match 'Available skills'){
                        $r.catalog_present=$true
                        foreach($match in [regex]::Matches($part.text,'(?m)^- ([-A-Za-z0-9_:]+):')){$r.skill_names.Add($match.Groups[1].Value)}
                    }
                }
            }
        }
        $r.spawn_count=@($r.calls.Values | Where-Object {$_ -match '(^|__|\.)spawn_agent$'}).Count
    }
    $total=0L;$input=0L;$output=0L;$cached=0L;$tools=0;$provenance=[Collections.Generic.List[object]]::new();$actualContext=$null
    foreach($r in $selected.Values){
        if($r.id -eq $RootSession){
            $contextFailures=[Collections.Generic.List[string]]::new()
            if([IO.Path]::GetFullPath([string]$r.meta.cwd) -cne [IO.Path]::GetFullPath($FixtureRoot)){$missing.Add('root-cwd-mismatch');$contextFailures.Add('cwd-mismatch')}
            if($ExpectedCliVersion -and $r.meta.cli_version -ne $ExpectedCliVersion){$missing.Add('root-version-mismatch');$contextFailures.Add('version-mismatch')}
            if($Model -and $r.model -ne $Model){$missing.Add('root-model-unverified');$contextFailures.Add('model-mismatch')}
            if($Effort -and $r.effort -ne $Effort){$missing.Add('root-effort-unverified');$contextFailures.Add('effort-mismatch')}
            if($ExpectedApproval -and $r.approval -ne $ExpectedApproval){$missing.Add('native-approval-policy-mismatch');$contextFailures.Add('approval-policy')}
            if($ExpectedReviewer -and $r.reviewer -ne $ExpectedReviewer){$missing.Add('native-approval-reviewer-mismatch');$contextFailures.Add('approvals-reviewer')}
            if($ExpectedSandbox -and $r.sandbox -ne $ExpectedSandbox){$missing.Add('native-sandbox-policy-mismatch');$contextFailures.Add('sandbox-policy')}
            $names=@($r.skill_names | Sort-Object -Unique)
            foreach($name in $names){
                $builtin=$name -in @('imagegen','openai-docs','skill-creator','skill-installer')
                $controlflow=$name -match '^(?:controlflow-codex:)?controlflow(?:-plan|-verify|-review)?$'
                if(-not $builtin -and -not ($Variant -eq 'v3' -and $controlflow)){$contextFailures.Add("ambient-skill:$name")}
            }
            if(-not $r.catalog_present){$contextFailures.Add('actual-skill-catalog-unverified')}
            $entryProof=@{verified=$false;reason='native selected entry unavailable'}
            foreach($fragment in $r.selected_skills){
                if($Variant -eq 'native'){$contextFailures.Add('unexpected-native-skill-injection');continue}
                $proof=Test-E2ENativeSkillInjection -Text $fragment -ExpectedPath $ExpectedEntryPath -ExpectedContents $ExpectedEntryContents
                if($proof.verified){$entryProof=$proof}else{$contextFailures.Add('unexpected-or-mismatched-selected-skill')}
            }
            if($Variant -eq 'v3' -and -not $entryProof.verified){$contextFailures.Add('actual-v3-entry-unavailable')}
            if($contextFailures.Count){$missing.Add('actual-context:'+($contextFailures -join ','))}
            $actualContext=@{verified=$contextFailures.Count -eq 0;source='native-exec-rollout';session_id=$r.id;model=$r.model;effort=$r.effort;approval_policy=$r.approval;approvals_reviewer=$r.reviewer;sandbox=$r.sandbox;catalog_present=$r.catalog_present;skill_names=$names;entry_injection=$entryProof;entry_injection_pending=$Variant -eq 'v3' -and -not $entryProof.verified -and -not $r.sampling_observed;failures=$contextFailures.ToArray();rollout_sha256=$r.snapshot_sha256}
        } elseif(-not $r.completed){$missing.Add("child-not-completed:$($r.id)")}
        if(@($selected.Values | Where-Object parent -eq $r.id).Count -lt $r.spawn_count){$missing.Add("child-rollout-missing:$($r.id)")}
        $u=$r.usage;$valid=$true
        foreach($field in @('input_tokens','output_tokens','total_tokens')){if($null -eq $u -or -not ($u[$field] -is [long] -or $u[$field] -is [int]) -or $u[$field] -lt 0){$valid=$false}}
        if($valid -and $u.total_tokens -ne ($u.input_tokens+$u.output_tokens)){$valid=$false}
        if(-not $valid){$missing.Add("usage:$($r.id)");continue}
        $input+=$u.input_tokens;$output+=$u.output_tokens;$total+=$u.total_tokens
        if($u.cached_input_tokens -is [long] -or $u.cached_input_tokens -is [int]){$cached+=$u.cached_input_tokens;if($u.cached_input_tokens -gt $u.input_tokens){$missing.Add('invalid-cached-usage')}}
        $tools+=$r.calls.Count
        $provenance.Add(@{id=$r.id;parent=$r.parent;input_tokens=$u.input_tokens;output_tokens=$u.output_tokens;total_tokens=$u.total_tokens;tool_calls=$r.calls.Count;rollout_sha256=$r.snapshot_sha256})
    }
    return @{complete=$missing.Count -eq 0 -and $selected.Count -gt 0;reason=$missing -join ';';input_tokens=$input;output_tokens=$output;cached_input_tokens=$cached;total_tokens=$total;tool_calls=$tools;sessions=$provenance.ToArray();actual_context=$actualContext}
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
    $args.Add('-c');$args.Add('plugins.controlflow-codex@'+$marketplace+'.enabled='+ $(if($Config.Variant -eq 'v3'){'true'}else{'false'}))
    return $args.ToArray()
}

function Get-E2EDiscoveryArguments([hashtable]$Config) {
    return @('--no-daemon','plugin','list','--json','--available','--marketplace',(Get-E2EMarketplaceName $Config))+@(Get-E2EConfigArguments $Config)
}
function Test-E2EPluginDiscovery {
    param([hashtable]$Capture,[hashtable]$Config)
    $identity='controlflow-codex@'+(Get-E2EMarketplaceName $Config)
    $answer=@{verified=$false;plugin_identity=$identity;reason='incomplete discovery process';record=$null}
    if($Capture.exit_code -ne 0 -or $Capture.timed_out -or -not $Capture.streams_complete -or -not $Capture.cleanup_verified){return $answer}
    try{
        $document=$Capture.stdout | ConvertFrom-Json -AsHashtable -Depth 100
        $records=@((@($document.installed)+@($document.available)) | Where-Object {$_.pluginId -ceq $identity})
        if($records.Count -ne 1){$answer.reason='discovery requires exactly one declared candidate';return $answer}
        $record=$records[0];$answer.record=$record
        if($record.marketplaceName -cne (Get-E2EMarketplaceName $Config) -or $record.installed -isnot [bool] -or $record.enabled -isnot [bool]){$answer.reason='invalid declared plugin state';return $answer}
        if($record.source.source -cne 'local' -or $record.source.path -isnot [string] -or [string]::IsNullOrWhiteSpace($record.source.path)){$answer.reason='candidate source must be explicit local path';return $answer}
        $expected=[IO.Path]::GetFullPath((Join-Path $Config.MarketplaceRoot 'plugins/controlflow-codex'))
        $actual=[IO.Path]::GetFullPath($record.source.path)
        $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
        if(-not [string]::Equals($expected,$actual,$comparison)){$answer.reason='candidate discovery source mismatch';return $answer}
        if($Config.Variant -eq 'v3' -and (-not $record.installed -or -not $record.enabled)){$answer.reason='v3 requires native cache installation and explicit enablement before generation';return $answer}
        if($Config.Variant -eq 'native' -and $record.enabled){$answer.reason='native candidate must be disabled before generation';return $answer}
        $answer.verified=$true;$answer.reason='declared native discovery state verified; actual exec catalog verification remains required'
    }catch{$answer.reason='invalid discovery JSON or source path'}
    return $answer
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
    [IO.Directory]::CreateDirectory($TrialDirectory) | Out-Null
    $result=@{schema_version='1.0.0';case_id=$Case.id;tier=$Case.tier;variant=$Config.Variant;status='incomplete';reason='not-run';session_id=$null;resumes=0;usage=$null;outcome=$null;false_completion=$false;wall_ms=0;generation_started=$false;api_rejected_before_generation=$false;configuration_rejected_before_generation=$false;spend_status='unknown';provenance=@{project_trust='untrusted';model=$Config.Model;effort=$Config.Effort;host=$Config.HostLabel;cli_version=$Config.ExpectedCliVersion;settings=$Config.Settings;sandbox=$Config.Sandbox;windows_sandbox=$Config.WindowsSandbox;approval_policy=$Config.ApprovalPolicy;approvals_reviewer=$Config.ApprovalReviewer;marketplace_name=(Get-E2EMarketplaceName $Config);plugin_identity=('controlflow-codex@'+(Get-E2EMarketplaceName $Config));budget=@{tokens=$Config.MaxTokens;tools=$Config.MaxToolCalls;wall_seconds=$Config.MaxWallSeconds};plugin_sha256=$Config.PluginDigest}}
    $clock=[Diagnostics.Stopwatch]::StartNew();$fixture=$null;$session='';$started=[datetime]::UtcNow
    try {
        foreach($key in @('Model','Effort','HostLabel','ExpectedCliVersion','CliPath','SessionRoot')){if(-not $Config[$key]){throw "Explicit $key required"}}
        foreach($key in @('MaxTokens','MaxToolCalls','MaxWallSeconds')){if($Config[$key] -le 0){throw "Positive explicit $key budget required"}}
        Assert-E2ENativePolicy $Config
        $version=Invoke-E2EProcess -Executable $Config.CliPath -Arguments (@($Config.CliPrefix)+@('--version')) -WorkingDirectory $TrialDirectory -TimeoutSeconds 10 -Environment $Config.Environment
        Write-E2EProcessReceipt -Capture $version -Path (Join-Path $TrialDirectory 'raw/version.process.json')
        if($version.exit_code -ne 0 -or -not $version.streams_complete -or -not $version.cleanup_verified -or $version.stdout.Trim() -cne ('codex-cli '+$Config.ExpectedCliVersion)){throw 'CLI version mismatch or incomplete process collection'}
        $fixture=New-E2EFixture -Case $Case -Directory (Join-Path $TrialDirectory 'repo')
        $result.provenance.fixture_hash=$fixture.fixture_hash
        $result.provenance.initial_commit=$fixture.baseline
        $schema=Join-Path $TrialDirectory 'response-schema.json'
        @{type='object';properties=@{status=@{type='string';enum=@('done','needs_clarification','blocked','cancelled')};question_id=@{type='string'};question=@{type='string'};summary=@{type='string'}};required=@('status','question_id','question','summary');additionalProperties=$false} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $schema -Encoding utf8
        $prompt=Get-E2ETrialPrompt -Case $Case -Variant $Config.Variant
        $allEvents=[Collections.Generic.List[object]]::new()
        $maxResumes=if($null -eq $Config.MaxResumes){2}else{$Config.MaxResumes}
        for($turn=0;$turn -le $maxResumes;$turn++){
            $remaining=$Config.MaxWallSeconds-$clock.Elapsed.TotalSeconds
            if($remaining -le 0){throw 'timeout: total trial wall budget'}
            $argv=@(Get-E2EExecArguments -Config $Config -Schema $schema -Session $session -FixtureRoot $fixture.root)
            $raw=Join-Path $TrialDirectory "raw/turn-$turn.jsonl"
            Write-E2EText (Join-Path $TrialDirectory "raw/turn-$turn.argv.json") ($argv | ConvertTo-Json)
            $observationState=@{last=[datetime]::MinValue}
            $observe={
                param($text)
                if(([datetime]::UtcNow-$observationState.last).TotalSeconds -lt 1){return ''}
                $observationState.last=[datetime]::UtcNow
                try{
                    $seen=@(Read-E2EEvents $text | Where-Object type -eq 'thread.started')
                    if($seen.Count -gt 0){$id=$seen[0].thread_id;$live=Get-E2EUsage -SessionRoot $Config.SessionRoot -RootSession $id -FixtureRoot $fixture.root -Since $started -Model $Config.Model -Effort $Config.Effort -ExpectedApproval $Config.ApprovalPolicy -ExpectedReviewer $Config.ApprovalReviewer -ExpectedSandbox $Config.Sandbox -Variant $Config.Variant -ExpectedEntryPath $Config.NativeEntryPath -ExpectedEntryContents $Config.NativeEntryContents
                        $definiteFailures=@($live.actual_context.failures | Where-Object {$_ -ne 'actual-v3-entry-unavailable' -or -not $live.actual_context.entry_injection_pending})
                        if($live.actual_context.catalog_present -and $live.actual_context.model -and $live.actual_context.approval_policy -and $live.actual_context.sandbox -and $definiteFailures.Count){return 'actual native exec context mismatch: '+($definiteFailures -join ',')}
                        if($live.total_tokens -gt $Config.MaxTokens){return 'token budget exceeded'}
                        if($live.tool_calls -gt $Config.MaxToolCalls){return 'tool budget exceeded'}
                    }
                }catch{}
                return ''
            }
            $capture=Invoke-E2EProcess -Executable $Config.CliPath -Arguments $argv -WorkingDirectory $fixture.root -TimeoutSeconds $remaining -Environment $Config.Environment -InputText $prompt -RawPath $raw -Observe $observe
            Write-E2EProcessReceipt -Capture $capture -Path (Join-Path $TrialDirectory "raw/turn-$turn.process.json")
            Write-E2EText (Join-Path $TrialDirectory "raw/turn-$turn.stderr.txt") $capture.stderr
            # Native thread.started is retained even when the process fails.
            # A malformed later event never erases an already emitted UUID.
            $events=[Collections.Generic.List[object]]::new();$invalidEvent=$false
            foreach($line in ($capture.stdout -split '\r?\n')){if(-not [string]::IsNullOrWhiteSpace($line)){try{$events.Add(($line | ConvertFrom-Json -AsHashtable -Depth 100))}catch{$invalidEvent=$true}}}
            $ids=@($events | Where-Object type -eq 'thread.started' | ForEach-Object thread_id | Select-Object -Unique)
            $parsedId=[guid]::Empty
            if($ids.Count -eq 1 -and [guid]::TryParse([string]$ids[0],[ref]$parsedId)){
                if($session -and $ids[0] -cne $session){throw 'resume session mismatch'}
                $session=[string]$ids[0];$result.session_id=$session
                $result.usage=Get-E2EUsage -SessionRoot $Config.SessionRoot -RootSession $session -FixtureRoot $fixture.root -Since $started -Model $Config.Model -Effort $Config.Effort -ExpectedCliVersion $Config.ExpectedCliVersion -ExpectedApproval $Config.ApprovalPolicy -ExpectedReviewer $Config.ApprovalReviewer -ExpectedSandbox $Config.Sandbox -Variant $Config.Variant -ExpectedEntryPath $Config.NativeEntryPath -ExpectedEntryContents $Config.NativeEntryContents
            }
            if(@($events | Where-Object {$_.type -match '^item\.' -or $_.type -eq 'turn.completed'}).Count -gt 0 -or $result.usage.total_tokens -gt 0){$result.generation_started=$true}
            if($turn -eq 0 -and $capture.exit_code -eq 2 -and -not $capture.timed_out -and $capture.streams_complete -and $capture.cleanup_verified -and $capture.stdout.Length -eq 0 -and $events.Count -eq 0 -and $capture.stderr -match '(?m)^error:' -and $capture.stderr -match '(?m)^Usage:'){
                $result.configuration_rejected_before_generation=$true;$result.spend_status='not-generated-cli-parser-rejection'
                throw 'CLI parser rejected configuration before generation; attempt excluded from model-trial count'
            }
            $stdinGuard='^Failed to read prompt from stdin: input is not valid UTF-8 \(invalid byte at offset [0-9]+\)\. '+[regex]::Escape('Convert it to UTF-8 and retry (e.g., `iconv -f <ENC> -t UTF-8 prompt.txt`).')+'$'
            if($turn -eq 0 -and $capture.exit_code -eq 1 -and -not $capture.timed_out -and $capture.streams_complete -and $capture.cleanup_verified -and $capture.stdout.Length -eq 0 -and $events.Count -eq 0 -and $capture.stderr.Trim() -cmatch $stdinGuard){
                $result.configuration_rejected_before_generation=$true;$result.spend_status='not-generated-cli-stdin-rejection'
                throw 'CLI rejected non-UTF8 stdin before generation; attempt excluded from model-trial count'
            }
            if(($capture.exit_code -ne 0 -or $capture.timed_out -or $capture.budget_reason -or -not $capture.streams_complete -or -not $capture.cleanup_verified) -and $result.usage){
                # Keep published spend, but an aborted native turn may still
                # have unreported in-flight usage. Do not budget from a false
                # assertion of complete accounting.
                $result.usage.complete=$false
                $result.usage.reason+=';native turn terminated without verified final accounting'
            }
            if($capture.exit_code -ne 0 -and $turn -eq 0 -and -not $invalidEvent -and -not $result.generation_started){
                foreach($event in $events | Where-Object type -eq 'turn.failed'){
                    try{$failure=$event.error.message | ConvertFrom-Json -AsHashtable;if($failure.status -eq 400 -and $failure.error.type -eq 'invalid_request_error'){$result.api_rejected_before_generation=$true;$result.spend_status='not-generated-api-rejection'}}catch{}
                }
                if($result.api_rejected_before_generation){throw 'API invalid-request400 rejected before generation; attempt excluded from model-trial count'}
            }
            if($capture.timed_out){throw 'timeout: process lifetime budget'}
            if(-not $capture.streams_complete -or -not $capture.cleanup_verified){throw 'incomplete process stream collection or cleanup'}
            if($capture.budget_reason){throw $capture.budget_reason}
            if($capture.exit_code -ne 0){throw "native process exit $($capture.exit_code)"}
            if($invalidEvent){throw 'Invalid exec JSONL event'}
            foreach($event in $events){$allEvents.Add($event)}
            if($ids.Count -ne 1 -or -not $session){throw 'trusted exact session id missing'}
            $usage=$result.usage
            $result.usage=$usage
            if(-not $usage.complete){throw "usage incomplete: $($usage.reason)"}
            $result.spend_status='verified-native-telemetry'
            $completed=@($events | Where-Object type -eq 'turn.completed')
            if($completed.Count -ne 1 -or $null -eq $completed[0].usage){throw 'turn usage event missing or ambiguous'}
            if($usage.total_tokens -gt $Config.MaxTokens -or $usage.tool_calls -gt $Config.MaxToolCalls){throw 'usage budget exceeded'}
            $messages=@($events | Where-Object {$_.type -eq 'item.completed' -and $_.item.type -eq 'agent_message'})
            if($messages.Count -eq 0){throw 'final structured response missing'}
            try{$reply=$messages[-1].item.text | ConvertFrom-Json -AsHashtable}catch{throw 'final structured response invalid'}
            if($reply.status -eq 'needs_clarification'){
                $answer=$Case.answers[$reply.question_id]
                if(-not $reply.question){throw 'unmatched required clarification'}
                if(-not $answer -or $reply.question -notmatch $answer.pattern){
                    $matches=@($Case.answers.Values | Where-Object {$reply.question -match $_.pattern})
                    if($matches.Count -ne 1){throw 'unmatched or ambiguous required clarification'}
                    $answer=$matches[0]
                }
                if($turn -ge $maxResumes){throw 'clarification resume budget exhausted'}
                $prompt=[string]$answer.answer;$result.resumes++;continue
            }
            if($reply.status -ne 'done'){throw "lawful stop: $($reply.status)"}
            if($Case.requires_clarification -and $result.resumes -eq 0){throw 'required product clarification was bypassed'}
            $result.outcome=Test-E2EOutcome -Case $Case -Fixture $fixture
            $result.status=if(-not $result.outcome.collection_complete){'incomplete'}elseif($result.outcome.pass){'success'}else{'failed'}
            $result.reason=if($result.outcome.pass){'repository outcome verified'}else{$result.outcome.failures -join ';'}
            $result.false_completion=-not $result.outcome.pass
            break
        }
    } catch { $result.reason=$_.Exception.Message }
    finally {
        if($session -and $fixture -and $null -eq $result.usage){try{$result.usage=Get-E2EUsage -SessionRoot $Config.SessionRoot -RootSession $session -FixtureRoot $fixture.root -Since $started}catch{}}
        $result.wall_ms=$clock.ElapsedMilliseconds
        $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $TrialDirectory 'result.json') -Encoding utf8
    }
    return $result
}

function Get-E2EMedian([double[]]$Values) {
    if(-not $Values.Count){return $null};$s=@($Values | Sort-Object);$n=$s.Count
    if($n % 2){return $s[[int][Math]::Floor($n/2)]};return ($s[$n/2-1]+$s[$n/2])/2
}
function Measure-E2EArmCounts {
    param([object[]]$Results,[int]$RequestedCount)
    $api=@($Results | Where-Object api_rejected_before_generation).Count
    $config=@($Results | Where-Object configuration_rejected_before_generation).Count
    $rejected=@($Results | Where-Object {$_.api_rejected_before_generation -or $_.configuration_rejected_before_generation}).Count
    $runs=$Results.Count-$rejected
    return @{requested_count=$RequestedCount;attempt_count=$Results.Count;run_count=$runs;rejected_attempt_count=$rejected;api_rejected_attempt_count=$api;configuration_rejected_attempt_count=$config;unrun_count=[Math]::Max(0,$RequestedCount-$runs)}
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
    param([object[]]$Results)
    $groups=@{};$pairs=[Collections.Generic.List[object]]::new();$unpaired=0;$incomplete=0
    $rejected=@($Results | Where-Object {$_.api_rejected_before_generation -or $_.configuration_rejected_before_generation})
    $Results=@($Results | Where-Object {-not $_.api_rejected_before_generation -and -not $_.configuration_rejected_before_generation})
    $Results=@(foreach($r in $Results){$copy=@{};foreach($key in $r.Keys){$copy[$key]=$r[$key]};$valid=Test-E2EResultEnvelope $r;$copy.envelope_complete=$valid;if(-not $valid){$copy.status='incomplete'};$copy})
    foreach($r in $Results){
        if($r.variant -notin @('native','v3') -or $r.case_id -isnot [string] -or [string]::IsNullOrWhiteSpace($r.case_id) -or $r.tier -notin @('TRIVIAL','SMALL','MEDIUM','LARGE','TRAP','CRITICAL_DIAGNOSTIC') -or ($r.trial -isnot [int] -and $r.trial -isnot [long]) -or $r.trial -lt 1){throw 'Invalid paired result identity'}
        $key=$r.case_id+'|'+$r.trial
        if(-not $groups.ContainsKey($key)){$groups[$key]=@{}}
        if($groups[$key].ContainsKey($r.variant)){throw 'Duplicate case/trial/variant result'}
        $groups[$key][$r.variant]=$r
    }
    foreach($key in $groups.Keys | Sort-Object){
        $g=$groups[$key];if(-not $g.ContainsKey('native') -or -not $g.ContainsKey('v3')){$unpaired++;continue}
        $n=$g.native;$v=$g.v3
        if((Test-E2EProvenance $n.provenance) -and (Test-E2EProvenance $v.provenance)){
        foreach($field in @('model','effort','host','fixture_hash','project_trust','sandbox','windows_sandbox','approval_policy','approvals_reviewer','cli_version')){if($n.provenance[$field] -cne $v.provenance[$field]){throw "Pair $key has mismatched $field provenance"}}
        foreach($field in @('settings','budget')){
            if($field -eq 'budget'){foreach($b in @('tokens','tools','wall_seconds')){if($n.provenance.budget[$b] -ne $v.provenance.budget[$b]){throw "Pair $key has mismatched $b budget"}}}
            elseif(($n.provenance.settings -join "`n") -cne ($v.provenance.settings -join "`n")){throw "Pair $key has mismatched settings"}
        }
        if($n.tier -ne $v.tier){throw "Pair $key has mismatched tier"}
        }
        $metrics=$n.envelope_complete -and $v.envelope_complete
        if(-not $metrics){$incomplete++}
        $pairs.Add(@{case_id=$n.case_id;trial=$n.trial;tier=$n.tier;native=$n;v3=$v;metrics_complete=$metrics;success_delta=if($metrics){[int]($v.status -eq 'success')-[int]($n.status -eq 'success')}else{$null}})
    }
    $clusters=@($pairs | Group-Object case_id);$tierMetrics=@{}
    foreach($tier in @('TRIVIAL','SMALL','MEDIUM','LARGE','TRAP')){
        $p=@($pairs | Where-Object tier -eq $tier);$m=@($p | Where-Object metrics_complete)
        $nm=Get-E2EMedian @($m | ForEach-Object {$_.native.usage.total_tokens});$vm=Get-E2EMedian @($m | ForEach-Object {$_.v3.usage.total_tokens})
        $tierMetrics[$tier]=@{paired_count=$p.Count;metric_pair_count=$m.Count;native_success_count=@($p | Where-Object {$_.native.status -eq 'success' -and $_.native.usage.complete}).Count;v3_success_count=@($p | Where-Object {$_.v3.status -eq 'success' -and $_.v3.usage.complete}).Count;native_median_tokens=$nm;v3_median_tokens=$vm;median_token_overhead=if($null -ne $nm -and $nm -gt 0){$vm/$nm-1}else{$null}}
    }
    $measuredClusters=@($pairs | Where-Object metrics_complete | Group-Object case_id)
    $clusterDeltas=@($measuredClusters | ForEach-Object {($_.Group | Measure-Object success_delta -Average).Average})
    $interval=$null
    if($measuredClusters.Count -gt 1){
        $rng=[Random]::new(923);$samples=[Collections.Generic.List[double]]::new()
        for($i=0;$i -lt 2000;$i++){$s=0.;for($j=0;$j -lt $measuredClusters.Count;$j++){$s+=$clusterDeltas[$rng.Next($measuredClusters.Count)]};$samples.Add($s/$measuredClusters.Count)}
        $sorted=@($samples | Sort-Object);$interval=@($sorted[49],$sorted[1949])
    }
    $nf=@($pairs | Where-Object {$_.native.false_completion -eq $true}).Count;$vf=@($pairs | Where-Object {$_.v3.false_completion -eq $true}).Count
    $absolute=@{}
    foreach($arm in @('native','v3')){$a=@($Results | Where-Object variant -eq $arm);$absolute[$arm]=@{run_count=$a.Count;success_count=@($a | Where-Object {$_.status -eq 'success' -and $_.usage.complete}).Count;failed_count=@($a | Where-Object status -eq 'failed').Count;incomplete_count=@($a | Where-Object {$_.status -eq 'incomplete' -or -not $_.usage.complete}).Count;false_completion_count=@($a | Where-Object {$_.false_completion -eq $true}).Count}}
    return @{schema_version='1.0.0';paired_trials=$pairs.Count;fixture_clusters=$clusters.Count;unpaired_records=$unpaired;rejected_attempt_count=$rejected.Count;incomplete_metrics_pairs=$incomplete;absolute_counts=$absolute;success_delta=if($clusterDeltas.Count){($clusterDeltas | Measure-Object -Average).Average}else{$null};success_delta_fixture_bootstrap_95=$interval;uncertainty_method='2000 fixture-cluster resamples, equal weight per fixture; seed 923; interval unavailable for one cluster';native_false_completions=$nf;v3_false_completions=$vf;false_completion_relative_reduction=if($nf -gt 0){1-$vf/$nf}else{$null};tiers=$tierMetrics;release_sample_complete=$clusters.Count -eq 55 -and @($clusters | Where-Object Count -lt 3).Count -eq 0 -and $unpaired -eq 0 -and $incomplete -eq 0;production_ready=$false}
}
