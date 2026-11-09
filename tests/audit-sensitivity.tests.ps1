param([ValidateSet('All','terminal','identity','git','gate','output')][string]$Only='All')
. "$PSScriptRoot/core-test-helpers.ps1"
Import-Module "$script:CoreRoot/scripts/ControlFlow.Package.psm1" -Force -DisableNameChecking
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cf-audit-mutants-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
$mutants=@(
 @{id='terminal';file='scripts/lib/Ledger.ps1';before="return `$State.schema_version -ceq '4.0.0' -and (`$State.status -cin @('COMPLETED','CANCELLED') -or (`$State.ContainsKey('lifecycle_closed') -and `$State.lifecycle_closed))";after='return $false';test='tests/audit-runtime.tests.ps1';case='Terminal';expected='ASSERT: TerminalInterruptIgnored'}
 @{id='identity';file='scripts/lib/Ledger.ps1';before='$checkIds=@(Get-CFUniqueSorted @($Artifact.payload.scenarios|ForEach-Object {$_.check_refs}))';after='$checkIds=@($Artifact.payload.scenarios|ForEach-Object {$_.check_refs}|Sort-Object -Unique)';test='tests/audit-runtime.tests.ps1';case='Identity';expected='ASSERT: CaseDistinctQABindingsRetained'}
 @{id='git';file='scripts/lib/Git.ps1';before='$executable=Resolve-CFGitExecutable $Root';after="`$executable='git'";test='tests/audit-runtime.tests.ps1';case='Git';expected='ASSERT: (CwdSentinelNeverSelected|RepositoryPathGitRejected)'}
 @{id='gate';file='scripts/lib/Gates.ps1';before="`$reasons.Add('LEDGER_CHANGED_DURING_GATE')";after='[void]$finalState';test='tests/audit-runtime.tests.ps1';case='Gate';expected='ASSERT: ConcurrentLedgerChangeRejectsPASS'}
 @{id='output';file='scripts/lib/Ledger.ps1';before="`$outputLimit=if(`$state.schema_version -ceq '4.0.0'){33554432}else{0}";after='$outputLimit=0';test='tests/capture-limits-v4.tests.ps1';case='Overflow';expected='ASSERT: OverflowFails:out'}
)
$killed=0
try{
 foreach($m in $mutants){
  if($Only -cne 'All' -and $m.id -cne $Only){continue}
  $copy=Join-Path $temp $m.id
  Copy-ControlFlowPackage $script:CoreRoot $copy
  $path=Join-Path $copy $m.file;$original=[IO.File]::ReadAllText($path)
  Assert ($original.Contains($m.before)) ('MutationAnchorPresent:'+ $m.id)
  [IO.File]::WriteAllText($path,$original.Replace($m.before,$m.after))
  $errors=$null;[Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errors)|Out-Null
  Assert ($errors.Count -eq 0) ('MutantSyntaxValid:'+ $m.id)
  $output=@(& (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -NoProfile -File (Join-Path $copy $m.test) -Case $m.case 2>&1)
  $exitCode=$LASTEXITCODE
  Assert ($exitCode -ne 0 -and ($output -join [Environment]::NewLine) -match $m.expected) ('MutationDetectedAtExpectedBehavior:'+ $m.id)
  $killed++
  Write-Output ("CONTROLLED_MUTATION {0}: killed by {1} {2}" -f $m.id,$m.test,$m.case)
 }
 $expected=if($Only -ceq 'All'){5}else{1}
 Assert ($killed -eq $expected) 'EverySelectedMutationKilled'
 Write-Output "audit-sensitivity: $killed/$expected controlled mutations detected; not a Stryker score"
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($full).StartsWith('cf-audit-mutants-')){throw 'Unsafe mutation cleanup'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
$global:LASTEXITCODE=0
