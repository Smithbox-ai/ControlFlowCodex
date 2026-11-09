param([ValidateSet('All','Terminal','Identity','Git','Gate')][string]$Case='All')
. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$module=Get-TestControlFlowModule
function LightFixture([string]$Session){
 $r=NewFixture
 try{
  $p=V4Contract $r final $Session;$v=Get-Content -Raw -LiteralPath $p|ConvertFrom-Json -AsHashtable
  $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
  [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
  $run=Start-ControlFlowRun $r $p $Session;$rp=$run.run_path
  Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
  Capture-ControlFlowCheck $r $rp check-1|Out-Null
  Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
  Artifact $r $rp review-packet|Out-Null
  return @{root=$r;path=$p;run=$rp}
 }catch{RemoveFixture $r;throw}
}
if($Case -in @('All','Terminal')){
 $f=LightFixture 'audit-terminal';$r=$f.root
 try{
  # Retain a valid notification generation to model a publisher that observed ACTIVE.
  Request-ControlFlowInterrupt $r 'audit-terminal'|Out-Null
  $notice=Get-Content -Raw -LiteralPath (Join-Path $f.run 'pending-interrupt.json')|ConvertFrom-Json -AsHashtable
  Update-ControlFlowRun $r $f.run @{type='resume';user_decision_ref='fixture:resume'}|Out-Null
  Update-ControlFlowRun $r $f.run @{type='complete'}|Out-Null
  Assert ($null -eq (Request-ControlFlowInterrupt $r 'audit-terminal')) 'TerminalInterruptIgnored'
  $notice.interrupt_id=[guid]::NewGuid().ToString('N')
  [IO.File]::WriteAllText((Join-Path $f.run 'pending-interrupt.json'),($notice|ConvertTo-Json -Depth 20))
  Assert ((Read-ControlFlowRun $r $f.run).state.status -ceq 'COMPLETED') 'LateMailboxCannotReopenCompleted'
  Throws {Update-ControlFlowRun $r $f.run @{type='resume';user_decision_ref='fixture:no-reopen'}} 'CompletedImmutable'
  Update-ControlFlowRun $r $f.run @{type='stop';reason='BLOCKED';evidence='fixture:stale-completion'}|Out-Null
  Assert ((Read-ControlFlowRun $r $f.run).state.lifecycle_closed) 'ClosedBlockedRemainsClosed'
  Assert ($null -eq (Request-ControlFlowInterrupt $r 'audit-terminal')) 'ClosedBlockedInterruptIgnored'
  $next=Start-ControlFlowRun $r $f.path 'audit-terminal'
  Assert ($next.run_id -cne (Read-ControlFlowRun $r $f.run).state.run_id) 'ClosedBlockedSessionReusable'
 }finally{RemoveFixture $r}
 $r=NewFixture
 try{
  $p=V4Contract $r draft 'audit-cancel';$run=Start-ControlFlowRun $r $p 'audit-cancel'
  Update-ControlFlowRun $r $run.run_path @{type='stop';reason='CANCEL';evidence='fixture:cancel'}|Out-Null
  Assert ($null -eq (Request-ControlFlowInterrupt $r 'audit-cancel')) 'CancelledInterruptIgnored'
  Assert ((Read-ControlFlowRun $r $run.run_path).state.status -ceq 'CANCELLED') 'CancelledStatusPreserved'
  Throws {Update-ControlFlowRun $r $run.run_path @{type='resume';user_decision_ref='fixture:no-reopen'}} 'CancelledImmutable'
 }finally{RemoveFixture $r}
 $r=NewFixture
 try{
  $p=LegacyContract $r -SessionId 'audit-legacy'
  $run=New-HistoricalV3RunFixture $r $p 'audit-legacy'
  Update-ControlFlowRun $r $run.run_path @{type='stop';reason='CANCEL';evidence='fixture:legacy'}|Out-Null
  Request-ControlFlowInterrupt $r 'audit-legacy'|Out-Null
  Assert ((Update-ControlFlowRun $r $run.run_path @{type='resume';user_decision_ref='fixture:legacy'}).state.status -ceq 'ACTIVE') 'V3ResumeSemanticsRetained'
 }finally{RemoveFixture $r}
}
if($Case -in @('All','Identity')){
 $r=NewFixture
 try{
  $p=V4Contract $r;$v=Get-Content -Raw -LiteralPath $p|ConvertFrom-Json -AsHashtable
  $v.criteria+=@(@{id='c1';text='Case-distinct criterion'})
  $v.review_policy.requirements+=@(@{target_id='c1';judges=@('code')})
  $v.checks[0].criteria=@('C1','c1')
  $extra=$v.checks[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json -AsHashtable
  $extra.id='Check-1';$extra.command='Write-Output original';$extra.Remove('report');$v.checks+=@($extra)
  [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
  $run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
  $context=Artifact $r $rp context;$design=Artifact $r $rp design @($context)
  ReviewArtifact $r $rp $design|Out-Null
  $payload=@{scenarios=@(@{id='S1';inputs='fixture';expected='Both exact identities';expectation_source='approved audit';criterion_refs=@('C1','c1');check_refs=@('check-1','Check-1');negative='Changed definition';boundary='Case'});mutation_assessment=@{decision='skip';method='none';rationale='Identity fixture only';scope=@();criterion_refs=@();check_refs=@()}}
  $qa=Artifact $r $rp qa-plan @($design) $payload
  Artifact $r $rp implementation-plan @($qa)|Out-Null
  $saved=Get-Content -Raw -LiteralPath (Join-Path $rp $qa.path)|ConvertFrom-Json -AsHashtable
  Assert ($saved.qa_bindings.checks.Count -eq 2 -and $saved.qa_bindings.criteria.Count -eq 2) 'CaseDistinctQABindingsRetained'
  $v.checks[1].command='Write-Output changed';$v.contract_status='final'
  [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
  Assert (-not (Get-ControlFlowPlanningContext $r $rp).artifacts.ContainsKey('qa-plan')) 'EitherCaseCheckChangeStalesQA'
  Throws {Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}} 'ChangedQACannotAuthorize'
 }finally{RemoveFixture $r}
 $r=NewFixture
 try{
  $p=V4Contract $r final;$v=Get-Content -Raw -LiteralPath $p|ConvertFrom-Json -AsHashtable
  $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
  $v.criteria+=@(@{id='c1';text='Other human criterion'});$v.checks=@()
  $v.review_policy.requirements=@(@{target_id='C1';judges=@('human')},@{target_id='c1';judges=@('human')})
  [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
  $rp=(Start-ControlFlowRun $r $p -ManualFallback).run_path
  Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
  $packet=Artifact $r $rp review-packet
  ReviewArtifact $r $rp $packet human UNKNOWN manual C1|Out-Null
  ReviewArtifact $r $rp $packet human UNKNOWN manual c1|Out-Null
  Assert ((Read-ControlFlowRun $r $rp).state.human_wait_targets.Count -eq 2) 'CaseDistinctHumanWaitTargets'
  # Simulate an older V4 publisher that collapsed the wait set but retained
  # both immutable review events. Reading must recover the unresolved target.
  $statePath=Join-Path $rp 'state.json'
  $historical=Get-Content -Raw -LiteralPath $statePath|ConvertFrom-Json -AsHashtable
  $historical.human_wait_targets=@('C1')
  [IO.File]::WriteAllText($statePath,($historical|ConvertTo-Json -Depth 80))
  Assert ((Read-ControlFlowRun $r $rp).state.human_wait_targets.Count -eq 2) 'HistoricalCaseWaitSetCannotLoseTarget'
  $approved=ReviewArtifact $r $rp $packet human APPROVED manual C1
  $receipt=@($approved.evidence.events|Where-Object {$_.type -ceq 'phase_review'})[-1].receipt_id
  Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='fixture:partial';decision_receipt_id=$receipt}} 'PartialCaseApprovalCannotResume'
 }finally{RemoveFixture $r}
 $r=NewFixture
 try{
  File $r 'A.txt' 'initial'
  $caseSensitive=-not [IO.File]::Exists((Join-Path $r 'a.txt'))
  Write-Output "CASE_PATH_CAPABILITY case_sensitive=$caseSensitive"
  if($caseSensitive){
   File $r 'a.txt' 'initial';Git $r @('add','.')|Out-Null;Git $r @('commit','-qm','case paths')|Out-Null
   $p=V4Contract $r final;$v=Get-Content -Raw -LiteralPath $p|ConvertFrom-Json -AsHashtable
   $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false;$v.scope=@('owned.txt','A.txt')
   [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40));$rp=(Start-ControlFlowRun $r $p -ManualFallback).run_path
   Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
   File $r 'A.txt' 'changed';File $r 'a.txt' 'unauthorized'
   Throws {Update-ControlFlowRun $r $rp @{type='resume';mode='planning';user_decision_ref='fixture:replan'}} 'CaseDistinctUnauthorizedCarriedPath'
  }else{Write-Output 'SKIP case-distinct source paths: requires case-sensitive filesystem'}
 }finally{RemoveFixture $r}
}
if($Case -in @('All','Git')){
 $r=NewFixture;$oldPath=$env:PATH;$oldDirectory=[Environment]::CurrentDirectory
 $external=Join-Path ([IO.Path]::GetTempPath()) ('cf-git-exe-'+[guid]::NewGuid().ToString('N'))
 [IO.Directory]::CreateDirectory($external)|Out-Null
 try{
  $trusted=@(Get-Command git -CommandType Application)[0].Source
  $name=if($IsWindows){'git.exe'}else{'git'}
  function Sentinel([string]$Path){
   if($IsWindows){Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32/whoami.exe') -Destination $Path}
   else{[IO.File]::WriteAllText($Path,"#!/bin/sh\nexit 71\n");[IO.File]::SetUnixFileMode($Path,[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)}
  }
  if($IsWindows){
   Sentinel (Join-Path $r $name);[Environment]::CurrentDirectory=$r
   $safeSelection=try{$snapshot=Get-ControlFlowGitSnapshot $r;$snapshot.head -cmatch '^[a-f0-9]{40}$'}catch{$false}
   Assert $safeSelection 'CwdSentinelNeverSelected'
  }
  $tools=Join-Path $r 'tools';[IO.Directory]::CreateDirectory($tools)|Out-Null;Sentinel (Join-Path $tools $name)
  $nested=Join-Path $r 'deep/child';[IO.Directory]::CreateDirectory($nested)|Out-Null
  function RejectGit([string]$Directory,[string]$Label){
   $errorText=try{Get-ControlFlowGitSnapshot $Directory|Out-Null;''}catch{$_.Exception.Message}
   Assert ($errorText -match 'UNTRUSTED_GIT_EXECUTABLE') $Label
  }
  $env:PATH=$tools+[IO.Path]::PathSeparator+$oldPath
  RejectGit $r 'RepositoryPathGitRejected';RejectGit $nested 'NestedCwdRepositoryGitRejected'
  $env:PATH=$oldPath
  $link=Join-Path $external 'linked-tools';$kind=if($IsWindows){'Junction'}else{'SymbolicLink'}
  New-Item -ItemType $kind -Path $link -Target $tools|Out-Null
  $env:PATH=$link+[IO.Path]::PathSeparator+$oldPath
  RejectGit $nested 'ExternalParentLinkToRepositoryGitRejected'
  $env:PATH=$oldPath;[IO.Directory]::Delete($link)
  $trustedLink=Join-Path $external 'trusted-tools'
  New-Item -ItemType $kind -Path $trustedLink -Target ([IO.Path]::GetDirectoryName($trusted))|Out-Null
  $env:PATH=$trustedLink+[IO.Path]::PathSeparator+$oldPath
  Assert ((Get-ControlFlowGitSnapshot $nested).head -ceq (Git $r @('rev-parse','HEAD'))) 'TrustedExternalParentLinkWorks'
  $env:PATH=$oldPath;[IO.Directory]::Delete($trustedLink)
  $sibling=$r+'-other'
  New-Item -ItemType $kind -Path $sibling -Target ([IO.Path]::GetDirectoryName($trusted))|Out-Null
  try{
   $env:PATH=$sibling+[IO.Path]::PathSeparator+$oldPath
   Assert ((Get-ControlFlowGitSnapshot $r).head -ceq (Git $r @('rev-parse','HEAD'))) 'PrefixSiblingIsOutsideWorktree'
  }finally{$env:PATH=$oldPath;[IO.Directory]::Delete($sibling)}
  # A linked worktree .git FILE must establish the same pre-execution boundary.
  $linked=Join-Path $external 'linked-worktree'
  & $trusted -C $r worktree add -q --detach $linked HEAD
  if($LASTEXITCODE -ne 0){throw 'Fixture worktree creation failed'}
  try{
   [IO.Directory]::CreateDirectory((Join-Path $linked 'tools'))|Out-Null
   Sentinel (Join-Path $linked ('tools/'+$name));$env:PATH=(Join-Path $linked 'tools')+[IO.Path]::PathSeparator+$oldPath
   RejectGit $linked 'LinkedWorktreeRepositoryGitRejected'
  }finally{$env:PATH=$oldPath;& $trusted -C $r worktree remove --force $linked}
  $env:PATH=$oldPath
  Assert ((Get-ControlFlowGitSnapshot $nested).head -ceq (Git $r @('rev-parse','HEAD'))) 'TrustedGitNestedRootWorks'
  $embedded=Join-Path $r 'embedded';[IO.Directory]::CreateDirectory($embedded)|Out-Null
  & $trusted -C $embedded init -q
  if($LASTEXITCODE -ne 0){throw 'Nested repository fixture creation failed'}
  $env:PATH=$tools+[IO.Path]::PathSeparator+$oldPath
  RejectGit $embedded 'EnclosingWorktreeGitRejectedForNestedRepository'
 }finally{
  $env:PATH=$oldPath;[Environment]::CurrentDirectory=$oldDirectory
  $safe=[IO.Path]::GetFullPath($external);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if(-not $safe.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($safe).StartsWith('cf-git-exe-')){throw 'Unsafe Git fixture cleanup'}
  if([IO.Directory]::Exists($safe)){Remove-Item -LiteralPath $safe -Recurse -Force}
  RemoveFixture $r
 }
}
if($Case -in @('All','Gate')){
 foreach($change in @('blocker','decision')){
  $f=LightFixture ('audit-gate-'+$change);$r=$f.root
  try{
   Assert ((Test-ControlFlowGate $r $f.run Completion).status -ceq 'PASS') 'StableDirectGatePasses'
   & $module {
    param($Change)
    $script:AuditGateChange=$Change;$script:AuditGateCalls=0;$script:AuditGateFired=$false
    $script:AuditGateOriginal=(Get-Item Function:Get-CFRunSource).ScriptBlock
    function script:Get-CFRunSource {
     param([string]$RepoRoot,[string]$RunPath,$State)
     if((Get-PSCallStack)[1].Command -ceq 'Test-ControlFlowGate'){
      $script:AuditGateCalls++
      if($script:AuditGateCalls -eq 2 -and -not $script:AuditGateFired){
       $script:AuditGateFired=$true
       if($script:AuditGateChange -ceq 'blocker'){Update-ControlFlowRun $RepoRoot $RunPath @{type='blocker';id='audit-open';status='OPEN';text='Concurrent blocker'}|Out-Null}
       else{
        $packet=(Get-ControlFlowPlanningContext $RepoRoot $RunPath).artifacts['review-packet']
        Update-ControlFlowRun $RepoRoot $RunPath @{type='phase_review';artifact_ref=$packet;target_id='C1';judge='human';verdict='REJECTED';assurance='manual';user_decision_ref='fixture:concurrent rejection'}|Out-Null
       }
      }
     }
     & $script:AuditGateOriginal @PSBoundParameters
    }
   } $change
   try{$gate=Test-ControlFlowGate $r $f.run Completion;$fired=& $module {$script:AuditGateFired}}
   finally{& $module {Set-Item Function:script:Get-CFRunSource $script:AuditGateOriginal}}
   Assert ($fired -and $gate.status -ceq 'FAIL' -and 'LEDGER_CHANGED_DURING_GATE' -cin $gate.reasons) ('ConcurrentLedgerChangeRejectsPASS:'+ $change)
  }finally{RemoveFixture $r}
 }
}
Write-Output "audit-runtime $Case : $script:Count assertions passed"
$global:LASTEXITCODE=0
