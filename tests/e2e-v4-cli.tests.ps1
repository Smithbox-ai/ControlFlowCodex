param([string]$AdapterRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
$AdapterRoot=(Resolve-Path -LiteralPath $AdapterRoot).Path
. "$PSScriptRoot/../evals/e2e-lib.ps1"
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cf-v4-cli-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
$count=0
function Check($Value,$Name){if(-not $Value){throw "ASSERT: $Name"};$script:count++}
$pwsh=(Get-Process -Id $PID).Path
$runner=Join-Path $AdapterRoot 'evals/run-e2e.ps1'
try{
 $capture=Invoke-E2EProcess -Executable $pwsh -WorkingDirectory $temp -TimeoutSeconds 60 -Arguments @('-NoProfile','-File',$runner,'-RepoRoot',$AdapterRoot,'-PrepareOnly','-CaseIds','readme-title','-OutDir',(Join-Path $temp 'prepared'))
 Check ($capture.exit_code -eq 0 -and $capture.streams_complete -and $capture.cleanup_verified -and $capture.stdout -match 'model runs=0') 'PrepareOnlyCreatesRealV4TreatmentWithoutCliModelsOrSessions'
 $p=Get-Content (Join-Path $temp 'prepared/prepared.json') -Raw|ConvertFrom-Json -AsHashtable
 Check ($p.variant -ceq 'v4' -and $p.prepared.Count -eq 1 -and $p.model_runs -eq 0 -and -not $p.protocol.may_launch) 'PreparedManifestDoesNotImplyTrialAcceptance'
 $request=Get-Content $p.prepared[0].request_path -Raw|ConvertFrom-Json -AsHashtable
 Check ($request.contract_version -ceq '4.0.0' -and $request.initial_source_digest -match '^[a-f0-9]{64}$' -and $p.prepared[0].prompt -match 'Bind the run to the actual native thread ID') 'PreparedRequestHasActualSourceAndNativeBindingRequirements'
 $target=Join-Path $temp 'link-target';[IO.Directory]::CreateDirectory($target)|Out-Null
 $link=Join-Path $temp 'link';$linkType=if($IsWindows){'Junction'}else{'SymbolicLink'}
 New-Item -ItemType $linkType -Path $link -Target $target|Out-Null
 $capture=Invoke-E2EProcess -Executable $pwsh -WorkingDirectory $temp -TimeoutSeconds 60 -Arguments @('-NoProfile','-File',$runner,'-RepoRoot',$AdapterRoot,'-PrepareOnly','-CaseIds','readme-title','-OutDir',(Join-Path $link 'evidence'))
 Check ($capture.exit_code -ne 0 -and -not (Test-Path (Join-Path $target 'evidence'))) 'LinkedOutDirRejectedBeforeAnyFixtureWrite'
 foreach($variant in @('native','v4','NATIVE','V4')){
  $collector=if($variant -ceq $variant.ToUpperInvariant()){'STDOUT-JSONL'}else{'stdout-jsonl'}
  $capture=Invoke-E2EProcess -Executable $pwsh -WorkingDirectory $temp -TimeoutSeconds 20 -Arguments @('-NoProfile','-File',$runner,'-RepoRoot',$AdapterRoot,'-Variant',$variant,'-Collector',$collector,'-Execute','-CliPath',(Join-Path $temp 'must-not-run.exe'))
  Check ($capture.exit_code -ne 0 -and $capture.stderr -match 'BLOCKED before any CLI/model/session access') "ExecuteCannotBypassProtocolBlock:$variant"
 }
 foreach($mode in @('Execute','DiscoverOnly')){
  $blockedOut=Join-Path $temp ('must-not-create-'+$mode)
  $capture=Invoke-E2EProcess -Executable $pwsh -WorkingDirectory $temp -TimeoutSeconds 20 -Arguments @('-NoProfile','-File',$runner,'-RepoRoot',$AdapterRoot,('-'+$mode),'-CliPath',(Join-Path $temp 'must-not-run.exe'),'-OutDir',$blockedOut)
  Check ($capture.exit_code -ne 0 -and $capture.stderr -match 'BLOCKED before any CLI/model/session access' -and -not (Test-Path $blockedOut)) "DefaultV4BlocksBeforeCliAndEvidenceWrites:$mode"
 }
 foreach($retired in @(@('-Variant','v3'),@('-Collector','legacy-rollout'),@('-SessionRoot',(Join-Path $temp 'must-not-read')))){
  $capture=Invoke-E2EProcess -Executable $pwsh -WorkingDirectory $temp -TimeoutSeconds 20 -Arguments (@('-NoProfile','-File',$runner,'-RepoRoot',$AdapterRoot,'-Execute')+$retired)
  Check ($capture.exit_code -ne 0) 'RetiredTreatmentCollectorAndSessionParameterRejected'
 }
 $workflow=[IO.File]::ReadAllText((Join-Path $AdapterRoot '.github/workflows/eval.yml'))
 Check ($workflow -notmatch 'npm install|OPENAI_API_KEY|codex login|\.codex/sessions|prepare-e2e-cache' -and $workflow -match 'Collector stdout-jsonl -Execute') 'WorkflowBlocksBeforeInstallationAuthenticationHistoryAndCache'
 $native=@{schema_version='2.0.0';variant='native';case_id='fixture';tier='SMALL';trial=1;provenance=@{}}
 $v4=@{schema_version='2.0.0';variant='v4';case_id='fixture';tier='SMALL';trial=1;provenance=@{}}
 foreach($arm in @('native','v4')){Write-E2EText (Join-Path $temp "$arm/summary.json") (@{results=@($(if($arm -ceq 'native'){$native}else{$v4}))}|ConvertTo-Json -Depth 15)}
 $comparison=Join-Path $temp 'comparison.json'
 $capture=Invoke-E2EProcess -Executable $pwsh -WorkingDirectory $temp -TimeoutSeconds 20 -Arguments @('-NoProfile','-File',(Join-Path $AdapterRoot 'evals/compare-e2e.ps1'),'-NativeDirectory',(Join-Path $temp 'native'),'-V4Directory',(Join-Path $temp 'v4'),'-OutputPath',$comparison)
 Check ($capture.exit_code -eq 0) 'ExplicitV4ComparisonCli'
 $report=Get-Content $comparison -Raw|ConvertFrom-Json -AsHashtable
 Check ($report.treatment -ceq 'v4' -and $report.status -ceq 'BLOCKED' -and $null -eq $report.success_delta -and -not $report.production_ready) 'ComparisonCannotInventBenefitFromBlockedRecords'
 Write-Output "e2e-v4-cli: $count assertions passed"
}finally{
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($full).StartsWith('cf-v4-cli-')){throw 'Unsafe test cleanup'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
$global:LASTEXITCODE=0
