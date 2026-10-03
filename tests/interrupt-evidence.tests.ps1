. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
$p=Contract $r;$run=Start-ControlFlowRun $r $p 'interrupt-busy';$path=$run.run_path
$lock=[IO.File]::Open((Join-Path $path 'writer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
$watch=[Diagnostics.Stopwatch]::StartNew();$interrupt=Request-ControlFlowInterrupt $r 'interrupt-busy' -TurnId 'native-turn-1';$watch.Stop()
Assert ($interrupt.status -eq 'INTERRUPTED' -and $watch.Elapsed.TotalSeconds -lt 3) 'busy writer interrupt persists within native timeout'
Assert ((Read-ControlFlowRun $r $path).state.status -eq 'INTERRUPTED') 'pending notification projects interrupted status during writer lock'
Assert ('RUN_NOT_ACTIVE' -in (Test-ControlFlowGate $r $path 'Completion').reasons) 'pending interrupt prevents completion'
$raw=Get-Content (Join-Path $path 'state.json') -Raw|ConvertFrom-Json -AsHashtable
Assert ($raw.status -eq 'ACTIVE' -and $raw.revision -eq 0) 'mailbox never pretends to publish certified state'
}finally{$lock.Dispose()}
Throws {Update-ControlFlowRun $r $path @{type='resume'}} 'pending interrupt still requires explicit resume decision'
$resumed=Update-ControlFlowRun $r $path @{type='resume';user_decision_ref='user-message:resume-1'}
Assert ($resumed.state.status -eq 'ACTIVE' -and $resumed.state.acknowledged_interrupt_id -eq $interrupt.interrupt_id) 'explicit resume atomically acknowledges observed notification'
Assert (Test-Path (Join-Path $path 'pending-interrupt.json')) 'ack keeps notification to avoid deletion race'
$next=Request-ControlFlowInterrupt $r 'interrupt-busy' -TurnId 'native-turn-2'
Assert ($next.interrupt_id -ne $interrupt.interrupt_id -and (Read-ControlFlowRun $r $path).state.status -eq 'INTERRUPTED') 'new interrupt after acknowledgment stays pending'
$pending=Join-Path $path 'pending-interrupt.json';$saved=[IO.File]::ReadAllText($pending)
[IO.File]::WriteAllText($pending,'{}')
Throws {Read-ControlFlowRun $r $path} 'corrupt notification fails closed'
Assert ((Test-ControlFlowGate $r $path 'Completion').status -eq 'ERROR') 'corrupt notification cannot produce completion pass'
Throws {Request-ControlFlowInterrupt $r 'interrupt-busy'} 'interrupt cannot silently overwrite corrupt prior notification'
[IO.File]::WriteAllText($pending,$saved)
$v=ConvertFrom-Json -InputObject $saved -AsHashtable;$v.run_id=[guid]::NewGuid().ToString('N');[IO.File]::WriteAllText($pending,($v|ConvertTo-Json -Depth 20))
Throws {Read-ControlFlowRun $r $path} 'foreign run notification rejected'
[IO.File]::WriteAllText($pending,$saved)
$v=ConvertFrom-Json -InputObject $saved -AsHashtable;$v.extra='not declared';[IO.File]::WriteAllText($pending,($v|ConvertTo-Json -Depth 20))
Throws {Read-ControlFlowRun $r $path} 'notification schema rejects unknown fields'
[IO.File]::WriteAllText($pending,$saved)
$sub=Join-Path $r 'nested/cwd';[IO.Directory]::CreateDirectory($sub)|Out-Null
$subInterrupt=Request-ControlFlowInterrupt $sub 'interrupt-busy'
Assert ($subInterrupt.run_path -eq $path) 'native cwd subdirectory resolves canonical active run'
Write-Output "interrupt-evidence busy/ack: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$r=NewFixture
try {
$p=Contract $r 'SMALL' 'none' "[IO.File]::WriteAllText('capture.started','yes'); Start-Sleep -Seconds 3; Write-Output 'finished'"
$run=Start-ControlFlowRun $r $p 'interrupt-capture';$path=$run.run_path
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'});$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
foreach($a in @('-NoProfile','-File',"$PSScriptRoot/core-child.ps1",'-RepoRoot',$r,'-RunPath',$path,'-Action','capture')){$info.ArgumentList.Add($a)}
$child=[Diagnostics.Process]::new();$child.StartInfo=$info;[void]$child.Start()
try{
$deadline=[DateTime]::UtcNow.AddSeconds(15)
while(-not (Test-Path (Join-Path $r 'capture.started')) -and [DateTime]::UtcNow -lt $deadline -and -not $child.HasExited){Start-Sleep -Milliseconds 25}
Assert (Test-Path (Join-Path $r 'capture.started')) 'real capture holds writer before interrupt'
$interrupt=Request-ControlFlowInterrupt $r 'interrupt-capture' -TurnId 'turn-during-capture'
Assert ((Read-ControlFlowRun $r $path).state.status -eq 'INTERRUPTED') 'active capture cannot hide pending interrupt'
Assert ($child.WaitForExit(15000)) 'real capture completes within bounded wait'
Assert ($child.ExitCode -eq 0) ('child capture published normally: '+$child.StandardError.ReadToEnd())
$read=Read-ControlFlowRun $r $path
Assert ($read.state.revision -eq 1 -and $read.state.status -eq 'INTERRUPTED') 'capture old-state publication cannot erase pending guard'
$resumed=Update-ControlFlowRun $r $path @{type='resume';user_decision_ref='user-message:resume-after-capture'}
Assert ($resumed.state.status -eq 'ACTIVE' -and $resumed.state.acknowledged_interrupt_id -eq $interrupt.interrupt_id) 'resume acknowledges notification after capture publication'
}finally{if(-not $child.HasExited){$child.Kill($true)};$child.Dispose()}
Write-Output "interrupt-evidence actual capture: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$r=NewFixture
try {
$p=Contract $r 'SMALL' 'none' "[Console]::Out.Write(('x' * 16777216))";$run=Start-ControlFlowRun $r $p 'interrupt-large';$path=$run.run_path
$capture=Capture-ControlFlowCheck $r $path 'check-1'
Assert ((Get-Item (Join-Path $path $capture.stdout_ref.path)).Length -ge 16777216) 'real large command output exists'
$stream=[IO.File]::Open((Join-Path $path $capture.stdout_ref.path),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
$watch=[Diagnostics.Stopwatch]::StartNew();$interrupt=Request-ControlFlowInterrupt $r 'interrupt-large';$watch.Stop()
Assert ($interrupt.status -eq 'INTERRUPTED' -and $watch.Elapsed.TotalSeconds -lt 3) 'interrupt bypasses even exclusively locked large evidence output within 3 seconds'
Write-Output ("interrupt fast path elapsed_ms="+[math]::Round($watch.Elapsed.TotalMilliseconds))
}finally{$stream.Dispose()}
Assert ((Read-ControlFlowRun $r $path).state.status -eq 'INTERRUPTED') 'large-output run remains interrupted on full verified read'
Write-Output "interrupt-evidence final: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$global:LASTEXITCODE=0
