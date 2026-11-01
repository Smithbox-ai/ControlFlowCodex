. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
Assert ((Get-ControlFlowClassification).schema_version -ceq '4.0.0') 'DefaultClassificationIsV4'
foreach($module in @('ControlFlow.Core.psm1','ControlFlow.Package.psm1','ControlFlow.Hooks.psm1')){
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $script:CoreRoot 'scripts') $module),[ref]$null,[ref]$null)
 Assert ($ast.ScriptRequirements.RequiredPSVersion -eq [version]'7.4') ('DeclaredRuntimeFloor:'+ $module)
}
Throws {Get-ControlFlowClassification -SchemaVersion '3.0.0'} 'NewClassificationRejectsV3'
Throws {Get-ControlFlowClassification -SchemaVersion '9.0.0'} 'UnknownVersionRejected'
$r=NewFixture
try {
 $p=LegacyContract $r -SessionId 'legacy-boundary'
 $paths=Get-ControlFlowStoragePaths $r 'test-task' 'legacy-boundary'
 $before=@(Get-ChildItem -LiteralPath $paths.worktree_path -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($paths.worktree_path,$_.FullName)+':'+(Get-FileHash $_.FullName).Hash}|Sort-Object)
 Throws {Start-ControlFlowRun $r $p 'legacy-boundary'} 'NewRunV3RejectedWithoutStorageMutation'
 $after=@(Get-ChildItem -LiteralPath $paths.worktree_path -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($paths.worktree_path,$_.FullName)+':'+(Get-FileHash $_.FullName).Hash}|Sort-Object)
 Assert (($before-join'|') -ceq ($after-join'|') -and -not(Test-Path $paths.active_path)) 'RejectedV3CreatesNoStateRunOrPointer'
 $shadow=New-Module -Name ControlFlow.Core -ScriptBlock {}
 Import-Module $shadow
 try {
  Assert (@(Get-Module ControlFlow.Core).Count -gt 1) 'HistoricalFixtureRegressionLoadsDuplicateModuleNames'
  $old=New-HistoricalV3RunFixture $r $p 'legacy-boundary'
 } finally {Remove-Module -ModuleInfo $shadow -Force}
 $read=Read-ControlFlowRun $r $old.run_path
 Assert ($read.legacy_semantics -and $read.state.schema_version -ceq '3.0.0') 'HistoricalV3RunPreservesVersionAndSemantics'
 $gate=Test-ControlFlowGate $r $old.run_path Completion
 Assert ($gate.legacy_semantics -and $gate.schema_version -ceq '3.0.0' -and $gate.status -ceq 'FAIL') 'LegacyGateIsExplicitAndDoesNotBecomeV4'
 $pointer=[IO.File]::ReadAllText($paths.active_path);$bad=$pointer|ConvertFrom-Json -AsHashtable;$bad.schema_version='4.0.0';[IO.File]::WriteAllText($paths.active_path,($bad|ConvertTo-Json -Depth 20))
 Throws {Get-ControlFlowActiveRun $r 'legacy-boundary'} 'LegacyActivePointerCannotBecomeV4'
 [IO.File]::WriteAllText($paths.active_path,$pointer)
 $notice=Request-ControlFlowInterrupt $r 'legacy-boundary'
 Assert ((Read-ControlFlowRun $r $old.run_path).state.status -ceq 'INTERRUPTED') 'OldPendingInterruptStillReadable'
 $dest=Join-Path $r 'migrated.json';$sourceBefore=[IO.File]::ReadAllText($p)
 & "$script:CoreRoot/scripts/migrate-contract.ps1" -Path $p -OutputPath $dest -TaskId migrated|Out-Null
 Assert ($LASTEXITCODE -eq 0) 'DefaultMigrationToV4'
 $m=Get-Content $dest -Raw|ConvertFrom-Json -AsHashtable
 Assert ($m.schema_version -ceq '4.0.0' -and $m.contract_status -ceq 'draft' -and $m.commit.mode -ceq 'none' -and -not$m.ContainsKey('approvals') -and -not$m.ContainsKey('captures')) 'MigrationProducesV4DraftWithoutApprovals'
 Assert ([IO.File]::ReadAllText($p) -ceq $sourceBefore -and (Read-ControlFlowRun $r $old.run_path).state.schema_version -ceq '3.0.0') 'MigrationNeverMutatesHistoricalRunOrContract'
} finally {RemoveFixture $r}

# This ownership/commit regression exercises real V4 preflight and artifacts,
# independently of the historical compatibility fixtures in the generic suites.
$r=NewFixture
try {
 File $r 'foreign.txt' 'foreign staged';Git $r @('add','foreign.txt')|Out-Null;File $r 'foreign.txt' 'foreign unstaged'
 $foreign=Git $r @('ls-files','-s','foreign.txt');$config=Git $r @('config','--local','--list')
 $p=V4Contract $r final 'v4-selective';$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
 $v.work_type='docs';$v.domain.classification='generic';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false;$v.review_policy.human_final=$false;$v.commit.mode='required'
 [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40));$run=Start-ControlFlowRun $r $p 'v4-selective'
 Assert (-not(Read-ControlFlowRun $r $run.run_path).legacy_semantics) 'NewRunUsesV4Semantics'
 Throws {Capture-ControlFlowCheck $r $run.run_path 'check-1'} 'V4CaptureRequiresRealPreflight'
 Update-ControlFlowRun $r $run.run_path @{type='preflight';status='APPROVED'}|Out-Null
 File $r 'owned.txt' 'V4 documented change'
 $capture=Capture-ControlFlowCheck $r $run.run_path 'check-1'
 Assert ($capture.status -ceq 'PASS' -and $capture.quality.executed_tests -ge 1 -and $capture.quality.assertion_count -ge 1) 'V4ActualAssertionsCaptured'
 Update-ControlFlowRun $r $run.run_path @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
 $packet=Artifact $r $run.run_path 'review-packet'
 $gate=Test-ControlFlowGate $r $run.run_path Commit
 Assert ($gate.status -ceq 'PASS' -and -not$gate.legacy_semantics) ('V4SelectiveCommitGate:'+($gate.reasons-join','))
 Assert ((Git $r @('ls-files','-s','foreign.txt')) -ceq $foreign -and (Git $r @('config','--local','--list')) -ceq $config) 'V4CandidatePreservesForeignIndexAndConfig'
 Git $r @('commit','--only','-qm','v4 scoped change','--','owned.txt')|Out-Null;$sha=Git $r @('rev-parse','HEAD')
 $gate=Test-ControlFlowGate $r $run.run_path Completion -CommitSha $sha
 Assert ($gate.status -ceq 'PASS') ('V4SelectiveCompletion:'+($gate.reasons-join','))
 Assert ((Git $r @('ls-files','-s','foreign.txt')) -ceq $foreign -and [IO.File]::ReadAllText((Join-Path $r 'foreign.txt')) -ceq 'foreign unstaged') 'V4SelectiveCommitPreservesForeignIndex'
 File $r 'owned.txt' 'late change';$stale=Test-ControlFlowGate $r $run.run_path Completion -CommitSha $sha
 Assert ($stale.status -ceq 'FAIL' -and 'CHECK_STALE:check-1' -cin $stale.reasons) 'V4LateSourceEditInvalidatesEvidence'
} finally {RemoveFixture $r}
Write-Output "v4-release: $script:Count assertions passed"
$global:LASTEXITCODE=0
