[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('Pilot','Release','Diagnostics')][string]$Suite='Pilot',
    [ValidateSet('native','v3')][string]$Variant='native',
    [switch]$ValidateOnly,[switch]$Execute,
    [string]$OutDir,[string]$Model,[ValidateSet('none','minimal','low','medium','high','xhigh','max')][string]$Effort,[string]$HostLabel,
    [string]$CliPath,[string]$ExpectedCliVersion,[string]$SessionRoot,
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
$root=(Resolve-Path -LiteralPath $RepoRoot).Path
$cases=if($Suite -eq 'Diagnostics'){@(Get-E2EReleaseDiagnosticCases)}else{@(Get-E2ECases -RepoRoot $root -Suite $Suite)}
if($CaseIds){foreach($id in $CaseIds){if($id -notin $cases.id){throw "Unknown $Suite case: $id"}};$cases=@($cases | Where-Object {$_.id -in $CaseIds})}
foreach($c in $cases){
    if(-not $c.id -or -not $c.task -or $c.commit -notin @('none','required') -or $c.factory -ne 'declarative' -or (-not $c.expected.Count -and -not $c.oracle)){throw 'Invalid executable case'}
}
if($ValidateOnly){$cases | Select-Object id,tier,pilot,commit | Format-Table | Out-String | Write-Output;Write-Output "VALID executable $Suite cases: $($cases.Count)";return}
if(-not $Execute -and -not $DiscoverOnly){throw 'Model execution requires explicit -Execute; use -ValidateOnly for unpaid validation'}
foreach($name in @('OutDir','Model','Effort','HostLabel','CliPath','ExpectedCliVersion','SessionRoot')){if(-not (Get-Variable $name -ValueOnly)){throw "Explicit -$name is required"}}
foreach($name in @('MaxWallSeconds','MaxTotalWallSeconds','MaxTokens','MaxTotalTokens','MaxToolCalls','MaxRuns','Trials')){if((Get-Variable $name -ValueOnly) -le 0){throw "Positive explicit -$name budget is required"}}
if($MaxResumes -lt 0){throw 'MaxResumes cannot be negative'}
Assert-E2ENativePolicy @{ApprovalPolicy=$ApprovalPolicy;ApprovalReviewer=$ApprovalReviewer;Sandbox=$Sandbox;WindowsSandbox=$WindowsSandbox}
if(Test-Path -LiteralPath $OutDir){throw 'OutDir must be new; existing evidence is immutable'}
$out=[IO.Path]::GetFullPath($OutDir)
# An output directory outside the source checkout prevents ancestor project
# instructions and repository plugin config from contaminating fixture trials.
if($out.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'OutDir must be outside source checkout for isolated fixtures'}
[IO.Directory]::CreateDirectory($out) | Out-Null
$settings=@()
if($SettingsPath){$settings=@(Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json);if(@($settings | Where-Object {$_ -isnot [string]}).Count){throw 'SettingsPath must contain a JSON array of provider key=value strings'}}
$config=@{Model=$Model;Effort=$Effort;HostLabel=$HostLabel;CliPath=$CliPath;CliPrefix=@();ExpectedCliVersion=$ExpectedCliVersion;SessionRoot=(Resolve-Path -LiteralPath $SessionRoot).Path;MaxTokens=$MaxTokens;MaxToolCalls=$MaxToolCalls;MaxWallSeconds=$MaxWallSeconds;MaxResumes=$MaxResumes;ApprovalPolicy=$ApprovalPolicy;ApprovalReviewer=$ApprovalReviewer;Sandbox=$Sandbox;WindowsSandbox=$WindowsSandbox;Variant=$Variant;Settings=$settings;Environment=@{};MarketplaceRoot='';MarketplaceName=$MarketplaceName;PluginDigest=''}
# Immutable local marketplace: only this copied plugin enters either arm.
$pluginSource=if($PluginRoot){(Resolve-Path -LiteralPath $PluginRoot).Path}else{$root}
$market=Join-Path $out 'marketplace';$snapshot=Join-Path $market 'plugins/controlflow-codex'
[IO.Directory]::CreateDirectory($snapshot) | Out-Null
foreach($rel in @('plugin.json','.codex-plugin','skills','schemas','scripts','hooks','assets','plans/templates')){
    $source=Join-Path $pluginSource $rel
    if(Test-Path -LiteralPath $source){$target=Join-Path $snapshot $rel;[IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null;Copy-Item -LiteralPath $source -Destination $target -Recurse}
}
@{name=$MarketplaceName;interface=@{displayName='Isolated ControlFlow evaluation'};plugins=@(@{name='controlflow-codex';source=@{source='local';path='./plugins/controlflow-codex'};policy=@{installation='AVAILABLE';authentication='ON_INSTALL'};category='Coding'})} | ConvertTo-Json -Depth 10 | ForEach-Object {Write-E2EText (Join-Path $market '.agents/plugins/marketplace.json') $_}
$inventory=@(Get-ChildItem -LiteralPath $snapshot -Recurse -File -Force | Sort-Object FullName | ForEach-Object {[ordered]@{path=[IO.Path]::GetRelativePath($snapshot,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$config.PluginDigest=Get-E2EPluginDigest -Inventory $inventory;$config.MarketplaceRoot=$market
$inventory | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'plugin-inventory.json') -Encoding utf8
$configArgs=@(Get-E2EConfigArguments $config)
$policyPreflight=Invoke-E2EPolicyPreflight -Config $config -Directory (Join-Path $out 'policy-preflight')
if(-not $policyPreflight.verified){throw 'Exact native exec/resume empty-stdin preflight failed; no model run started; inspect policy-preflight evidence'}
$discovery=Invoke-E2EProcess -Executable $CliPath -Arguments @(Get-E2EDiscoveryArguments $config) -WorkingDirectory $out -TimeoutSeconds 30 -Environment @{}
Write-E2EText (Join-Path $out 'plugin-discovery.json') $discovery.stdout
Write-E2EText (Join-Path $out 'plugin-discovery.stderr.txt') $discovery.stderr
@{exit_code=$discovery.exit_code;timed_out=$discovery.timed_out;wall_ms=$discovery.wall_ms;streams_complete=$discovery.streams_complete;cleanup_verified=$discovery.cleanup_verified;stdout_bytes=[Text.Encoding]::UTF8.GetByteCount($discovery.stdout);stderr_bytes=[Text.Encoding]::UTF8.GetByteCount($discovery.stderr)} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'plugin-discovery.process.json') -Encoding utf8
$discoveryState=Test-E2EPluginDiscovery -Capture $discovery -Config $config
$discoveryState | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $out 'plugin-discovery.state.json') -Encoding utf8
if(-not $discoveryState.verified){throw "Isolated local marketplace discovery failed: $($discoveryState.reason) (exit=$($discovery.exit_code), timeout=$($discovery.timed_out), wall_ms=$($discovery.wall_ms)); no model run started"}
if($Variant -eq 'v3'){
    $version=[string]$discoveryState.record.version
    if($version -cnotmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?(?:\+[A-Za-z0-9.-]+)?$'){throw 'Native installed candidate version missing or invalid'}
    $config.NativeEntryPath=Join-Path (Split-Path $config.SessionRoot -Parent) "plugins/cache/$MarketplaceName/controlflow-codex/$version/skills/controlflow/SKILL.md"
    $config.NativeEntryContents=[IO.File]::ReadAllText((Join-Path $snapshot 'skills/controlflow/SKILL.md'))
    if(-not (Test-Path -LiteralPath $config.NativeEntryPath) -or [IO.File]::ReadAllText($config.NativeEntryPath) -cne $config.NativeEntryContents){throw 'Native cached entry differs from immutable candidate snapshot'}
    Write-E2EText (Join-Path $out 'native-entry.expected.json') (@{name='controlflow-codex:controlflow';path=$config.NativeEntryPath;contents_sha256=Get-E2EHash $config.NativeEntryContents;proof='native SDK selected skill user fragment required; explicit-only entries are hidden from prompt catalog'} | ConvertTo-Json)
}
# Debug rendering loads differently from exec --ignore-user-config. Keep this
# diagnostic evidence; only the actual native exec rollout proves isolation.
$promptCheck=Invoke-E2EProcess -Executable $CliPath -Arguments (@('--no-daemon','debug','prompt-input')+$configArgs+@('Configuration isolation check.')) -WorkingDirectory $out -TimeoutSeconds 30 -Environment @{}
@{exit_code=$promptCheck.exit_code;timed_out=$promptCheck.timed_out;wall_ms=$promptCheck.wall_ms;stdout_bytes=[Text.Encoding]::UTF8.GetByteCount($promptCheck.stdout);stderr_bytes=[Text.Encoding]::UTF8.GetByteCount($promptCheck.stderr)} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'prompt-input.process.json') -Encoding utf8
Write-E2EText (Join-Path $out 'prompt-input.stderr.txt') $promptCheck.stderr
Write-E2EText (Join-Path $out 'prompt-input.json') $promptCheck.stdout
$promptText='';$debugParsed=$false
if($promptCheck.exit_code -eq 0){try{$render=$promptCheck.stdout | ConvertFrom-Json -Depth 100;$promptText=($render | ForEach-Object {$_.content | ForEach-Object text}) -join "`n";$debugParsed=$true}catch{}}
@{discovery_filter=$MarketplaceName;plugin_identity=$discoveryState.plugin_identity;debug_prompt_parsed=$debugParsed;debug_prompt_loader='loads user configuration; diagnostic only';debug_ambient_catalog_detected=$promptText -match 'superpowers:|controlflow-codex@local-personal|sites:sites-building';actual_exec_rollout_verification_required=$true} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'preflight-diagnostics.json') -Encoding utf8
@{project_trust='untrusted';suite=$Suite;variant=$Variant;model=$Model;effort=$Effort;host=$HostLabel;cli_version=$ExpectedCliVersion;approval_policy=$ApprovalPolicy;approvals_reviewer=$ApprovalReviewer;sandbox=$Sandbox;windows_sandbox=$WindowsSandbox;marketplace_name=$MarketplaceName;plugin_identity=$discoveryState.plugin_identity;max_tokens=$MaxTokens;max_total_tokens=$MaxTotalTokens;max_tool_calls=$MaxToolCalls;max_wall_seconds=$MaxWallSeconds;max_total_wall_seconds=$MaxTotalWallSeconds;max_runs=$MaxRuns;trials=$Trials;case_ids=@($cases.id);settings=$settings;prompt_sha256=Get-E2EHash $promptCheck.stdout;plugin_sha256=$config.PluginDigest;started_at=[datetime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $out 'manifest.json') -Encoding utf8
if($DiscoverOnly){Write-Output "VALID isolated CLI marketplace discovery; debug prompt is diagnostic only: $out";return}
$results=[Collections.Generic.List[object]]::new();$totalTokens=0L;$clock=[Diagnostics.Stopwatch]::StartNew();$stopped=''
for($trial=1;$trial -le $Trials;$trial++){
    foreach($case in $cases){
        if($results.Count -ge $MaxRuns){$stopped='run-count budget';break}
        if($totalTokens -ge $MaxTotalTokens){$stopped='total token budget';break}
        if($clock.Elapsed.TotalSeconds -ge $MaxTotalWallSeconds){$stopped='total wall budget';break}
        $config.MaxTokens=[Math]::Min($MaxTokens,$MaxTotalTokens-$totalTokens)
        $config.MaxWallSeconds=[Math]::Min($MaxWallSeconds,$MaxTotalWallSeconds-$clock.Elapsed.TotalSeconds)
        # Cwd carries no diagnostic case title into the model prompt.
        $opaque=(Get-E2EHash $case.id).Substring(0,16)
        $dir=Join-Path $out "trials/fixture-$opaque/$trial"
        Write-Output "START $Variant $($case.id) trial $trial"
        $r=Invoke-E2ETrial -Case $case -Config $config -TrialDirectory $dir
        if($Suite -eq 'Diagnostics'){$r=Set-E2EDiagnosticCollectionResult -Result $r -Case $case -Fixture @{root=(Join-Path $dir 'repo')}}
        $r.trial=$trial;$r | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $dir 'result.json') -Encoding utf8
        $results.Add($r);if($r.usage){$totalTokens+=$r.usage.total_tokens}
        Write-Output "RESULT $($r.status): $($r.reason); tokens=$($r.usage.total_tokens)"
        if($r.api_rejected_before_generation -or $r.configuration_rejected_before_generation){$stopped='API or CLI rejected configuration before generation; no model trial consumed';break}
        # Unknown usage makes remaining spend unknowable. Stop the whole arm.
        if(-not $r.usage -or -not $r.usage.complete){$stopped='usage incomplete; remaining spend unknown';break}
    }
    if($stopped){break}
}
$summary=@{variant=$Variant;suite=$Suite;success_count=@($results | Where-Object status -eq 'success').Count;failed_count=@($results | Where-Object status -eq 'failed').Count;incomplete_count=@($results | Where-Object {$_.status -eq 'incomplete' -and -not $_.api_rejected_before_generation -and -not $_.configuration_rejected_before_generation}).Count;false_completion_count=@($results | Where-Object false_completion).Count;total_tokens=$totalTokens;wall_ms=$clock.ElapsedMilliseconds;stopped_reason=$stopped;production_ready=$false}
$counts=Measure-E2EArmCounts -Results $results.ToArray() -RequestedCount ($cases.Count*$Trials)
foreach($key in $counts.Keys){$summary[$key]=$counts[$key]}
@{summary=$summary;results=$results.ToArray()} | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding utf8
Write-Output ($summary | ConvertTo-Json -Compress)
