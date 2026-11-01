. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
File $r 'foreign.txt' 'foreign staged';Git $r @('add','foreign.txt')|Out-Null;File $r 'foreign.txt' 'foreign unstaged'
$foreignBefore=Git $r @('ls-files','-s','foreign.txt')
$configBefore=Git $r @('config','--local','--list')
$p=LegacyContract $r 'MEDIUM' 'required' -SessionId 'gate-session'
$run=New-HistoricalV3RunFixture $r $p 'gate-session';$path=$run.run_path
$g=Test-ControlFlowGate $r $path 'Completion';Assert ($g.status -eq 'FAIL') 'missing captures and reviews cannot complete'
Update-ControlFlowRun $r $path @{type='preflight';status='APPROVED'}|Out-Null
File $r 'owned.txt' 'implementation'
Capture-ControlFlowCheck $r $path 'check-1'|Out-Null
Update-ControlFlowRun $r $path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Update-ControlFlowRun $r $path @{type='review';status='APPROVED'}|Out-Null
$g=Test-ControlFlowGate $r $path 'Commit'
Assert ($g.status -eq 'PASS') ('fresh deliverable passes commit gate: '+($g|ConvertTo-Json -Depth 10 -Compress))
Assert ((Git $r @('ls-files','-s','foreign.txt')) -ceq $foreignBefore) 'candidate generation leaves foreign index untouched'
Assert ((Git $r @('config','--local','--list')) -ceq $configBefore) 'external candidate index does not change repository config'
$missingCommit=Test-ControlFlowGate $r $path 'Completion'; Assert ($missingCommit.status -eq 'FAIL') ('required commit must actually exist: '+($missingCommit|ConvertTo-Json -Depth 10))
Git $r @('commit','--only','-qm','scoped commit','--','owned.txt')|Out-Null
$sha=Git $r @('rev-parse','HEAD')
$g=Test-ControlFlowGate $r $path 'Completion' -CommitSha $sha
Assert ($g.status -eq 'PASS') ('actual selective commit passes completion: '+($g.reasons -join ','))
Assert ((Git $r @('ls-files','-s','foreign.txt')) -ceq $foreignBefore) 'selective commit preserves foreign index'
File $r 'owned.txt' 'late edit';$g=Test-ControlFlowGate $r $path 'Completion' -CommitSha $sha
Assert ($g.status -eq 'FAIL' -and 'CHECK_STALE:check-1' -in $g.reasons) 'source mutation stales capture'
File $r 'owned.txt' 'implementation';File $r 'foreign.txt' 'foreign mutation'
Assert ('FOREIGN_WORKTREE_CHANGED:foreign.txt' -in (Test-ControlFlowGate $r $path 'Completion' -CommitSha $sha).reasons) 'foreign dirty path mutation blocks'
Write-Output "gates: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}}
$r=NewFixture
try {
$p=LegacyContract $r 'SMALL' 'none' -SessionId 'small-session';$run=New-HistoricalV3RunFixture $r $p 'small-session';$path=$run.run_path
Capture-ControlFlowCheck $r $path 'check-1'|Out-Null
Update-ControlFlowRun $r $path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Assert ((Test-ControlFlowGate $r $path 'Completion').status -eq 'PASS') 'SMALL uses actual inline capture evidence'
Assert ((Test-ControlFlowGate $r $path 'Commit').status -eq 'FAIL') 'commit not requested never authorized'
Add-Content -LiteralPath $p -Value ' '
Assert ('CHECK_STALE:check-1' -in (Test-ControlFlowGate $r $path 'Completion').reasons) 'exact contract bytes mutation stales evidence'
Throws {Update-ControlFlowRun $r $path @{type='complete'}} 'complete event internally rejects failed gate'
Write-Output "gates total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}}

$r=NewFixture
try {
$p=LegacyContract $r 'SMALL' 'none' -SessionId 'done-session';$run=New-HistoricalV3RunFixture $r $p 'done-session'
Capture-ControlFlowCheck $r $run.run_path 'check-1'|Out-Null
Update-ControlFlowRun $r $run.run_path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
$done=Update-ControlFlowRun $r $run.run_path @{type='complete';status='invented'}
Assert ($done.state.status -eq 'COMPLETED') 'complete publishes only after internally fresh actual completion gate'
File $r 'owned.txt' 'late hook change'
Assert ((Test-ControlFlowGate $r $run.run_path 'Completion').status -eq 'FAIL') 'COMPLETED state alone never bypasses fresh gate'
Write-Output "gates final: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}}
$global:LASTEXITCODE=0
$r=NewFixture
try {
    File $r '.gitignore' 'ignored-root.txt';Git $r @('add','.gitignore')|Out-Null;Git $r @('commit','-qm','ignore input')|Out-Null
    File $r 'ignored-root.txt' 'good';$sub=Join-Path $r 'sub';[IO.Directory]::CreateDirectory($sub)|Out-Null
    $p=LegacyContract $r 'SMALL' 'none' "if ((Get-Content ignored-root.txt) -ne 'good') { throw 'bad' }" 'subdirectory'
    $v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable;$v.checks[0].inputs=@('ignored-root.txt');[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
    $run=New-HistoricalV3RunFixture $sub $p 'subdirectory'
    $capture=Capture-ControlFlowCheck $sub $run.run_path 'check-1'
    Update-ControlFlowRun $sub $run.run_path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
    Assert ($capture.status -eq 'PASS') 'relative check cwd resolves from the Git root even when invoked from a subdirectory'
    File $r 'ignored-root.txt' 'bad'
    $gate=Test-ControlFlowGate $sub $run.run_path 'Completion'
    Assert ('CHECK_STALE:check-1' -in $gate.reasons) 'declared input uses Git root even when invoked from a subdirectory'
    Write-Output "gates subdirectory input: $script:Count assertions passed"
} finally {RemoveFixture $r}
$global:LASTEXITCODE=0
$r=NewFixture
try {
File $r '.gitignore' 'ignored-input.txt';Git $r @('add','.gitignore')|Out-Null;Git $r @('commit','-qm','ignore fixture')|Out-Null
File $r 'ignored-input.txt' 'good'
$p=LegacyContract $r 'SMALL' 'none' "if ((Get-Content ignored-input.txt) -ne 'good') { throw 'bad' }" -SessionId 'declared-input'
$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable;$v.checks[0].inputs=@('ignored-input.txt');[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
$run=New-HistoricalV3RunFixture $r $p 'declared-input';$path=$run.run_path
$capture=Capture-ControlFlowCheck $r $path 'check-1'
Update-ControlFlowRun $r $path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Assert ($capture.status -eq 'PASS' -and (Test-ControlFlowGate $r $path 'Completion').status -eq 'PASS') 'declared ignored file allows fresh successful capture'
File $r 'ignored-input.txt' 'bad';$gate=Test-ControlFlowGate $r $path 'Completion'
Assert ($gate.status -eq 'FAIL' -and 'CHECK_STALE:check-1' -in $gate.reasons) 'changed declared ignored input invalidates captured check'
File $r 'ignored-input.txt' 'good';Capture-ControlFlowCheck $r $path 'check-1'|Out-Null
Update-ControlFlowRun $r $path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
[IO.File]::Delete((Join-Path $r 'ignored-input.txt'));$gate=Test-ControlFlowGate $r $path 'Completion'
Assert ($gate.status -eq 'FAIL' -and 'CHECK_STALE:check-1' -in $gate.reasons) 'deletion of declared input invalidates captured check'
File $r 'ignored-input.txt' 'good'
$v.checks[0].command="[IO.File]::WriteAllText('ignored-input.txt','changed')";[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
$capture=Capture-ControlFlowCheck $r $path 'check-1'
Assert ($capture.status -eq 'STALE') 'declared input changed during check is never PASS'
[IO.Directory]::CreateDirectory((Join-Path $r 'input-dir'))|Out-Null
$v.checks[0].inputs=@('input-dir');[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
Throws {Capture-ControlFlowCheck $r $path 'check-1'} 'directories cannot be declared as file inputs'
$link=Join-Path $r 'input-link';$linkCreated=$false
try{New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $r 'ignored-input.txt') -ErrorAction Stop|Out-Null;$linkCreated=$true}catch{}
if($linkCreated){
    $v.checks[0].inputs=@('input-link');[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
    Throws {Capture-ControlFlowCheck $r $path 'check-1'} 'symbolic links cannot be declared as file inputs'
}
Write-Output "gates input freshness total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}}
$global:LASTEXITCODE=0
$r=NewFixture
try {
$p=LegacyContract $r 'SMALL' 'required' -SessionId 'wrong-tree';$run=New-HistoricalV3RunFixture $r $p 'wrong-tree';$path=$run.run_path
File $r 'owned.txt' 'requested edit';Capture-ControlFlowCheck $r $path 'check-1'|Out-Null
Update-ControlFlowRun $r $path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Assert ((Test-ControlFlowGate $r $path 'Commit').status -eq 'PASS') 'approved candidate built before wrong tree commit'
File $r 'foreign.txt' 'unrequested committed content';Git $r @('commit','-am','wrong actual tree','-q')|Out-Null
File $r 'foreign.txt' 'initial'
$g=Test-ControlFlowGate $r $path 'Completion'
Assert ('COMMIT_TREE_OR_PARENT_MISMATCH' -in $g.reasons) 'actual unexpected commit tree rejected even when working source restored'
Write-Output "gates actual tree final: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}}
$global:LASTEXITCODE=0
$r=NewFixture
try {
$p=LegacyContract $r 'SMALL' 'none' -SessionId 'removed-index';$run=New-HistoricalV3RunFixture $r $p 'removed-index';$path=$run.run_path
Capture-ControlFlowCheck $r $path 'check-1'|Out-Null
Update-ControlFlowRun $r $path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Git $r @('rm','--cached','foreign.txt')|Out-Null
$g=Test-ControlFlowGate $r $path 'Completion'
Assert ('UNOWNED_INDEX_CHANGED:foreign.txt' -in $g.reasons) 'initially clean unowned index deletion is not hidden by unchanged working content'
Write-Output "gates index deletion final: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}}
$global:LASTEXITCODE=0
