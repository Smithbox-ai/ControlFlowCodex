. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
Assert ($null -ne (Get-Command Get-ControlFlowStoragePaths -ErrorAction SilentlyContinue)) 'external storage path resolver exists'
$r=NewFixture
try {
    $paths=Get-ControlFlowStoragePaths -RepoRoot $r -TaskId 'test-task' -SessionId 'storage-session' -Create
    Assert (-not $paths.root.StartsWith($r+[IO.Path]::DirectorySeparatorChar)) 'state root is outside the project'
    $cli=Join-Path $script:CoreRoot 'scripts/get-storage-paths.ps1'
    $pwsh=@(Get-Command pwsh -CommandType Application)[0].Source
    $cliPaths=(& $pwsh -NoProfile -File $cli -RepoRoot $r -TaskId 'test-task' -SessionId 'storage-session' -Create)|ConvertFrom-Json -AsHashtable
    Assert ($LASTEXITCODE -eq 0 -and $cliPaths.contract_path -ceq $paths.contract_path) 'bundled CLI resolves the same external contract with a successful exit'
    $p=Contract $r -SessionId 'storage-session'
    $before=Git $r @('status','--porcelain=v1','--untracked-files=all')
    $run=Start-ControlFlowRun $r $p 'storage-session'
    Capture-ControlFlowCheck $r $run.run_path 'check-1'|Out-Null
    Update-ControlFlowRun $r $run.run_path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
    Assert ((Test-ControlFlowGate $r $run.run_path 'Completion').status -eq 'PASS') 'external evidence proves completion'
    Assert ((Get-ControlFlowActiveRun $r 'storage-session').run_path -ceq $run.run_path) 'external active marker restores exact session'
    Assert ((Git $r @('status','--porcelain=v1','--untracked-files=all')) -ceq $before) 'contract, capture, locks and markers leave Git status unchanged'
    Assert (-not (Test-Path (Join-Path $r 'plans')) -and -not (Test-Path (Join-Path $r '.codex'))) 'runtime creates no project bookkeeping directories'
    $other=Get-ControlFlowStoragePaths -RepoRoot $r -TaskId 'test-task' -SessionId 'other-session'
    Assert ($other.contract_path -cne $p -and $other.active_path -cne $paths.active_path) 'sessions have separate contracts and active markers'
    Throws {Read-ControlFlowRun $r $run.run_path 'other-session'} 'another session cannot adopt external run'
    $second=NewFixture
    try {
        $secondPaths=Get-ControlFlowStoragePaths $second 'test-task' 'storage-session'
        Assert ($secondPaths.worktree_path -cne $paths.worktree_path) 'physical worktree and Git identity separate external state'
        Throws {Read-ControlFlowRun $second $run.run_path 'storage-session'} 'another worktree cannot adopt external evidence'
        Assert ($null -eq (Get-ControlFlowActiveRun $second 'storage-session')) 'another worktree has no active marker'
        $env:CONTROLFLOW_STATE_ROOT=Join-Path $second 'hidden-state'
        Throws {Get-ControlFlowStoragePaths $r 'test-task' 'storage-session' -Create} 'state inside another project is also rejected'
        Assert (-not [IO.Directory]::Exists($env:CONTROLFLOW_STATE_ROOT)) 'another project remains untouched'
    } finally {$env:CONTROLFLOW_STATE_ROOT=$script:TestStateRoot;RemoveFixture $second}
    $linkedWorktree=Join-Path ([IO.Path]::GetTempPath()) ('cf-core-'+[guid]::NewGuid().ToString('N'))
    Git $r @('worktree','add','--detach',$linkedWorktree,'HEAD')|Out-Null
    try {
        $linkedPaths=Get-ControlFlowStoragePaths $linkedWorktree 'test-task' 'storage-session' -Create
        Assert ($linkedPaths.worktree_path -cne $paths.worktree_path) 'linked Git worktrees keep distinct external state'
        Throws {Read-ControlFlowRun $linkedWorktree $run.run_path 'storage-session'} 'shared Git history does not authorize another worktree run'
        Assert ($null -eq (Get-ControlFlowActiveRun $linkedWorktree 'storage-session')) 'linked worktree does not inherit the main worktree marker'
    } finally {RemoveFixture $linkedWorktree;Git $r @('worktree','prune')|Out-Null}
    $bareRoot=Join-Path ([IO.Path]::GetTempPath()) ('cf-bare-'+[guid]::NewGuid().ToString('N'))
    $bareWorktree=Join-Path ([IO.Path]::GetTempPath()) ('cf-core-'+[guid]::NewGuid().ToString('N'))
    try {
        Git $r @('clone','--bare','--quiet',$r,$bareRoot)|Out-Null
        Git $bareRoot @('worktree','add','--detach',$bareWorktree,'HEAD')|Out-Null
        $env:CONTROLFLOW_STATE_ROOT=[IO.Path]::Combine($bareRoot,'controlflow')
        Throws {Get-ControlFlowStoragePaths $bareWorktree 'test-task' 'storage-session' -Create} 'state inside a shared bare Git directory is rejected'
        Assert (-not [IO.Directory]::Exists($env:CONTROLFLOW_STATE_ROOT)) 'shared Git metadata receives no bookkeeping'
    } finally {
        $env:CONTROLFLOW_STATE_ROOT=$script:TestStateRoot
        if([IO.Directory]::Exists($bareWorktree)){RemoveFixture $bareWorktree}
        $resolvedBare=[IO.Path]::GetFullPath($bareRoot);$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if(-not $resolvedBare.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolvedBare).StartsWith('cf-bare-')){throw 'Unsafe bare fixture cleanup'}
        if([IO.Directory]::Exists($resolvedBare)){Remove-Item -LiteralPath $resolvedBare -Recurse -Force}
    }
    $manualContract=Contract $r
    $manual=Start-ControlFlowRun $r $manualContract -ManualFallback
    Assert ($manual.run_path -match '[/\\]sessions[/\\]manual[/\\]' -and $manual.state.manual_fallback) 'manual fallback has an external namespace without inventing native identity'
    Throws {Read-ControlFlowRun $r $manual.run_path 'storage-session'} 'native session cannot adopt manual fallback'
    $prior=$env:CONTROLFLOW_STATE_ROOT
    $priorCodexHome=$env:CODEX_HOME
    try {
        $env:CONTROLFLOW_STATE_ROOT=Join-Path $r 'hidden-state'
        Throws {Get-ControlFlowStoragePaths $r 'test-task' 'storage-session' -Create} 'configured project-local state is rejected'
        $cliError=(& $pwsh -NoProfile -File $cli -RepoRoot $r -TaskId 'test-task' -SessionId 'storage-session' -Create)|ConvertFrom-Json -AsHashtable
        Assert ($LASTEXITCODE -eq 2 -and $cliError.status -ceq 'ERROR' -and $cliError.error -match 'STATE_ROOT_INSIDE_PROJECT') 'bundled CLI reports an explicit setup error without fallback'
        $global:LASTEXITCODE=0
        Assert (-not (Test-Path $env:CONTROLFLOW_STATE_ROOT)) 'rejected root is never created'
        $env:CONTROLFLOW_STATE_ROOT='relative-state'
        Throws {Get-ControlFlowStoragePaths $r 'test-task' 'storage-session' -Create} 'relative state root is rejected'
        $blockedRoot=Join-Path $prior 'blocked-root'
        [IO.File]::WriteAllText($blockedRoot,'owned sentinel')
        $env:CONTROLFLOW_STATE_ROOT=$blockedRoot
        $unavailable=$false
        try {Get-ControlFlowStoragePaths $r 'test-task' 'storage-session' -Create|Out-Null} catch {$unavailable=$_.Exception.Message -match 'STATE_STORAGE_UNAVAILABLE'}
        Assert $unavailable 'unwritable storage fails with an explicit storage error'
        Assert ([IO.File]::ReadAllText($blockedRoot) -ceq 'owned sentinel' -and -not (Test-Path (Join-Path $r 'plans'))) 'unavailable storage preserves existing data and never falls back to the project'
        [IO.File]::Delete($blockedRoot)
        $env:CONTROLFLOW_STATE_ROOT=''
        $env:CODEX_HOME=Join-Path $prior 'native-home'
        $nativeSentinel=Join-Path $env:CODEX_HOME 'sessions/preserved.jsonl'
        File $env:CODEX_HOME 'sessions/preserved.jsonl' 'native session remains owned by Codex'
        $defaultPaths=Get-ControlFlowStoragePaths $r 'default-test' 'storage-session' -Create
        Assert ($defaultPaths.root -ceq (Join-Path $env:CODEX_HOME 'controlflow')) 'CODEX_HOME selects a dedicated ControlFlow namespace'
        Assert ([IO.File]::ReadAllText($nativeSentinel) -ceq 'native session remains owned by Codex') 'native Codex session data is untouched'
        $env:CODEX_HOME=''
        $homePaths=Get-ControlFlowStoragePaths $r 'default-test' 'storage-session'
        Assert ($homePaths.root -ceq (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex/controlflow')) 'unset CODEX_HOME uses the native user home default without writing'
    } finally {
        $env:CONTROLFLOW_STATE_ROOT=$prior;$env:CODEX_HOME=$priorCodexHome
        $nativeHome=Join-Path $prior 'native-home'
        if([IO.Directory]::Exists($nativeHome) -and [IO.Path]::GetFullPath($nativeHome).StartsWith($script:TestStateRoot+[IO.Path]::DirectorySeparatorChar)){[IO.Directory]::Delete($nativeHome,$true)}
    }
    $linkedRoot=Join-Path ([IO.Path]::GetTempPath()) ('cf-state-link-'+[guid]::NewGuid().ToString('N'))
    try {
        if($IsWindows){New-Item -ItemType Junction -Path $linkedRoot -Target $prior|Out-Null}else{[IO.Directory]::CreateSymbolicLink($linkedRoot,$prior)|Out-Null}
        $env:CONTROLFLOW_STATE_ROOT=$linkedRoot
        Assert ($null -eq (Get-ControlFlowActiveRun $r 'unmanaged-session')) 'an absent external marker keeps native sessions unmanaged even through an unused alias'
        Throws {Get-ControlFlowStoragePaths $r 'test-task' 'storage-session' -Create} 'linked state roots cannot create or adopt evidence'
        Throws {Get-ControlFlowActiveRun $r 'storage-session'} 'existing evidence cannot be adopted through an aliased root'
    } finally {$env:CONTROLFLOW_STATE_ROOT=$prior;if([IO.Directory]::Exists($linkedRoot)){[IO.Directory]::Delete($linkedRoot)}}
    if(-not $IsWindows) {
        $danglingPaths=Get-ControlFlowStoragePaths $r 'test-task' 'dangling-session' -Create
        [IO.File]::CreateSymbolicLink($danglingPaths.active_path,[IO.Path]::Combine($danglingPaths.session_path,'missing.json'))|Out-Null
        try {Throws {Get-ControlFlowActiveRun $r 'dangling-session'} 'a dangling active marker is invalid rather than unmanaged'}
        finally {[IO.File]::Delete($danglingPaths.active_path)}
        $writerLock=[IO.Path]::Combine($run.run_path,'writer.lock')
        $escapedWriter=[IO.Path]::Combine($r,'escaped-writer.lock')
        [IO.File]::Delete($writerLock)
        [IO.File]::CreateSymbolicLink($writerLock,$escapedWriter)|Out-Null
        try {
            Throws {Update-ControlFlowRun $r $run.run_path @{type='preflight';status='APPROVED'}} 'a writer lock link is rejected before opening its target'
            Assert (-not [IO.File]::Exists($escapedWriter)) 'writer lock cannot create project bookkeeping through a leaf link'
        } finally {[IO.File]::Delete($writerLock);[IO.File]::Delete($escapedWriter)}
        $lockContract=Contract $r -SessionId 'lock-session'
        $lockPaths=Get-ControlFlowStoragePaths $r 'test-task' 'lock-session'
        $escapedActive=[IO.Path]::Combine($r,'escaped-active.lock')
        [IO.File]::CreateSymbolicLink($lockPaths.active_path+'.lock',$escapedActive)|Out-Null
        try {
            Throws {Start-ControlFlowRun $r $lockContract 'lock-session'} 'an active marker lock link is rejected before opening its target'
            Assert (-not [IO.File]::Exists($escapedActive)) 'active marker lock cannot create project bookkeeping through a leaf link'
        } finally {[IO.File]::Delete($lockPaths.active_path+'.lock');[IO.File]::Delete($escapedActive)}
        $unixUserId=& (@(Get-Command id -CommandType Application)[0]).Source -u
        if($unixUserId -ne '0') {
            $sessionMode=[IO.File]::GetUnixFileMode($paths.session_path)
            [IO.File]::SetUnixFileMode($paths.session_path,[IO.UnixFileMode]0)
            try {Throws {Get-ControlFlowActiveRun $r 'storage-session'} 'an unreadable active namespace is an error rather than unmanaged'}
            finally {[IO.File]::SetUnixFileMode($paths.session_path,$sessionMode)}
        }
        $literalRoot=$prior+'-literal\name'
        try {
            $env:CONTROLFLOW_STATE_ROOT=$literalRoot
            $literalContract=Contract $r -SessionId 'literal-storage'
            Assert ($literalContract.StartsWith($literalRoot+'/',[StringComparison]::Ordinal)) 'external Unix root preserves literal backslash bytes'
            $literalRun=Start-ControlFlowRun $r $literalContract 'literal-storage'
            Capture-ControlFlowCheck $r $literalRun.run_path 'check-1'|Out-Null
            Assert ([IO.File]::Exists([IO.Path]::Combine($literalRun.run_path,'state.json'))) 'literal Unix root holds real state and captures'
        } finally {$env:CONTROLFLOW_STATE_ROOT=$prior;if([IO.Directory]::Exists($literalRoot)){[IO.Directory]::Delete($literalRoot,$true)}}
    }
    File $r 'plans/artifacts/legacy-task/plan.meta.json' ([IO.File]::ReadAllText($p))
    $legacyPath=Join-Path $r 'plans/artifacts/legacy-task/plan.meta.json'
    $legacyContents=[IO.File]::ReadAllText($legacyPath)
    Throws {Start-ControlFlowRun $r $legacyPath 'legacy-session'} 'project-local legacy contract requires explicit external migration'
    Assert ([IO.File]::ReadAllText($legacyPath) -ceq $legacyContents) 'legacy artifacts are never silently rewritten or deleted'
    Write-Output "VALID external state storage: $script:Count assertions"
} finally {RemoveFixture $r}
