. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
$b=Git $r @('rev-parse','HEAD')
File $r 'foreign.txt' 'staged';Git $r @('add','foreign.txt');File $r 'foreign.txt' 'working';File $r ' space ü .txt' 'untracked'
$s=Get-ControlFlowGitSnapshot -RepoRoot $r
Assert (@($s.dirty_paths).Count -eq 2) 'partial stage and whitespace UTF8 path observed'
$a=Get-ControlFlowSourceDigest -RepoRoot $r -Baseline $b
File $r 'foreign.txt' 'mutation'
$d=Get-ControlFlowSourceDigest -RepoRoot $r -Baseline $b
Assert ($a.digest -cne $d.digest) 'mutation of initial dirty file changes fingerprint'
File $r ' space ü .txt' 'mutated untracked'
$e=Get-ControlFlowSourceDigest -RepoRoot $r -Baseline $b
Assert ($d.digest -cne $e.digest) 'untracked mutation changes fingerprint'
Git $r @('add','.');$f=Get-ControlFlowSourceDigest -RepoRoot $r -Baseline $b
Assert ($e.digest -ceq $f.digest) 'staging same contents preserves fingerprint'
Git $r @('commit','-qm','effective content');$g=Get-ControlFlowSourceDigest -RepoRoot $r -Baseline $b
Assert ($e.digest -ceq $g.digest) 'commit same contents preserves fingerprint'
Throws {Get-ControlFlowSourceDigest -RepoRoot $r -Baseline 'deadbeef'} 'invalid baseline fails closed'
Throws {Get-ControlFlowGitSnapshot -RepoRoot ([IO.Path]::GetTempPath())} 'not a git repo fails closed'
Write-Output "git-evidence: $script:Count assertions passed"
}finally{Remove-Item -LiteralPath $r -Recurse -Force}
$r=NewFixture
try {
$b=Git $r @('rev-parse','HEAD');$tree=Git $r @('rev-parse','HEAD^{tree}')
Throws {Get-ControlFlowSourceDigest $r $tree} 'tree object cannot masquerade as baseline commit'
$orphan=Git $r @('commit-tree',$tree,'-m','unrelated baseline')
Throws {Get-ControlFlowSourceDigest $r $orphan} 'valid nonancestor baseline fails closed'
$index=Join-Path $r '.git/index';$old=[IO.File]::ReadAllBytes($index)
try{[IO.File]::WriteAllText($index,'broken index');Throws {Get-ControlFlowGitSnapshot $r} 'failed Git index observation cannot become empty CLEAN'}finally{[IO.File]::WriteAllBytes($index,$old)}
[IO.File]::Delete((Join-Path $r 'owned.txt'));$before=Get-ControlFlowSourceDigest $r $b
Git $r @('add','-A')|Out-Null;Git $r @('commit','-qm','deletion')|Out-Null
$after=Get-ControlFlowSourceDigest $r $b;Assert ($before.digest -ceq $after.digest) 'deletion fingerprint survives commit'
Assert (@($after.entries|Where-Object {$_.path -ceq 'owned.txt'})[0].mode -eq 'deleted') 'baseline deletion remains represented after commit'
if(-not $IsWindows){File $r 'back\slash' 'path';$snap=Get-ControlFlowGitSnapshot $r;Assert ('back\slash' -cin $snap.untracked) 'literal Unix backslash survives Git parsing'}
Write-Output "git-evidence final: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$global:LASTEXITCODE=0
$r=NewFixture
try {
$b=Git $r @('rev-parse','HEAD')
Git $r @('update-index','--assume-unchanged','owned.txt')|Out-Null;File $r 'owned.txt' 'hidden user edit'
Throws {Get-ControlFlowGitSnapshot $r} 'assume-unchanged cannot hide initial foreign user content'
$p=Contract $r 'SMALL' 'required'
Throws {Start-ControlFlowRun $r $p 'hidden-index'} 'run start fails closed on hidden index entries'
Git $r @('update-index','--no-assume-unchanged','owned.txt')|Out-Null
Git $r @('update-index','--skip-worktree','owned.txt')|Out-Null
Throws {Get-ControlFlowSourceDigest $r $b} 'skip-worktree observation is unsupported and fail-closed'
Assert ((Git $r @('ls-files','-v','owned.txt')).StartsWith('S ')) 'observation never clears user skip-worktree flag'
Write-Output "git-evidence hidden flags final: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$global:LASTEXITCODE=0
$r=NewFixture
try {
$older=Git $r @('rev-parse','HEAD');File $r 'later.txt' 'added after baseline';Git $r @('add','later.txt')|Out-Null;Git $r @('commit','-qm','later tracked file')|Out-Null
[IO.File]::Delete((Join-Path $r 'later.txt'))
$unstaged=Get-ControlFlowSourceDigest $r $older
Git $r @('add','-A')|Out-Null
$staged=Get-ControlFlowSourceDigest $r $older
Assert ($unstaged.digest -ceq $staged.digest) 'deleting post-baseline addition has stage-invariant effective absence'
Git $r @('commit','-qm','remove post-baseline file')|Out-Null
$committed=Get-ControlFlowSourceDigest $r $older
Assert ($unstaged.digest -ceq $committed.digest) 'deleting post-baseline addition has commit-invariant effective absence'
Assert (@($committed.entries|Where-Object {$_.path -ceq 'later.txt'}).Count -eq 0) 'absent path absent in fixed baseline needs no tombstone'
Write-Output "git-evidence older baseline final: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){Remove-Item -LiteralPath $r -Recurse -Force}}
$global:LASTEXITCODE=0
