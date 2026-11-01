<#
.SYNOPSIS
Install or uninstall a validated ControlFlow package transactionally.
.DESCRIPTION
Stages and validates the shared package inventory before replacing an owned
installation. Marketplace publication uses an atomic file rename. On failure
the prior plugin directory is restored; unrelated marketplace entries survive.
Successful replacement/removal retains previous source and registration bytes
in a reported recovery directory. Omitted Flavor preserves an owned install.
#>
param(
    [string]$HomeRoot = $HOME,
    [string]$PluginName = 'controlflow-codex',
    [switch]$Uninstall,
    [switch]$Force,
    [ValidateSet('Universal','NativeLegacy', IgnoreCase=$false)][string]$Flavor = 'Universal',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$flavorExplicit = $PSBoundParameters.ContainsKey('Flavor')
Import-Module (Join-Path $PSScriptRoot 'ControlFlow.Package.psm1') -Force

if ($PluginName -cnotmatch '^[a-z0-9][a-z0-9_-]{0,63}$' -or $PluginName -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])$') { throw 'PluginName must be a lowercase safe single directory name (not a reserved device name)' }
$sourceRoot = Resolve-ControlFlowPath (Split-Path -Parent $PSScriptRoot)
$homeDir = Resolve-ControlFlowPath $HomeRoot
$pluginsDir = Assert-ControlFlowContained (Join-Path $homeDir 'plugins') $homeDir
$target = Assert-ControlFlowContained (Join-Path $pluginsDir $PluginName) $pluginsDir
$marketplaceDir = Assert-ControlFlowContained (Join-Path $homeDir '.agents/plugins') $homeDir
$marketplacePath = Assert-ControlFlowContained (Join-Path $marketplaceDir 'marketplace.json') $marketplaceDir
$pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$sameSourceTarget = $sourceRoot.Equals($target, $pathComparison)
if (($sameSourceTarget -or (Test-ControlFlowContained $target $sourceRoot) -or (Test-ControlFlowContained $sourceRoot $target)) -and -not ($Uninstall -and $sameSourceTarget)) { throw 'Source and installation target overlap' }

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

function Get-ExistingInstallTarget {
    if (Test-Path -LiteralPath $target) {
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw 'Existing plugin target must be a directory' }
        Assert-ControlFlowTree $target
        $ownedManifest = Join-Path $target 'plugin.json'
        $oldFlavor = 'Universal'
        if (-not (Test-Path -LiteralPath $ownedManifest -PathType Leaf)) { $ownedManifest = Join-Path $target '.codex-plugin/plugin.json'; $oldFlavor = 'NativeLegacy' }
        if (-not (Test-Path -LiteralPath $ownedManifest -PathType Leaf)) { throw 'Existing plugin target is not owned by a plugin manifest' }
        $owned = Get-Content -LiteralPath $ownedManifest -Raw | ConvertFrom-Json -AsHashtable
        if ($owned -isnot [Collections.IDictionary] -or -not $owned.ContainsKey('name') -or $owned.name -cne 'controlflow-codex') { throw 'Existing plugin target belongs to a different plugin' }
        return @{ exists = $true; flavor = $oldFlavor }
    }
    return @{ exists = $false; flavor = $null }
}
$existing = Get-ExistingInstallTarget
$flavorReason = 'default Universal for fresh install'
if ($flavorExplicit) { $flavorReason = 'explicit -Flavor' }
elseif ($existing.exists) { $Flavor = $existing.flavor; $flavorReason = 'preserved existing flavor' }
function Assert-TargetChoice($Info) {
    if ($Info.exists -and -not $Uninstall -and $Info.flavor -cne $Flavor -and -not $flavorExplicit) { throw 'Cross-flavor replacement requires explicit -Flavor and -Force' }
    if ($Info.exists -and -not $Force) { throw 'Existing plugin target requires -Force to replace or uninstall' }
}
Assert-TargetChoice $existing

$matching = @($marketplace.plugins | Where-Object { $_.name -ieq $PluginName })
foreach ($entry in $matching) {
    if ($entry.name -cne $PluginName -or -not $entry.ContainsKey('source') -or $entry.source -isnot [Collections.IDictionary] -or $entry.source.source -cne 'local' -or $entry.source.path -cne "./plugins/$PluginName") { throw 'Matching marketplace registration is foreign; refusing to replace or remove it' }
}
if ($matching.Count -gt 1) { throw 'Duplicate marketplace registrations require reconciliation before mutation' }
$ownedRegistration = if ($matching.Count -eq 1) { $matching[0] } else { $null }
if ($Uninstall -and -not $existing.exists -and -not $ownedRegistration) {
    Write-Output "Nothing to uninstall for $PluginName; no source or registration changes; cache/trust/config/run data unchanged"
    $global:LASTEXITCODE = 0
    return
}

$sourceFlavor = $null
if (-not $Uninstall) {
    $rootManifest = Join-Path $sourceRoot 'plugin.json'
    $sourceFlavor = if (Test-Path -LiteralPath $rootManifest) { 'Universal' } else { 'NativeLegacy' }
    if ($Flavor -ceq 'Universal' -and $sourceFlavor -ceq 'NativeLegacy') { throw 'NativeLegacy source cannot provide Universal; choose a Universal source or explicit -Flavor NativeLegacy' }
    $sourceManifest = Assert-ControlFlowPackage $sourceRoot -Flavor $sourceFlavor
    if ($sourceManifest.name -cne 'controlflow-codex') { throw 'Source package has an invalid ControlFlow identity' }
}
function Copy-SelectedPackage([string]$Destination) {
    Copy-ControlFlowPackage $sourceRoot $Destination -Flavor $sourceFlavor
    if ($Flavor -ceq 'NativeLegacy' -and $sourceFlavor -ceq 'Universal') {
        Remove-Item -LiteralPath (Assert-ControlFlowContained (Join-Path $Destination 'plugin.json') $Destination)
    }
    $null = Assert-ControlFlowPackage $Destination $sourceManifest.version -Flavor $Flavor
    foreach ($relative in Get-ControlFlowPackageFiles $sourceRoot -Flavor $sourceFlavor) {
        if ($Flavor -ceq 'NativeLegacy' -and $relative -ceq 'plugin.json') { continue }
        if ((Get-FileHash -LiteralPath (Join-Path $sourceRoot $relative)).Hash -cne (Get-FileHash -LiteralPath (Join-Path $Destination $relative)).Hash) { throw "Staged shared bytes differ: $relative" }
    }
}
if ($DryRun) {
    # Validate a format conversion in owned temporary staging; target, lock and
    # registration stay untouched. No source/module reads follow self-removal.
    if (-not $Uninstall -and $sourceFlavor -cne $Flavor) {
        $tempBase = Resolve-ControlFlowPath ([IO.Path]::GetTempPath())
        $validationStage = Assert-ControlFlowContained (Join-Path $tempBase ('controlflow-install-validation-' + [guid]::NewGuid().ToString('N'))) $tempBase
        try { Copy-SelectedPackage $validationStage } finally { if (Test-Path -LiteralPath $validationStage) { Remove-ControlFlowTree $validationStage $tempBase } }
    }
    Write-Output "DRY RUN $Flavor $(if($Uninstall){'uninstall'}else{'install'}) $PluginName to $target (selection: $flavorReason); no target/registration changes; callbacks NOT_RUN"
    $global:LASTEXITCODE = 0
    return
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

$currentTarget = Get-ExistingInstallTarget
if ($currentTarget.exists -ne $existing.exists -or ($currentTarget.exists -and $currentTarget.flavor -cne $existing.flavor)) { throw 'Installation changed during initialization; retry without silently reselecting flavor' }
Assert-TargetChoice $currentTarget
$hadTarget = $currentTarget.exists

$marketplace.plugins = @($marketplace.plugins | Where-Object { $_.name -cne $PluginName })
if (-not $Uninstall) {
    $registration = if ($ownedRegistration) { $ownedRegistration } else { @{ name = $PluginName; source = @{ source = 'local'; path = "./plugins/$PluginName" } } }
    $registration.name = $PluginName
    $registration.source.source = 'local'; $registration.source.path = "./plugins/$PluginName"
    if (-not $registration.ContainsKey('policy')) { $registration.policy = @{ installation = 'AVAILABLE'; authentication = 'ON_INSTALL' } }
    if (-not $registration.ContainsKey('category')) { $registration.category = 'Coding' }
    $marketplace.plugins += $registration
    $null = Assert-ControlFlowPackage $sourceRoot $sourceManifest.version -Flavor $sourceFlavor
}
$id = [guid]::NewGuid().ToString('N')
$stage = Assert-ControlFlowContained (Join-Path $pluginsDir ".$PluginName-stage-$id") $pluginsDir
$backupRoot = Assert-ControlFlowContained (Join-Path $pluginsDir ".$PluginName-backup-$id") $pluginsDir
$backup = Assert-ControlFlowContained (Join-Path $backupRoot 'source') $pluginsDir
$marketTemp = Assert-ControlFlowContained (Join-Path $marketplaceDir ".marketplace-$id.tmp") $marketplaceDir
$oldMoved = $false
$newMoved = $false
$published = $false
try {
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $marketplaceDir -Force | Out-Null
    if (-not $Uninstall) { Copy-SelectedPackage $stage }
    # Prepare full registration before changing the installed directory.
    $marketplace | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $marketTemp -Encoding utf8
    if ($hadTarget -or $hadMarketplace) {
        New-Item -ItemType Directory -Path $backupRoot | Out-Null
        if ($hadMarketplace) { [IO.File]::WriteAllBytes((Assert-ControlFlowContained (Join-Path $backupRoot 'marketplace.json') $pluginsDir), [Convert]::FromBase64String($marketplaceSnapshot)) }
        Write-Output "Recovery backup retained at $backupRoot"
    }
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
# Retain the complete prior source and registration, including unknown files.
# Native cache/trust and external run data are outside this installer's scope.
if ($Uninstall) { Write-Output "Uninstalled local source/registration for $PluginName (flavor $Flavor; selection: $flavorReason); cache/trust/config/run data unchanged" } else { Write-Output "Installed $PluginName to $target (flavor $Flavor; selection: $flavorReason; callbacks NOT_RUN)" }
$global:LASTEXITCODE = 0
} finally {
    $installationLock.Dispose()
}
