$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$helper=Join-Path $repo 'evals/prepare-e2e-cache.ps1'
$count=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "ASSERT: $Message"};$script:count++}
function Throws([scriptblock]$Body,[string]$Message){$thrown=$false;try{& $Body|Out-Null}catch{$thrown=$true};Assert $thrown $Message}
function Text([string]$Path,[string]$Value){[IO.Directory]::CreateDirectory((Split-Path $Path -Parent))|Out-Null;[IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false))}
Assert (Test-Path -LiteralPath $helper -PathType Leaf) 'cache-only dev preparation helper exists (feature missing)'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('cf-e2e-cache-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch)|Out-Null
try{
    $source=Join-Path $scratch 'frozen-runtime'
    Text (Join-Path $source 'plugin.json') '{"name":"controlflow-codex","version":"3.0.0-rc.1"}'
    Text (Join-Path $source '.codex-plugin/plugin.json') '{"name":"controlflow-codex","version":"3.0.0-rc.1"}'
    Text (Join-Path $source 'skills/controlflow/SKILL.md') '# Frozen entry'
    Text (Join-Path $source 'scripts/check.ps1') '# Frozen check'
    $inventory=@(Get-ChildItem -LiteralPath $source -Recurse -Force -File|ForEach-Object {[ordered]@{path=[IO.Path]::GetRelativePath($source,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
    $inventoryPath=Join-Path $scratch 'inventory.json';Text $inventoryPath (ConvertTo-Json -InputObject $inventory -Depth 5)
    $cache=Join-Path $scratch 'fake-native-cache';[IO.Directory]::CreateDirectory($cache)|Out-Null
    Text (Join-Path $cache 'other-market/foreign.txt') 'another installed plugin'
    $config=Join-Path $scratch 'fake-profile/config.toml';Text $config "[test_settings]`ntheme = 'blue'`n"
    $auth=Join-Path $scratch 'fake-profile/auth.json';Text $auth '{"test":"unchanged"}'
    $configHash=(Get-FileHash -LiteralPath $config).Hash;$authHash=(Get-FileHash -LiteralPath $auth).Hash
    $receipt=Join-Path $scratch 'receipt.json';$market='controlflow-eval-owned-smoke'
    $params=@{SourceRoot=$source;ExpectedInventoryPath=$inventoryPath;NativeCacheRoot=$cache;MarketplaceName=$market;ConfigPath=$config;ReceiptPath=$receipt}
    & $helper @params|Out-Null
    $record=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json -AsHashtable -Depth 30
    $target=Join-Path $cache $market;$payload=Join-Path $target 'controlflow-codex/3.0.0-rc.1'
    Assert ($record.provisioned -and -not $record.cleaned -and (Test-Path -LiteralPath $payload)) 'cache uses native marketplace/plugin/version layout'
    Assert ($record.inventory.Count -eq 4 -and (Test-Path -LiteralPath ($receipt+'.sha256'))) 'exact payload hashes and receipt digest are preserved'
    foreach($file in $inventory){Assert ((Get-FileHash -LiteralPath (Join-Path $payload $file.path)).Hash.ToLowerInvariant() -ceq $file.sha256) "copied bytes are exact: $($file.path)"}
    Assert ((Get-FileHash -LiteralPath $config).Hash -ceq $configHash -and (Get-FileHash -LiteralPath $auth).Hash -ceq $authHash) 'preparation writes neither config nor auth'
    Assert ([IO.File]::ReadAllText((Join-Path $cache 'other-market/foreign.txt')) -ceq 'another installed plugin') 'other native cache namespaces are untouched'
    Throws {& $helper @params} 'existing namespace/receipt cannot be overwritten'
    $cleanup=@{NativeCacheRoot=$cache;MarketplaceName=$market;ConfigPath=$config;ReceiptPath=$receipt;Cleanup=$true}
    Throws {& $helper @cleanup} 'cleanup requires explicit assertion that owned processes stopped'
    & $helper @cleanup -ProcessesStopped|Out-Null
    Assert (-not (Test-Path -LiteralPath $target)) 'cleanup removes only the exact owned namespace'
    $cleaned=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json -AsHashtable -Depth 30
    Assert ($cleaned.cleaned -and $cleaned.config_pre.sha256 -ceq $cleaned.config_post.sha256) 'cleanup retains a config-unchanged receipt'
    Assert ((Get-FileHash -LiteralPath $config).Hash -ceq $configHash -and (Get-FileHash -LiteralPath $auth).Hash -ceq $authHash -and (Test-Path -LiteralPath (Join-Path $cache 'other-market/foreign.txt'))) 'scoped cleanup preserves auth/config/other plugins'
    Throws {& $helper @cleanup -ProcessesStopped} 'cleaned receipt is not reusable'
    $params.ReceiptPath=Join-Path $scratch 'bad-hash-receipt.json';$params.MarketplaceName='controlflow-eval-bad-hash'
    $wrong=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $inventory -Depth 5) -AsHashtable;$wrong[0].sha256='0'*64;Text $inventoryPath (ConvertTo-Json -InputObject $wrong -Depth 5)
    Throws {& $helper @params} 'source hash mismatch refuses before cache writes'
    Assert (-not (Test-Path -LiteralPath (Join-Path $cache $params.MarketplaceName)) -and -not (Test-Path -LiteralPath $params.ReceiptPath)) 'failed validation publishes neither cache nor receipt'
    Text $inventoryPath (ConvertTo-Json -InputObject $inventory -Depth 5)
    # A debugger action simulates an external writer at the last config check,
    # after cache and receipt publication, without production failure hooks.
    $params.MarketplaceName='controlflow-eval-late-failure';$params.ReceiptPath=Join-Path $scratch 'late-failure.json'
    $lastCheck=@(Select-String -LiteralPath $helper -Pattern '^\s*Same-Config \$before\s*$')[-1].LineNumber
    $breakpoint=Set-PSBreakpoint -Script $helper -Line $lastCheck -Action {[IO.File]::WriteAllText($config,'# simulated unrelated config writer')}
    try{Throws {& $helper @params} 'late unrelated config drift rejects preparation'}finally{Remove-PSBreakpoint -Breakpoint $breakpoint;Text $config "[test_settings]`ntheme = 'blue'`n"}
    Assert (-not (Test-Path -LiteralPath (Join-Path $cache $params.MarketplaceName)) -and -not (Test-Path -LiteralPath $params.ReceiptPath) -and -not (Test-Path -LiteralPath ($params.ReceiptPath+'.sha256'))) 'late preparation failure rolls back exact owned cache and published receipts'
    $params.MarketplaceName='controlflow-eval-publish-race';$params.ReceiptPath=Join-Path $scratch 'publish-race.json'
    $raceTarget=Join-Path $cache $params.MarketplaceName
    $global:cfE2ECacheRaceTarget=$raceTarget
    $publishScript=$helper;$publishPattern='^\s*\[IO.Directory\]::Move\(\$stage'
    if(Select-String -LiteralPath $helper -Pattern '^\s*Move-ControlFlowTree \$stage'){$publishScript=Join-Path $repo 'scripts/ControlFlow.Package.psm1';$publishPattern='^\s*Move-Item -LiteralPath \$src'}
    $publishLine=@(Select-String -LiteralPath $publishScript -Pattern $publishPattern)[-1].LineNumber
    $breakpoint=Set-PSBreakpoint -Script $publishScript -Line $publishLine -Action {[IO.Directory]::CreateDirectory($global:cfE2ECacheRaceTarget)|Out-Null;[IO.File]::WriteAllText((Join-Path $global:cfE2ECacheRaceTarget 'foreign.txt'),'foreign namespace created by another actor')}
    try{Throws {& $helper @params} 'publication refuses a target created after prior-path checks'}finally{Remove-PSBreakpoint -Breakpoint $breakpoint;Remove-Variable -Name cfE2ECacheRaceTarget -Scope Global}
    Assert ([IO.File]::ReadAllText((Join-Path $raceTarget 'foreign.txt')) -ceq 'foreign namespace created by another actor' -and @(Get-ChildItem -LiteralPath $raceTarget -Force).Count -eq 1 -and -not (Test-Path -LiteralPath $params.ReceiptPath)) 'racing foreign namespace is preserved without nested stage or published receipt'
    Remove-ControlFlowTree $raceTarget $scratch
    Text (Join-Path $source 'evals/forbidden.txt') 'development data'
    Throws {& $helper @params} 'full repository/development files are not runtime payloads'
    Remove-ControlFlowTree (Join-Path $source 'evals') $scratch
    Text (Join-Path $source 'scripts/.git/foreign.txt') 'nested working state'
    $working=@($inventory)+@([ordered]@{path='scripts/.git/foreign.txt';sha256=(Get-FileHash -LiteralPath (Join-Path $source 'scripts/.git/foreign.txt')).Hash.ToLowerInvariant()})
    Text $inventoryPath (ConvertTo-Json -InputObject $working -Depth 5)
    Throws {& $helper @params} 'working state under a runtime prefix is refused even with a declared hash'
    Remove-ControlFlowTree (Join-Path $source 'scripts/.git') $scratch
    Text $inventoryPath (ConvertTo-Json -InputObject $inventory -Depth 5)
    $params.MarketplaceName='../escape'
    Throws {& $helper @params} 'marketplace traversal is rejected'
    $params.MarketplaceName='ControlFlow-eval-uppercase'
    Throws {& $helper @params} 'marketplace names must match the exact lowercase namespace'
    $params.MarketplaceName='controlflow-eval-'+('a'*100)
    Throws {& $helper @params} 'marketplace namespace is bounded by the native identity length'
    $params.MarketplaceName='controlflow-eval-source-root';$params.NativeCacheRoot=$source
    Throws {& $helper @params} 'overlapping runtime source/cache roots are refused'
    $params.NativeCacheRoot=$cache
    $params.MarketplaceName='controlflow-eval-mutated';$params.ReceiptPath=Join-Path $scratch 'mutated.json'
    & $helper @params|Out-Null
    $cleanup.MarketplaceName=$params.MarketplaceName;$cleanup.ReceiptPath=$params.ReceiptPath
    $target=Join-Path $cache $params.MarketplaceName;$payload=Join-Path $target 'controlflow-codex/3.0.0-rc.1'
    Text (Join-Path $payload 'scripts/check.ps1') '# mutated cache'
    Throws {& $helper @cleanup -ProcessesStopped} 'modified cache bytes cannot be recursively deleted'
    Text (Join-Path $payload 'scripts/check.ps1') '# Frozen check'
    Text (Join-Path $target 'foreign.txt') 'new foreign contents'
    Throws {& $helper @cleanup -ProcessesStopped} 'unexpected namespace file prevents cleanup'
    Remove-Item -LiteralPath (Join-Path $target 'foreign.txt')
    $recordText=[IO.File]::ReadAllText($params.ReceiptPath);Text $params.ReceiptPath ($recordText+"`n")
    Throws {& $helper @cleanup -ProcessesStopped} 'changed ownership receipt fails digest verification'
    Text $params.ReceiptPath $recordText
    & $helper @cleanup -ProcessesStopped|Out-Null
    $params.MarketplaceName='controlflow-eval-config-drift';$params.ReceiptPath=Join-Path $scratch 'config-drift.json'
    & $helper @params|Out-Null
    $cleanup.MarketplaceName=$params.MarketplaceName;$cleanup.ReceiptPath=$params.ReceiptPath
    Text $config '# changed by another actor'
    Throws {& $helper @cleanup -ProcessesStopped} 'global config drift cannot pass an unchanged-config claim'
    Text $config "[test_settings]`ntheme = 'blue'`n"
    & $helper @cleanup -ProcessesStopped|Out-Null
    $params.MarketplaceName='controlflow-eval-missing-config';$params.ReceiptPath=Join-Path $scratch 'missing-config.json';$params.ConfigPath=Join-Path $scratch 'fake-profile/absent.toml'
    & $helper @params|Out-Null
    Assert (-not (Test-Path -LiteralPath $params.ConfigPath)) 'an absent config remains absent'
    & $helper -NativeCacheRoot $cache -MarketplaceName $params.MarketplaceName -ConfigPath $params.ConfigPath -ReceiptPath $params.ReceiptPath -Cleanup -ProcessesStopped|Out-Null
    $params.ConfigPath=$config;$params.MarketplaceName='controlflow-eval-process-evidence';$params.ReceiptPath=Join-Path $scratch 'process-evidence.json'
    & $helper @params|Out-Null
    $evidence=Join-Path $scratch 'v3-evidence';$target=Join-Path $cache $params.MarketplaceName
    $cleanup=@{NativeCacheRoot=$cache;MarketplaceName=$params.MarketplaceName;ConfigPath=$config;ReceiptPath=$params.ReceiptPath;Cleanup=$true;ProcessesStopped=$true;ProcessEvidenceRoot=$evidence}
    Throws {& $helper @cleanup} 'missing process evidence refuses cache deletion'
    Assert (Test-Path -LiteralPath $target) 'unverified process cleanup keeps the owned cache intact'
    $manifest=[ordered]@{variant='v3';marketplace_name=$params.MarketplaceName;plugin_identity=('controlflow-codex@'+$params.MarketplaceName);started_at=[datetime]::UtcNow.ToString('o')}
    Text (Join-Path $evidence 'manifest.json') (ConvertTo-Json -InputObject $manifest)
    Text (Join-Path $evidence 'policy-preflight/result.json') '{"checks":[{"mode":"initial","cleanup_verified":true,"streams_complete":true},{"mode":"resume","cleanup_verified":true,"streams_complete":true}]}'
    foreach($mode in @('initial','resume')){Text (Join-Path $evidence "policy-preflight/$mode.argv.json") '[]'}
    $complete='{"cleanup_verified":true,"streams_complete":true}'
    foreach($file in @('plugin-discovery.process.json','prompt-input.process.json','trials/fixture-fake/1/raw/version.process.json','trials/fixture-fake/1/raw/turn-0.process.json')){Text (Join-Path $evidence $file) $complete}
    Text (Join-Path $evidence 'trials/fixture-fake/1/raw/turn-0.argv.json') '[]'
    Text (Join-Path $evidence 'trials/fixture-fake/1/raw/turn-0.jsonl') "{`"type`":`"thread.started`"}`n{`"type`":`"turn.completed`"}`n"
    Text (Join-Path $evidence 'trials/fixture-fake/1/result.json') (ConvertTo-Json -InputObject @{resumes=0;provenance=@{marketplace_name=$params.MarketplaceName;plugin_identity=$manifest.plugin_identity}})
    Text (Join-Path $evidence 'trials/fixture-fake/1/raw/turn-0.process.json') '{"cleanup_verified":false,"streams_complete":true}'
    Throws {& $helper @cleanup} 'a surviving owned boundary prevents cache cleanup'
    Text (Join-Path $evidence 'trials/fixture-fake/1/raw/turn-0.process.json') $complete
    Remove-Item -LiteralPath (Join-Path $evidence 'trials/fixture-fake/1/raw/turn-0.process.json')
    Throws {& $helper @cleanup} 'argv/raw turn requires its exact owned-process receipt'
    Text (Join-Path $evidence 'trials/fixture-fake/1/raw/turn-0.process.json') $complete
    $manifest.started_at='2000-01-01T00:00:00Z';Text (Join-Path $evidence 'manifest.json') (ConvertTo-Json -InputObject $manifest)
    Throws {& $helper @cleanup} 'stale process cohort cannot certify current cache cleanup'
    $manifest.started_at=[datetime]::UtcNow.ToString('o');$manifest.marketplace_name='controlflow-eval-another';Text (Join-Path $evidence 'manifest.json') (ConvertTo-Json -InputObject $manifest)
    Throws {& $helper @cleanup} 'another cache namespace cannot certify current cleanup'
    $manifest.marketplace_name=$params.MarketplaceName;Text (Join-Path $evidence 'manifest.json') (ConvertTo-Json -InputObject $manifest)
    & $helper @cleanup|Out-Null
    $cleaned=Get-Content -LiteralPath $params.ReceiptPath -Raw|ConvertFrom-Json -AsHashtable -Depth 30
    Assert ($cleaned.cleaned -and $cleaned.process_cleanup_evidence.root -ceq $evidence -and $cleaned.process_cleanup_evidence.inventory.Count -ge 8) 'verified process receipts are hashed into preserved cleanup evidence'
    $params.ConfigPath=$config;$params.MarketplaceName='controlflow-eval-link';$params.ReceiptPath=Join-Path $scratch 'linked.json'
    $link=Join-Path $cache $params.MarketplaceName;$linked=$false
    try{New-Item -ItemType SymbolicLink -Path $link -Target $source -ErrorAction Stop|Out-Null;$linked=$true}catch{if(-not $IsWindows){throw}}
    if($linked){Throws {& $helper @params} 'linked native namespace is refused without following it';Remove-Item -LiteralPath $link}
    Assert (@(Get-ChildItem -LiteralPath $cache -Force|Where-Object Name -like '.*-stage-*').Count -eq 0) 'no transaction staging directories survive normal/refused operations'
    Write-Output "VALID isolated cache-only preparation: $count assertions"
}finally{
    $full=[IO.Path]::GetFullPath($scratch);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside temporary root'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
