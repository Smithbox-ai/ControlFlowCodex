<#
.SYNOPSIS
Install or uninstall a validated ControlFlow package transactionally.
.DESCRIPTION
Stages and validates the shared package inventory before replacing an owned
installation. Marketplace publication uses an atomic file rename. On failure
the prior plugin directory is restored; unrelated marketplace entries survive.
#>
param(
    [string]$HomeRoot = $HOME,
    [string]$PluginName = 'controlflow-codex',
    [switch]$Uninstall,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ControlFlow.Package.psm1') -Force

if ($PluginName -cnotmatch '^[a-z0-9][a-z0-9_-]{0,63}$' -or $PluginName -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])$') { throw 'PluginName must be a lowercase safe single directory name (not a reserved device name)' }
$sourceRoot = Resolve-ControlFlowPath (Split-Path -Parent $PSScriptRoot)
$homeDir = Resolve-ControlFlowPath $HomeRoot
$pluginsDir = Assert-ControlFlowContained (Join-Path $homeDir 'plugins') $homeDir
$target = Assert-ControlFlowContained (Join-Path $pluginsDir $PluginName) $pluginsDir
$marketplaceDir = Assert-ControlFlowContained (Join-Path $homeDir '.agents/plugins') $homeDir
$marketplacePath = Assert-ControlFlowContained (Join-Path $marketplaceDir 'marketplace.json') $marketplaceDir
if ($sourceRoot -eq $target -or (Test-ControlFlowContained $target $sourceRoot) -or (Test-ControlFlowContained $sourceRoot $target)) { throw 'Source and installation target overlap' }

# Parse existing registration before creating, moving or deleting plugin files.
$hadMarketplace = Test-Path -LiteralPath $marketplacePath
$marketplaceSnapshot = if ($hadMarketplace -and (Test-Path -LiteralPath $marketplacePath -PathType Leaf)) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($marketplacePath)) } else { $null }
if (Test-Path -LiteralPath $marketplacePath) {
    if (-not (Test-Path -LiteralPath $marketplacePath -PathType Leaf)) { throw 'Marketplace path must be a file' }
    $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json -AsHashtable
    if ($marketplace -isnot [Collections.IDictionary] -or -not $marketplace.ContainsKey('plugins') -or $marketplace.plugins -isnot [array]) { throw 'Marketplace must contain a plugins array' }
    foreach ($entry in $marketplace.plugins) {
        if ($entry -isnot [Collections.IDictionary] -or -not $entry.ContainsKey('name') -or $entry.name -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.name)) { throw 'Marketplace plugin entry must have a name' }
    }
} else {
    $marketplace = @{ name = 'local-personal'; interface = @{ displayName = 'Local Personal Plugins' }; plugins = @() }
}

# Keep this inode persistent: deleting a released lock could let a waiter lock
# an old inode while another writer creates and locks a new one.
New-Item -ItemType Directory -Path $marketplaceDir -Force | Out-Null
$lockPath = Assert-ControlFlowContained (Join-Path $marketplaceDir '.controlflow-install.lock') $marketplaceDir
$installationLock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $marketplaceExistsNow = Test-Path -LiteralPath $marketplacePath
    if ($marketplaceExistsNow -ne $hadMarketplace) { throw 'Marketplace changed during installer initialization; retry the operation' }
    if ($hadMarketplace -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($marketplacePath)) -cne $marketplaceSnapshot) { throw 'Marketplace changed during installer initialization; retry the operation' }

$sourceManifest = Get-Content -LiteralPath (Join-Path $sourceRoot 'plugin.json') -Raw | ConvertFrom-Json -AsHashtable
if (-not $sourceManifest.ContainsKey('name') -or $sourceManifest.name -ne 'controlflow-codex') { throw 'Source package has an invalid ControlFlow identity' }
$hadTarget = Test-Path -LiteralPath $target
if ($hadTarget) {
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw 'Existing plugin target must be a directory' }
    Assert-ControlFlowTree $target
    $ownedManifest = Join-Path $target 'plugin.json'
    if (-not (Test-Path -LiteralPath $ownedManifest -PathType Leaf)) { $ownedManifest = Join-Path $target '.codex-plugin/plugin.json' }
    if (-not (Test-Path -LiteralPath $ownedManifest -PathType Leaf)) { throw 'Existing plugin target is not owned by a plugin manifest' }
    $owned = Get-Content -LiteralPath $ownedManifest -Raw | ConvertFrom-Json -AsHashtable
    if (-not $owned.ContainsKey('name') -or $owned.name -cne $sourceManifest.name) { throw 'Existing plugin target belongs to a different plugin' }
    if (-not $Force) { throw 'Existing plugin target requires -Force to replace or uninstall' }
}

$marketplace.plugins = @($marketplace.plugins | Where-Object { $_.name -cne $PluginName })
if (-not $Uninstall) {
    $marketplace.plugins += @{ name = $PluginName; source = @{ source = 'local'; path = "./plugins/$PluginName" }; policy = @{ installation = 'AVAILABLE'; authentication = 'ON_INSTALL' }; category = 'Coding' }
    $null = Assert-ControlFlowPackage $sourceRoot
}
$id = [guid]::NewGuid().ToString('N')
$stage = Assert-ControlFlowContained (Join-Path $pluginsDir ".$PluginName-stage-$id") $pluginsDir
$backup = Assert-ControlFlowContained (Join-Path $pluginsDir ".$PluginName-backup-$id") $pluginsDir
$marketTemp = Assert-ControlFlowContained (Join-Path $marketplaceDir ".marketplace-$id.tmp") $marketplaceDir
$oldMoved = $false
$newMoved = $false
$published = $false
try {
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $marketplaceDir -Force | Out-Null
    if (-not $Uninstall) { Copy-ControlFlowPackage $sourceRoot $stage }
    # Prepare full registration before changing the installed directory.
    $marketplace | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $marketTemp -Encoding utf8
    if ($hadTarget) { Move-ControlFlowTree $target $backup $pluginsDir; $oldMoved = $true }
    if (-not $Uninstall) { Move-ControlFlowTree $stage $target $pluginsDir; $newMoved = $true }
    $null = Assert-ControlFlowContained $marketplacePath $marketplaceDir
    $null = Assert-ControlFlowContained $marketTemp $marketplaceDir
    [IO.File]::Move($marketTemp, $marketplacePath, $true)
    $published = $true
} catch {
    $failure = $_
    if (-not $published) {
        if ($newMoved) { Remove-ControlFlowTree $target $pluginsDir }
        if ($oldMoved) { Move-ControlFlowTree $backup $target $pluginsDir }
    }
    throw $failure
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-ControlFlowTree $stage $pluginsDir }
    if (Test-Path -LiteralPath $marketTemp) { $safeTemp = Assert-ControlFlowContained $marketTemp $marketplaceDir; Remove-Item -LiteralPath $safeTemp -Force }
}
# After publication, a backup cleanup failure must not roll back a valid new
# registration. Keep the recoverable backup and identify its path to the caller.
if ($published -and $oldMoved) {
    try { Remove-ControlFlowTree $backup $pluginsDir } catch { Write-Warning "Installed registration is valid; retained backup $backup ($($_.Exception.Message))" }
}
if ($Uninstall) { Write-Output "Uninstalled $PluginName" } else { Write-Output "Installed $PluginName to $target" }
$global:LASTEXITCODE = 0
} finally {
    $installationLock.Dispose()
}
