. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
File $r 'foreign.txt' 'foreign staged';Git $r @('add','foreign.txt')|Out-Null;File $r 'foreign.txt' 'foreign unstaged'
$foreignBefore=Git $r @('ls-files','-s','foreign.txt')
$configBefore=Git $r @('config','--local','--list')
$p=Contract $r 'MEDIUM' 'required' -SessionId 'gate-session'
$run=Start-ControlFlowRun $r $p 'gate-session';$path=$run.run_path
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
$p=Contract $r 'SMALL' 'none' -SessionId 'small-session';$run=Start-ControlFlowRun $r $p 'small-session';$path=$run.run_path
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
$p=Contract $r 'SMALL' 'none' -SessionId 'done-session';$run=Start-ControlFlowRun $r $p 'done-session'
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
$p=Contract $r 'SMALL' 'required' -SessionId 'wrong-tree';$run=Start-ControlFlowRun $r $p 'wrong-tree';$path=$run.run_path
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
$p=Contract $r 'SMALL' 'none' -SessionId 'removed-index';$run=Start-ControlFlowRun $r $p 'removed-index';$path=$run.run_path
Capture-ControlFlowCheck $r $path 'check-1'|Out-Null
Update-ControlFlowRun $r $path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Git $r @('rm','--cached','foreign.txt')|Out-Null
$g=Test-ControlFlowGate $r $path 'Completion'
Assert ('UNOWNED_INDEX_CHANGED:foreign.txt' -in $g.reasons) 'initially clean unowned index deletion is not hidden by unchanged working content'
Write-Output "gates index deletion final: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}}
$global:LASTEXITCODE=0
