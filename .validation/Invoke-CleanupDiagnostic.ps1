function Invoke-CleanupDiagnostic {
    param([Parameter(Mandatory)][string]$Repo)
    $state=@{contexts=@{};pid_files=@{};errors=[Collections.Generic.List[string]]::new();clock=[Diagnostics.Stopwatch]::StartNew()}
    $gitFile=Join-Path $Repo 'scripts/lib/Git.ps1';$testFile=Join-Path $Repo 'tests/process-timeout.tests.ps1'
    $readFrame={param([string]$Name,[string]$File)
        $frames=@(Get-PSCallStack|Where-Object{($_.FunctionName -ceq $Name -or -not $Name) -and $_.ScriptName -and [IO.Path]::GetFullPath($_.ScriptName) -ceq [IO.Path]::GetFullPath($File)})
        if(-not $frames.Count){throw "STOPPED_FRAME_NOT_FOUND:$Name"}
        $frame=$frames[0];$values=@{}
        foreach($entry in $frame.InvocationInfo.BoundParameters.GetEnumerator()){$values[$entry.Key]=[Management.Automation.PSVariable]::new($entry.Key,$entry.Value)}
        $module=$frame.InvocationInfo.MyCommand.Module
        if($module){
            foreach($name in @('p','group','mainProcessId','drain','cleanupOk','timedOut','processIncomplete','outTask','errTask','stdout','stderr','result','errorNumber','signalResult','snapshot')){
                $variable=$module.SessionState.PSVariable.Get($name);if($null -ne $variable){$values[$name]=$variable}
            }
        }
        return ,$values
    }.GetNewClosure()
    $lineAt={param($Lines,[string]$Text)$hits=@(for($i=0;$i -lt $Lines.Length;$i++){if($Lines[$i].Trim() -ceq $Text){$i+1}});if($hits.Count -ne 1){throw "DIAGNOSTIC_MARKER_NOT_UNIQUE:$Text"};$hits[0]}
    $gitLines=[IO.File]::ReadAllLines($gitFile);$testLines=[IO.File]::ReadAllLines($testFile)
    $points=[Collections.Generic.List[object]]::new();$output=@();$scriptError=$null;$scriptExit=$null
    try {
        $action={try{
            $v=& $readFrame 'Invoke-CFProcess' $gitFile
            if($v.ContainsKey('OwnDescendants') -and $v['OwnDescendants'].Value){
                $owner=$v['p'].Value.Id;$key=[string]$owner
                if($state.contexts.ContainsKey($key)){throw 'OWNED_PID_REUSED'}
                $command=[string]$v['Arguments'].Value[-1]
                $kind=if($command.Contains('spawn-silent.ps1')){'silent'}elseif($command.Contains('spawn-child.ps1')){'inherited'}else{'normal'}
                $pidFile=$null
                if($kind -cne 'normal'){
                    $parsed=[Management.Automation.Language.Parser]::ParseInput($command,[ref]$null,[ref]$null)
                    $commands=@($parsed.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -cin @('./spawn-child.ps1','./spawn-silent.ps1')},$true))
                    if($commands.Count -ne 1 -or $commands[0].CommandElements[1] -isnot [Management.Automation.Language.StringConstantExpressionAst]){throw 'PID_FILE_LITERAL_NOT_PROVEN'}
                    $pidFile=[IO.Path]::GetFullPath($commands[0].CommandElements[1].Value)
                    if(-not $pidFile.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::Ordinal) -or -not [IO.Path]::GetFileName($pidFile).StartsWith('cf-child-')){throw 'PID_FILE_OUTSIDE_OWNED_TEMP'}
                }
                $state.contexts[$key]=@{owner_pid=$owner;directory=$v['Directory'].Value;kind=$kind;pid_file=$pidFile;group_owned=[bool]$v['group'].Value;main_pid=0;descendant_pid=$null;signals=[Collections.Generic.List[object]]::new();snapshots=[Collections.Generic.List[object]]::new();verification_elapsed_ms=$null;final=$null;post_cleanup_snapshot=$null}
            }
        }catch{$state.errors.Add($_.Exception.Message)}}.GetNewClosure()
        $points.Add((Set-PSBreakpoint -Script $gitFile -Line (& $lineAt $gitLines '$started=$true') -Action $action))
        $action={try{
            $v=& $readFrame 'Invoke-CFGroupSignal' $gitFile;$target=$v['GroupId'].Value
            if($state.contexts.ContainsKey([string]$target)){
                $pair=$v['signalResult'].Value
                if($pair.Result -ne $v['result'].Value -or $pair.ErrorNumber -ne $v['errorNumber'].Value){throw 'ATOMIC_SIGNAL_PAIR_MISMATCH'}
                $state.contexts[[string]$target].signals.Add(@{group_id=$target;signal=$v['Signal'].Value;result=$pair.Result;errno=$pair.ErrorNumber;errno_capture='atomic-native-helper';observed_at_utc=[datetime]::UtcNow.ToString('o');observed_elapsed_ms=$state.clock.ElapsedMilliseconds})
            }
        }catch{$state.errors.Add($_.Exception.Message)}}.GetNewClosure()
        $points.Add((Set-PSBreakpoint -Script $gitFile -Line (& $lineAt $gitLines 'return Resolve-CFGroupSignalResult $result $errorNumber') -Action $action))
        $action={try{
            $v=& $readFrame 'Test-CFGroupHasOtherProcess' $gitFile;$target=$v['GroupId'].Value
            if($state.contexts.ContainsKey([string]$target)){
                $ctx=$state.contexts[[string]$target];$ctx.main_pid=$v['MainId'].Value;$ctx.snapshots.Add(@{group_id=$target;bytes=$v['snapshot'].Value.stdout})
                if($ctx.pid_file -and [IO.File]::Exists($ctx.pid_file)){$ctx.descendant_pid=[int][IO.File]::ReadAllText($ctx.pid_file)}
            }
        }catch{$state.errors.Add($_.Exception.Message)}}.GetNewClosure()
        $points.Add((Set-PSBreakpoint -Script $gitFile -Line (& $lineAt $gitLines '$lines=$script:Utf8.GetString($snapshot.stdout) -split ''\r?\n''') -Action $action))
        $ast=[Management.Automation.Language.Parser]::ParseFile($gitFile,[ref]$null,[ref]$null)
        $groupNodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '$group' -and $n.Extent.Text.Contains('$empty=$false') -and $n.Extent.Text.Contains('$drain.ElapsedMilliseconds')},$true))
        if($groupNodes.Count -ne 1){throw 'GROUP_VERIFICATION_BLOCK_AMBIGUOUS'}
        $action={try{
            $v=& $readFrame 'Invoke-CFProcess' $gitFile;$key=[string]$v['p'].Value.Id
            if($state.contexts.ContainsKey($key)){$state.contexts[$key].verification_elapsed_ms=$v['drain'].Value.ElapsedMilliseconds}
        }catch{$state.errors.Add($_.Exception.Message)}}.GetNewClosure()
        $points.Add((Set-PSBreakpoint -Script $gitFile -Line $groupNodes[0].Clauses[0].Item2.Statements[0].Extent.StartLineNumber -Action $action))
        $action={try{
            $v=& $readFrame 'Invoke-CFProcess' $gitFile
            if($v.ContainsKey('OwnDescendants') -and $v['OwnDescendants'].Value){
                $key=[string]$v['p'].Value.Id;if(-not $state.contexts.ContainsKey($key)){throw 'OWNED_START_EVENT_MISSING'}
                $ctx=$state.contexts[$key];$ctx.main_pid=$v['mainProcessId'].Value;$outTask=$v['outTask'].Value;$errTask=$v['errTask'].Value
                $ctx.final=@{cleanup_ok=[bool]$v['cleanupOk'].Value;timed_out=[bool]$v['timedOut'].Value;process_incomplete=[bool]$v['processIncomplete'].Value;stdout_complete=($outTask.IsCompleted -and -not $outTask.IsFaulted);stderr_complete=($errTask.IsCompleted -and -not $errTask.IsFaulted);stdout_base64=[Convert]::ToBase64String($v['stdout'].Value.ToArray());stderr_base64=[Convert]::ToBase64String($v['stderr'].Value.ToArray())}
                # Observe only after the runtime has made its cleanup decision.
                # This observation cannot turn that decision into success.
                $psStart=[Diagnostics.ProcessStartInfo]::new();$psStart.FileName='/bin/ps';$psStart.UseShellExecute=$false;$psStart.RedirectStandardOutput=$true;$psStart.RedirectStandardError=$true
                foreach($arg in @('-axo','pid=,pgid=,stat=')){[void]$psStart.ArgumentList.Add($arg)}
                $psProcess=[Diagnostics.Process]::Start($psStart)
                try {
                    $psOut=$psProcess.StandardOutput.ReadToEndAsync();$psErr=$psProcess.StandardError.ReadToEndAsync()
                    if(-not $psProcess.WaitForExit(1500) -or -not [Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($psOut,$psErr)).Wait(1500) -or $psProcess.ExitCode -ne 0){throw 'POST_CLEANUP_PS_INCOMPLETE'}
                    $rows=@(foreach($row in ($psOut.GetAwaiter().GetResult() -split '\r?\n')){
                        if([string]::IsNullOrWhiteSpace($row)){continue}
                        if($row -notmatch '^\s*(\d+)\s+(\d+)\s+(\S+)\s*$'){throw 'POST_CLEANUP_PS_UNPARSABLE'}
                        $observed=[int]$Matches[1];$pgid=[int]$Matches[2];$status=$Matches[3]
                        if($pgid -eq $ctx.owner_pid){@{pid=$observed;pgid=$pgid;state=$status}}
                    })
                    $ctx.post_cleanup_snapshot=@{stage='after-runtime-cleanup-decision-before-return';observed_at_utc=[datetime]::UtcNow.ToString('o');observed_elapsed_ms=$state.clock.ElapsedMilliseconds;exit_code=$psProcess.ExitCode;complete=$true;group_id=$ctx.owner_pid;processes=$rows}
                } finally {if(-not $psProcess.HasExited){$psProcess.Kill();[void]$psProcess.WaitForExit(1500)};$psProcess.Dispose()}
            }
        }catch{$state.errors.Add($_.Exception.Message)}}.GetNewClosure()
        $points.Add((Set-PSBreakpoint -Script $gitFile -Line (& $lineAt $gitLines 'if(-not $cleanupOk){throw ''PROCESS_CLEANUP_UNVERIFIABLE''}') -Action $action))
        $global:LASTEXITCODE=0
        try {$output=@(& $testFile 2>&1);$scriptExit=$global:LASTEXITCODE}catch{$scriptError=@{message=$_.Exception.ToString();stack=$_.ScriptStackTrace}}
    }finally{if($points.Count){Remove-PSBreakpoint -Breakpoint $points.ToArray()}}
    # Original fixture finally/owned-child cleanup has completed before emission.
    foreach($line in $output){[Console]::WriteLine([string]$line)}
    $records=@(foreach($ctx in $state.contexts.Values){
        $samples=@(foreach($sample in $ctx.snapshots){
            $rows=@(foreach($line in ([Text.Encoding]::UTF8.GetString($sample.bytes) -split '\r?\n')){
                if($line -match '^\s*(\d+)\s+(\d+)\s+(\S+)\s*$'){$observed=[int]$Matches[1];$pgid=[int]$Matches[2];$stateText=$Matches[3];if($pgid -eq $ctx.owner_pid -or $observed -eq $ctx.owner_pid -or $observed -eq $ctx.main_pid -or ($ctx.descendant_pid -and $observed -eq $ctx.descendant_pid)){@{pid=$observed;pgid=$pgid;state=$stateText}}}
            });@{group_id=$sample.group_id;processes=$rows}
        })
        @{owner_pid=$ctx.owner_pid;main_pid=$ctx.main_pid;descendant_pid=$ctx.descendant_pid;kind=$ctx.kind;group_owned=$ctx.group_owned;verification_elapsed_ms=$ctx.verification_elapsed_ms;signal0_probe_count=@($ctx.signals|Where-Object signal -EQ 0).Count;native_signals=$ctx.signals.ToArray();native_ps_snapshots=$samples;final=$ctx.final;post_cleanup_snapshot=$ctx.post_cleanup_snapshot}
    })
    $problems=[Collections.Generic.List[string]]::new()
    if($scriptError -or $scriptExit -ne 0){$problems.Add('NATIVE_SUITE_FAILED')}
    $assertions=@($output|Where-Object{[string]$_ -match '^process timeout: 42 assertions passed$'})
    if($assertions.Count -ne 1){$problems.Add('EXPECTED_42_ASSERTIONS_NOT_OBSERVED')}
    if($state.errors.Count){$problems.Add('DIAGNOSTIC_COLLECTION_ERROR')}
    if($records.Count -ne 8 -or @($records|Where-Object kind -EQ 'normal').Count -ne 6 -or @($records|Where-Object kind -EQ 'inherited').Count -ne 1 -or @($records|Where-Object kind -EQ 'silent').Count -ne 1){$problems.Add('OWNED_CONTEXT_SET_INCOMPLETE')}
    foreach($record in $records){
        $absent=@($record.native_signals|Where-Object{$_.signal -eq 0 -and $_.result -eq -1 -and $_.errno -eq 3})
        if(@($record.native_signals|Where-Object signal -EQ 9).Count -ne 1){$problems.Add('OWNED_TERMINATION_ATTEMPT_MISSING_OR_AMBIGUOUS')}
        if(-not $record.group_owned -or -not $record.final -or -not $record.final.cleanup_ok -or $record.signal0_probe_count -lt 1 -or $absent.Count -lt 1 -or $null -eq $record.verification_elapsed_ms){$problems.Add('OWNED_CLEANUP_NOT_PROVEN')}
        if(-not $record.final.stdout_complete -or -not $record.final.stderr_complete){$problems.Add('STREAMS_INCOMPLETE')}
        if(-not $record.post_cleanup_snapshot -or -not $record.post_cleanup_snapshot.complete -or $record.post_cleanup_snapshot.exit_code -ne 0 -or $record.post_cleanup_snapshot.group_id -ne $record.owner_pid -or @($record.post_cleanup_snapshot.processes).Count){$problems.Add('POST_CLEANUP_GROUP_NOT_CONFIRMED_ABSENT')}
        foreach($signal in $record.native_signals){if($signal.errno_capture -cne 'atomic-native-helper' -or -not $signal.observed_at_utc -or -not $record.post_cleanup_snapshot -or $signal.observed_elapsed_ms -gt $record.post_cleanup_snapshot.observed_elapsed_ms){$problems.Add('ATOMIC_TIMED_SIGNAL_PROVENANCE_MISSING')}}
        if($record.kind -ceq 'silent'){$rows=@($record.native_ps_snapshots|ForEach-Object processes|Where-Object{$_.pid -eq $record.descendant_pid -and $_.pgid -eq $record.owner_pid});if(-not $record.descendant_pid -or $rows.Count -lt 1 -or -not $record.final.process_incomplete){$problems.Add('SILENT_DESCENDANT_IDENTITY_NOT_PROVEN')}}
    }
    $result=@{status=if($problems.Count){if($scriptError -or $scriptExit -ne 0){'FAIL'}else{'INCONCLUSIVE'}}else{'PASS'};assertions=if($assertions.Count){42}else{$null};native_contexts=$records;collection_errors=$state.errors.ToArray();problems=$problems.ToArray();script_error=$scriptError;breakpoint_hits=@($points|ForEach-Object{@{line=$_.Line;hits=$_.HitCount}});historical_failure_causation='NOT_ESTABLISHED';scope='Current fixed candidate native cleanup validation; historical FAIL retained';models=0}
    [Console]::WriteLine('CLEANUP_DIAGNOSTIC_JSON '+($result|ConvertTo-Json -Depth 14 -Compress));return $result
}
