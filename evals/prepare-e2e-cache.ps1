[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$ExpectedInventoryPath,
    [Parameter(Mandatory)][string]$NativeCacheRoot,
    [Parameter(Mandatory)][ValidateLength(1,96)][ValidatePattern('^controlflow-eval-[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$MarketplaceName,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [switch]$Cleanup,
    [switch]$ProcessesStopped,
    [string]$ProcessEvidenceRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Only shared deterministic filesystem guards are reused. No native CLI,
# profile/config setter, trust API, authentication or model invocation occurs.
Import-Module (Join-Path $PSScriptRoot '../scripts/ControlFlow.Package.psm1') -Force -DisableNameChecking
$comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
if($MarketplaceName -cnotmatch '^controlflow-eval-[a-z0-9]+(?:-[a-z0-9]+)*$'){throw 'Evaluation marketplace must have an exact lowercase owned namespace'}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}
function Json($Value){return ConvertTo-Json -InputObject $Value -Depth 40 -Compress}
function Config-State {
    if(Test-Path -LiteralPath $config -PathType Leaf){return [ordered]@{exists=$true;sha256=Hash $config}}
    if(Test-Path -LiteralPath $config){throw 'Config path must be a file or absent'}
    return [ordered]@{exists=$false;sha256=$null}
}
function Same-Config($Before){if((Json (Config-State)) -cne (Json $Before)){throw 'Protected global config changed; no unchanged-config claim is possible'}}
function Write-New([string]$Path,[string]$Text){
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Tree([string]$Root,[switch]$RuntimeOnly){
    Assert-ControlFlowTree $Root
    $items=[Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force)){
        $relative=[IO.Path]::GetRelativePath($Root,$item.FullName).Replace('\','/')
        if($RuntimeOnly -and $relative -notmatch '^(plugin\.json|\.codex-plugin(?:/.*)?|assets(?:/.*)?|skills(?:/.*)?|schemas(?:/.*)?|scripts(?:/.*)?|hooks(?:/.*)?|plans(?:/templates(?:/.*)?)?)$'){throw "Not a frozen runtime-only payload: $relative"}
        if($RuntimeOnly -and @($relative.Split('/')|Where-Object {$_ -in @('.git','.vs','.agents','.codex','.aws','node_modules')}).Count){throw "Working state is not a runtime payload: $relative"}
        if($item.PSIsContainer){$items.Add($relative,[ordered]@{path=$relative;kind='directory';sha256=$null})}
        else{$items.Add($relative,[ordered]@{path=$relative;kind='file';sha256=Hash $item.FullName})}
    }
    return @($items.Values)
}
function Files($Inventory){return @($Inventory|Where-Object kind -eq 'file'|ForEach-Object {[ordered]@{path=$_.path;sha256=$_.sha256}})}
function Expected([string]$Path){
    $raw=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -AsHashtable -Depth 20
    if($raw -isnot [array] -or $raw.Count -eq 0){throw 'Expected runtime file inventory must be a nonempty array'}
    $items=[Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($row in $raw){
        if($row.path -isnot [string] -or $row.path -notmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$' -or @($row.path.Split('/')|Where-Object {$_ -in @('.','..')}).Count -or $row.sha256 -isnot [string] -or $row.sha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Invalid expected path/SHA256 inventory row'}
        if($items.ContainsKey($row.path)){throw 'Duplicate runtime inventory path'}
        $items.Add($row.path,[ordered]@{path=$row.path;sha256=$row.sha256.ToLowerInvariant()})
    }
    return @($items.Values)
}
function Verify-Files([string]$Root,$Expected){if((Json (Files @(Tree $Root -RuntimeOnly))) -cne (Json $Expected)){throw 'Exact runtime source/cache file inventory differs from declared SHA256 bytes'}}
function Verify-Owned([string]$Root,$Record){
    $null=Assert-ControlFlowContained $Root $cache
    Assert-ControlFlowTree $Root
    $marker=Get-Content -LiteralPath (Join-Path $Root '.controlflow-e2e-owner.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 10
    if($marker.token -cne $Record.token -or $marker.marketplace -cne $MarketplaceName -or $marker.market_root -cne $target){throw 'Exact cache ownership marker does not match receipt'}
    if((Json @(Tree $Root)) -cne (Json $Record.owned_tree)){throw 'Owned cache contents/directories changed; refusing recursive deletion'}
}
function Process-Evidence($Record){
    $root=Resolve-ControlFlowPath $ProcessEvidenceRoot
    if(-not (Test-Path -LiteralPath $root -PathType Container) -or $root.Equals($cache,$comparison) -or (Test-ControlFlowContained $root $cache)){throw 'Process evidence must be an existing directory outside native cache'}
    Assert-ControlFlowTree $root
    $files=[Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
    function Read-Evidence([string]$Relative,[switch]$Raw){
        $path=Assert-ControlFlowContained (Join-Path $root $Relative) $root
        if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing owned-process evidence: $Relative"}
        if(-not $files.ContainsKey($Relative)){$files.Add($Relative,[ordered]@{path=$Relative;sha256=Hash $path})}
        if($Raw){return $null}
        return Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 40
    }
    function Complete-Process([string]$Relative){
        $capture=Read-Evidence $Relative
        if($capture.cleanup_verified -isnot [bool] -or -not $capture.cleanup_verified -or $capture.streams_complete -isnot [bool] -or -not $capture.streams_complete){throw "Owned process stream/cleanup incomplete: $Relative"}
    }
    $manifest=Read-Evidence 'manifest.json'
    if($manifest.variant -cne 'v3' -or $manifest.marketplace_name -cne $MarketplaceName -or $manifest.plugin_identity -cne ('controlflow-codex@'+$MarketplaceName)){throw 'Process cohort does not bind this exact v3 cache namespace'}
    try{$started=[datetimeoffset]$manifest.started_at;$created=[datetimeoffset]$Record.created_at}catch{throw 'Process/cache freshness timestamp is invalid'}
    if($started -lt $created -or $started -gt [datetimeoffset]::UtcNow.AddMinutes(1)){throw 'Process cohort does not postdate this cache preparation'}
    $policy=Read-Evidence 'policy-preflight/result.json'
    foreach($mode in @('initial','resume')){
        $checks=@($policy.checks|Where-Object mode -ceq $mode)
        if($checks.Count -ne 1 -or $checks[0].cleanup_verified -isnot [bool] -or -not $checks[0].cleanup_verified -or $checks[0].streams_complete -isnot [bool] -or -not $checks[0].streams_complete){throw "Missing/incomplete owned $mode policy process"}
        $null=Read-Evidence "policy-preflight/$mode.argv.json"
    }
    foreach($relative in @('plugin-discovery.process.json','prompt-input.process.json')){Complete-Process $relative}
    $trials=Join-Path $root 'trials'
    if(Test-Path -LiteralPath $trials){
        foreach($fixture in @(Get-ChildItem -LiteralPath $trials -Directory -Force)){
          foreach($trial in @(Get-ChildItem -LiteralPath $fixture.FullName -Directory -Force)){
            if($trial.Name -cnotmatch '^[1-9][0-9]*$'){throw 'Malformed owned trial evidence directory'}
            $raw=Join-Path $trial.FullName 'raw'
            $relative=[IO.Path]::GetRelativePath($root,$raw).Replace('\','/')
            Complete-Process ($relative+'/version.process.json')
            $result=Read-Evidence ([IO.Path]::GetRelativePath($root,(Join-Path $trial.FullName 'result.json')).Replace('\','/'))
            if($result.provenance.marketplace_name -cne $MarketplaceName -or $result.provenance.plugin_identity -cne $manifest.plugin_identity){throw 'Trial process namespace differs from prepared cache'}
            if($result.resumes -isnot [int] -and $result.resumes -isnot [long] -or $result.resumes -lt 0){throw 'Trial turn count is missing/invalid'}
            for($turn=0;$turn -le $result.resumes;$turn++){Complete-Process ($relative+"/turn-$turn.process.json")}
            foreach($file in @(Get-ChildItem -LiteralPath $raw -File -Force|Where-Object {$_.Name -cmatch '^turn-[0-9]+\.(argv\.json|jsonl)$'})){
                $null=Read-Evidence ($relative+'/'+$file.Name) -Raw
                Complete-Process ($relative+'/'+($file.Name -replace '\.(argv\.json|jsonl)$','.process.json'))
            }
          }
        }
    }
    foreach($row in $files.Values){if((Hash (Join-Path $root $row.path)) -cne $row.sha256){throw 'Owned-process evidence changed during verification'}}
    return [ordered]@{root=$root;inventory=@($files.Values)}
}
$cache=Resolve-ControlFlowPath $NativeCacheRoot
if(-not (Test-Path -LiteralPath $cache -PathType Container)){throw 'Native cache base must already exist; helper never writes other cache roots'}
if($cache.Equals([IO.Path]::GetPathRoot($cache),$comparison)){throw 'Native cache base must not be a filesystem root'}
$target=Assert-ControlFlowContained (Join-Path $cache $MarketplaceName) $cache
$config=Resolve-ControlFlowPath $ConfigPath
$receipt=Resolve-ControlFlowPath $ReceiptPath
$digest=Resolve-ControlFlowPath ($receipt+'.sha256')
if((Test-ControlFlowContained $receipt $cache) -or (Test-ControlFlowContained $config $cache) -or $receipt.Equals($config,$comparison) -or $digest.Equals($config,$comparison)){throw 'Config and audit receipts must be outside native cache and distinct'}
$receiptParent=Split-Path $receipt -Parent
if(-not (Test-Path -LiteralPath $receiptParent -PathType Container)){throw 'Audit receipt parent must already exist'}
$before=Config-State
if($Cleanup){
    if(-not $ProcessesStopped){throw 'Cleanup requires -ProcessesStopped after the owned trial processes have exited'}
    if((Get-Content -LiteralPath $digest -Raw).Trim() -cne (Hash $receipt)){throw 'Ownership receipt SHA256 mismatch'}
    $record=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json -AsHashtable -Depth 40
    if($record.schema_version -cne '1.0.0' -or -not $record.provisioned -or $record.cleaned -or $record.native_cache_root -cne $cache -or $record.market_root -cne $target -or $record.marketplace -cne $MarketplaceName -or $record.config_path -cne $config){throw 'Receipt does not own the exact requested cache namespace/config'}
    if((Json $record.config_pre) -cne (Json $before)){throw 'Global config differs from provisioned baseline'}
    $processEvidence=if($ProcessEvidenceRoot){Process-Evidence $record}else{$null}
    Verify-Owned $target $record
    Same-Config $before
    Remove-ControlFlowTree $target $cache
    Same-Config $before
    $record.cleaned=$true;$record.cleaned_at=[datetime]::UtcNow.ToString('o');$record.config_post=Config-State
    if($processEvidence){$record.process_cleanup_evidence=$processEvidence}
    $auditTemp=Assert-ControlFlowContained (Join-Path $receiptParent ('.cache-cleanup-'+[guid]::NewGuid().ToString('N')+'.json')) $receiptParent
    $digestTemp=$auditTemp+'.sha256'
    try{
        Write-New $auditTemp (Json $record);Write-New $digestTemp (Hash $auditTemp)
        [IO.File]::Move($auditTemp,$receipt,$true);[IO.File]::Move($digestTemp,$digest,$true)
    }finally{foreach($path in @($auditTemp,$digestTemp)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}}
    Write-Output "CLEANED exact owned evaluation namespace $MarketplaceName; config/auth were not written"
    return
}
if(-not $SourceRoot -or -not $ExpectedInventoryPath){throw 'Preparation requires frozen SourceRoot and ExpectedInventoryPath'}
if((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $receipt) -or (Test-Path -LiteralPath $digest)){throw 'Native namespace or ownership receipt already exists; replacement is prohibited'}
$source=Resolve-ControlFlowPath $SourceRoot
$inventoryPath=Resolve-ControlFlowPath $ExpectedInventoryPath
if(-not (Test-Path -LiteralPath $source -PathType Container) -or $source.Equals($cache,$comparison) -or (Test-ControlFlowContained $source $cache) -or (Test-ControlFlowContained $cache $source) -or (Test-ControlFlowContained $receipt $source)){throw 'Frozen source/cache/audit paths must not overlap'}
$expected=@(Expected $inventoryPath)
Verify-Files $source $expected
foreach($required in @('plugin.json','.codex-plugin/plugin.json','skills/controlflow/SKILL.md')){if($required -cnotin $expected.path){throw 'Frozen runtime snapshot is missing its plugin/entry identity'}}
$manifest=Get-Content -LiteralPath (Join-Path $source 'plugin.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 40
$compat=Get-Content -LiteralPath (Join-Path $source '.codex-plugin/plugin.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 40
if($manifest.name -cne 'controlflow-codex' -or $manifest.version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$' -or $manifest.name -cne $compat.name -or $manifest.version -cne $compat.version){throw 'Frozen native plugin identity/version mismatch'}
$nonce=[guid]::NewGuid().ToString('N')
$stage=Assert-ControlFlowContained (Join-Path $cache ('.'+$MarketplaceName+'-stage-'+$nonce)) $cache
$pluginStage=Join-Path $stage ('controlflow-codex/'+$manifest.version)
$auditTemp=Assert-ControlFlowContained (Join-Path $receiptParent ('.cache-prepare-'+$nonce+'.json')) $receiptParent
$digestTemp=$auditTemp+'.sha256';$record=$null;$published=$false;$receiptPublished=$false;$digestPublished=$false;$stageCreated=$false;$auditHash=$null
try{
    if(Test-Path -LiteralPath $stage){throw 'Unique staging path unexpectedly exists'}
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop|Out-Null;$stageCreated=$true
    Write-New (Join-Path $stage '.controlflow-e2e-owner.json') (Json ([ordered]@{token=$nonce;marketplace=$MarketplaceName;market_root=$target}))
    [IO.Directory]::CreateDirectory((Split-Path $pluginStage -Parent))|Out-Null
    Copy-Item -LiteralPath $source -Destination $pluginStage -Recurse -Force
    Verify-Files $pluginStage $expected
    $record=[ordered]@{schema_version='1.0.0';token=$nonce;marketplace=$MarketplaceName;native_cache_root=$cache;market_root=$target;plugin_root=(Join-Path $target ('controlflow-codex/'+$manifest.version));source_root=$source;expected_inventory_path=$inventoryPath;expected_inventory_sha256=Hash $inventoryPath;provisioned=$true;cleaned=$false;created_at=[datetime]::UtcNow.ToString('o');inventory=$expected;owned_tree=@(Tree $stage);config_path=$config;config_pre=$before;config_post=Config-State}
    Same-Config $before
    Write-New $auditTemp (Json $record);$auditHash=Hash $auditTemp;Write-New $digestTemp $auditHash
    # Directory.Move is a same-volume no-replace rename. Move-Item would nest
    # the stage inside a destination directory created after its prior check.
    $null=Assert-ControlFlowContained $stage $cache;$null=Assert-ControlFlowContained $target $cache
    Assert-ControlFlowTree $stage
    [IO.Directory]::Move($stage,$target);$published=$true
    Verify-Owned $target $record
    Verify-Files (Join-Path $target ('controlflow-codex/'+$manifest.version)) $expected
    [IO.File]::Move($auditTemp,$receipt);$receiptPublished=$true
    [IO.File]::Move($digestTemp,$digest);$digestPublished=$true
    Same-Config $before
    Write-Output "PREPARED native cache-only namespace $MarketplaceName ($($expected.Count) files); no config/trust/auth writes"
}catch{
    # Roll back only paths created by this invocation, after exact ownership and
    # byte verification; unexpected changes make cleanup fail closed.
    if($published){Verify-Owned $target $record;Remove-ControlFlowTree $target $cache}
    if($receiptPublished){if((Hash $receipt) -cne $auditHash){throw 'Published receipt changed; refusing rollback deletion'};Remove-Item -LiteralPath $receipt -Force}
    if($digestPublished){if((Get-Content -LiteralPath $digest -Raw).Trim() -cne $auditHash){throw 'Published receipt digest changed; refusing rollback deletion'};Remove-Item -LiteralPath $digest -Force}
    throw
}finally{
    if($stageCreated -and (Test-Path -LiteralPath $stage)){if($record){Verify-Owned $stage $record};Remove-ControlFlowTree $stage $cache}
    foreach($path in @($auditTemp,$digestTemp)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}
}
