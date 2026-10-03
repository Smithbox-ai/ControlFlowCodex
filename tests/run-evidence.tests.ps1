. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
$p=Contract $r
$run=Start-ControlFlowRun -RepoRoot $r -ContractPath $p -SessionId 'native-session'
$path=$run.run_path
$read=Read-ControlFlowRun -RepoRoot $r -RunPath $path -SessionId 'native-session'
Assert ($read.state.revision -eq 0) 'initial immutable state revision'
Assert ((Get-ControlFlowActiveRun $r 'native-session').state.run_id -eq $read.state.run_id) 'active session exact binding'
Throws {Read-ControlFlowRun $r $path -SessionId 'other-session'} 'foreign session rejected'
$check=Capture-ControlFlowCheck $r $path 'check-1'
Assert ($check.status -eq 'PASS' -and $check.exit_code -eq 0) 'real successful command captured'
$updated=Update-ControlFlowRun $r $path @{type='coverage';criterion_id='C1';check_ids=@('check-1')} -ExpectedRevision 1
Assert ($updated.state.revision -eq 2) 'atomic revision advanced'
Throws {Update-ControlFlowRun $r $path @{type='preflight';status='APPROVED'} -ExpectedRevision 1} 'stale concurrent revision rejected'
Throws {Update-ControlFlowRun $r $path @{type='check';status='PASS'}} 'model-authored check evidence rejected'
$stateFile=Join-Path $path 'state.json';$state=Get-Content $stateFile -Raw|ConvertFrom-Json -AsHashtable
$evidence=Join-Path $path $state.evidence_ref.path
$old=[IO.File]::ReadAllText($evidence);[IO.File]::WriteAllText($evidence,'{}')
Throws {Read-ControlFlowRun $r $path} 'corrupt immutable evidence fails closed'
[IO.File]::WriteAllText($evidence,$old)
$lock=[IO.File]::Open((Join-Path $path 'writer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{Throws {Update-ControlFlowRun $r $path @{type='preflight';status='APPROVED'}} 'exclusive filehandle writer lock excludes concurrent writer'}finally{$lock.Dispose()}
File $r 'plans/artifacts/test-task/runs/unused-orphan' '{}'
Assert ((Read-ControlFlowRun $r $path).state.revision -eq 2) 'orphan outside published refs cannot change revision'
Update-ControlFlowRun $r $path @{type='stop';reason='INTERRUPT';evidence='native interrupt event'}|Out-Null
Assert ((Read-ControlFlowRun $r $path).state.status -eq 'INTERRUPTED') 'interrupt persisted'
Throws {Update-ControlFlowRun $r $path @{type='resume'}} 'resume needs concrete user decision'
Update-ControlFlowRun $r $path @{type='resume';user_decision_ref='user-message:resume-1'}|Out-Null
Assert ((Read-ControlFlowRun $r $path).state.status -eq 'ACTIVE') 'explicit resume accepted'
for($i=0;$i -lt 3;$i++){Update-ControlFlowRun $r $path @{type='continuation';signature='same'}|Out-Null}
Assert ((Read-ControlFlowRun $r $path).state.status -eq 'BLOCKED') 'third identical continuation is bounded'
Write-Output "run-evidence: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$r=NewFixture
try{
$p=Contract $r 'SMALL' 'none' 'Write-Error failure; exit 7'
$run=Start-ControlFlowRun $r $p 'failure-session'
$c=Capture-ControlFlowCheck $r $run.run_path 'check-1';Assert ($c.status -eq 'FAIL' -and $c.exit_code -eq 7) 'failure capture records actual exit'
$p=Contract $r 'SMALL' 'none' "[IO.File]::WriteAllText('owned.txt','changed')"
$c=Capture-ControlFlowCheck $r $run.run_path 'check-1';Assert ($c.status -eq 'STALE') 'check that mutates source never PASS'
Write-Output "run-evidence total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
function StartFixtureChild([string]$Root,[string]$RunPath,[string]$Action){
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'});$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
foreach($a in @('-NoProfile','-File',"$PSScriptRoot/core-child.ps1",'-RepoRoot',$Root,'-RunPath',$RunPath,'-Action',$Action)){$info.ArgumentList.Add($a)}
$p=[Diagnostics.Process]::new();$p.StartInfo=$info;[void]$p.Start();return $p
}
$r=NewFixture
try {
$p=Contract $r;$run=Start-ControlFlowRun $r $p 'race';$path=$run.run_path
$a=StartFixtureChild $r $path 'update';$b=StartFixtureChild $r $path 'update'
try{$a.WaitForExit();$b.WaitForExit();Assert (@($a.ExitCode,$b.ExitCode|Where-Object {$_ -eq 0}).Count -eq 1) 'two real child writers cannot both publish revision zero';Assert ((Read-ControlFlowRun $r $path).state.revision -eq 1) 'concurrent state contains exactly one event'}finally{$a.Dispose();$b.Dispose()}
$statePath=Join-Path $path 'state.json';$old=[IO.File]::ReadAllBytes($statePath)
if($IsWindows){
$stream=[IO.File]::Open($statePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{Throws {Update-ControlFlowRun $r $path @{type='blocker';id='B2';status='OPEN';text='filesystem fault'}} 'filesystem denies atomic state replacement'}finally{$stream.Dispose()}
}else{
$evidenceDir=Join-Path $path 'evidence';$originalMode=[IO.File]::GetUnixFileMode($evidenceDir)
try{[IO.File]::SetUnixFileMode($evidenceDir,[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserExecute);Throws {Update-ControlFlowRun $r $path @{type='blocker';id='B2';status='OPEN';text='filesystem fault'}} 'filesystem denies evidence publication'}finally{[IO.File]::SetUnixFileMode($evidenceDir,$originalMode)}
}
Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath)) -ceq [Convert]::ToBase64String($old)) 'failed publication leaves coherent old state'
Assert ((Read-ControlFlowRun $r $path).state.revision -eq 1) 'unpublished immutable evidence orphan ignored'
$raw=Get-Content $statePath -Raw|ConvertFrom-Json -AsHashtable
$ref=Join-Path $path $raw.evidence_ref.path;[IO.File]::Move($ref,$ref+'.missing')
Throws {Read-ControlFlowRun $r $path} 'missing published evidence reference blocks read'
[IO.File]::Move($ref+'.missing',$ref)
Write-Output "run-evidence concurrent/fault total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$r=NewFixture
try {
$p=Contract $r 'SMALL' 'none' "[IO.File]::WriteAllText('capture.started','yes'); Start-Sleep -Seconds 60"
$run=Start-ControlFlowRun $r $p 'crash';$path=$run.run_path;$child=StartFixtureChild $r $path 'capture'
try{
$deadline=[DateTime]::UtcNow.AddSeconds(15)
while(-not (Test-Path (Join-Path $r 'capture.started')) -and [DateTime]::UtcNow -lt $deadline -and -not $child.HasExited){Start-Sleep -Milliseconds 50}
Assert (Test-Path (Join-Path $r 'capture.started')) 'real check started before crash injection'
$child.Kill($true);$child.WaitForExit()
Assert ((Read-ControlFlowRun $r $path).state.revision -eq 0) 'killed capture cannot publish partial evidence'
Update-ControlFlowRun $r $path @{type='stop';reason='INTERRUPT';evidence='test killed native process'}|Out-Null
Assert ((Read-ControlFlowRun $r $path).state.status -eq 'INTERRUPTED') 'OS releases writer handle after crashed child'
}finally{if(-not $child.HasExited){$child.Kill($true)};$child.Dispose()}
Write-Output "run-evidence crash total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$r=NewFixture
try {
$p=Contract $r 'SMALL' 'none' 'Start-Sleep -Seconds 5';$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable;$v.checks[0].timeout_seconds=1;[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
$run=Start-ControlFlowRun $r $p 'timeout';$capture=Capture-ControlFlowCheck $r $run.run_path 'check-1'
Assert ($capture.status -eq 'TIMEOUT' -and $capture.timed_out) 'timeout is captured as non-PASS'
$stream=Join-Path $run.run_path $capture.stdout_ref.path;[IO.File]::WriteAllText($stream,'corrupted output')
Throws {Read-ControlFlowRun $r $run.run_path} 'output hash corruption blocks read'
Write-Output "run-evidence final total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$nonGit=Join-Path ([IO.Path]::GetTempPath()) ('cf-core-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($nonGit)|Out-Null
try{Assert ($null -eq (Get-ControlFlowActiveRun $nonGit 'unmanaged')) 'unmanaged projectless session has no active run'}finally{Remove-Item -LiteralPath $nonGit -Recurse -Force}

Write-Output "run-evidence complete: $script:Count assertions passed"
$global:LASTEXITCODE=0

# A native child exit must remain the actual captured exit, not shell-normalized 1.
$r=NewFixture
try {
$pwsh=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$command="& '"+$pwsh.Replace("'","''")+"' -NoProfile -Command 'exit 7'"
$p=Contract $r 'SMALL' 'none' $command;$run=Start-ControlFlowRun $r $p 'native-exit'
$capture=Capture-ControlFlowCheck $r $run.run_path 'check-1'
Assert ($capture.status -eq 'FAIL' -and $capture.exit_code -eq 7) 'native child nonzero exit is captured exactly'
Write-Output "run-evidence native exit total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$global:LASTEXITCODE=0
$r=NewFixture
$outside=Join-Path ([IO.Path]::GetTempPath()) ('cf-core-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($outside)|Out-Null
try {
Throws {Update-ControlFlowRun $r $outside @{type='stop';reason='BLOCKED';evidence='invalid target'}} 'outside repository run rejected'
Assert (-not (Test-Path (Join-Path $outside 'writer.lock'))) 'invalid external run path never creates a lock outside repository'
}finally{foreach($p in @($r,$outside)){if($p -and [IO.Path]::GetFileName($p).StartsWith('cf-core-')){Remove-Item -LiteralPath $p -Recurse -Force}}}
$global:LASTEXITCODE=0
$r=NewFixture
try {
$p=Contract $r;$run=Start-ControlFlowRun $r $p 'directory-pointer'
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('directory-pointer'))).ToLowerInvariant()
$active=Join-Path $r "plans/artifacts/.controlflow/active/$hash.json";[IO.File]::Move($active,$active+'.backup');[IO.Directory]::CreateDirectory($active)|Out-Null
Throws {Get-ControlFlowActiveRun $r 'directory-pointer'} 'directory replacing active pointer is corruption, not absent session'
Write-Output "run-evidence boundary total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$global:LASTEXITCODE=0
