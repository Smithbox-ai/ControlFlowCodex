[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('Pilot','Release','Diagnostics')][string]$Suite='Pilot',
    [ValidateSet('native','v4')][string]$Variant='v4',
    [ValidateSet('stdout-jsonl')][string]$Collector='stdout-jsonl',
    [switch]$ValidateOnly,[switch]$PrepareOnly,[switch]$Execute,
    [string]$OutDir,[string]$Model,[ValidateSet('none','minimal','low','medium','high','xhigh','max')][string]$Effort,[string]$HostLabel,
    [string]$CliPath,[string]$ExpectedCliVersion,
    [int]$MaxWallSeconds,[int]$MaxTotalWallSeconds,[long]$MaxTokens,[long]$MaxTotalTokens,[int]$MaxToolCalls,[int]$MaxRuns,
    [int]$Trials=1,[int]$MaxResumes=2,
    [ValidateSet('on-request','never')][string]$ApprovalPolicy='never',
    [ValidateSet('user','auto_review')][string]$ApprovalReviewer='user',
    [ValidateSet('workspace-write','read-only')][string]$Sandbox='workspace-write',
    [ValidateSet('elevated','unelevated')][string]$WindowsSandbox,
    [string]$SettingsPath,[string[]]$CaseIds,[string]$PluginRoot,
    [ValidatePattern('^[a-z0-9][a-z0-9_-]{0,95}$')][string]$MarketplaceName='controlflow-eval',
    [switch]$DiscoverOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'e2e-lib.ps1')
$Variant=$Variant.ToLowerInvariant();$Collector=$Collector.ToLowerInvariant()
$root=(Resolve-Path -LiteralPath $RepoRoot).Path
$cases=if($Suite -eq 'Diagnostics'){@(Get-E2EReleaseDiagnosticCases)}else{@(Get-E2ECases -RepoRoot $root -Suite $Suite)}
if($CaseIds){foreach($id in $CaseIds){if($id -notin $cases.id){throw "Unknown $Suite case: $id"}};$cases=@($cases | Where-Object {$_.id -in $CaseIds})}
foreach($c in $cases){
    if(-not $c.id -or -not $c.task -or $c.commit -notin @('none','required') -or $c.factory -ne 'declarative' -or (-not $c.expected.Count -and -not $c.oracle)){throw 'Invalid executable case'}
}
$modeCount=[int]$ValidateOnly.IsPresent+[int]$PrepareOnly.IsPresent+[int]$Execute.IsPresent+[int]$DiscoverOnly.IsPresent
if($modeCount -ne 1){throw 'Choose exactly one ValidateOnly, PrepareOnly, Execute or DiscoverOnly mode'}
if($ValidateOnly){$cases | Select-Object id,tier,pilot,commit | Format-Table | Out-String | Write-Output;Write-Output "VALID executable $Suite cases: $($cases.Count)";return}
if($PrepareOnly){
    if($Variant -cne 'v4' -or $Collector -cne 'stdout-jsonl' -or $Execute -or $DiscoverOnly){throw 'PrepareOnly requires V4 stdout-jsonl and excludes native execution/discovery'}
    if(-not $OutDir -or -not [IO.Path]::IsPathFullyQualified($OutDir) -or (Test-Path -LiteralPath $OutDir)){throw 'PrepareOnly requires a new absolute OutDir'}
    $out=[IO.Path]::GetFullPath($OutDir)
    Assert-E2EAdapterNoLinks $out;Assert-E2EAdapterNoLinks $root
    if($out -ceq $root -or $out.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'OutDir must be outside source checkout'}
    $pluginSource=if($PluginRoot){(Resolve-Path -LiteralPath $PluginRoot).Path}else{$root}
    Assert-E2EAdapterNoLinks $pluginSource
    [IO.Directory]::CreateDirectory($out)|Out-Null
    $prepared=@(foreach($case in $cases){
        $dir=Join-Path $out ('fixtures/'+(Get-E2EHash $case.id).Substring(0,16))
        $fixture=New-E2EFixture -Case $case -Directory (Join-Path $dir 'repo')
        $t=New-E2EV4Treatment -Case $case -FixtureRoot $fixture.root -TrialDirectory (Join-Path $dir 'treatment') -PluginRoot $pluginSource
        @{case_id=$case.id;fixture_hash=$fixture.fixture_hash;request_path=$t.request_path;request_sha256=$t.request_sha256;environment=$t.environment;prompt=$t.prompt}
    })
    $report=@{schema_version='2.0.0';variant='v4';collector=$Collector;prepared=$prepared;model_runs=0;protocol=(Get-E2EProtocolReadiness @{Variant=$Variant;Collector=$Collector});production_ready=$false}
    Write-E2EText (Join-Path $out 'prepared.json') ($report|ConvertTo-Json -Depth 20)
    Write-Output "PREPARED V4 fixtures: $($prepared.Count); model runs=0; execution BLOCKED by protocol capability: $out"
    return
}
# No native launch, authentication, profile, cache or history access may precede
# this unsupported-capability check. Model-free preparation is separate above.
$readiness=Get-E2EProtocolReadiness @{Variant=$Variant;Collector=$Collector}
throw ('BLOCKED before any CLI/model/session access: '+($readiness.missing -join ', '))