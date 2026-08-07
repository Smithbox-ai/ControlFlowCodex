<#
.SYNOPSIS
  Install or uninstall the ControlFlow for Codex plugin from this project
  checkout into the home-local plugin directory.

.DESCRIPTION
  Install is a clean reinstall: it first removes any previously installed
  plugin files at the target location, then copies the current shipped files
  from this project directory. This avoids orphaned files when files are
  renamed or removed between versions. Use -Uninstall to remove only.

  The shipped surface mirrors what the release workflow packages: .codex-plugin,
  assets, skills, schemas, scripts, plans/templates, plans/examples, tests,
  evals, README.md, CHANGELOG.md, LICENSE. .git, .vs, dist, and other working
  state are never copied.

.PARAMETER HomeRoot
  Home root that contains the plugins/ directory and .agents/plugins/
  marketplace manifest. Defaults to $HOME.

.PARAMETER PluginName
  Installed plugin directory name. Defaults to controlflow-codex.

.PARAMETER Uninstall
  Remove the installed plugin files and its marketplace entry instead of
  installing.

.PARAMETER Force
  Replace an existing installation without prompting, or remove without
  prompting when uninstalling.

.EXAMPLE
  pwsh -File scripts/install.ps1 -Force
  pwsh -File scripts/install.ps1 -Uninstall -Force
#>
param(
    [string]$HomeRoot = $HOME,

    [string]$PluginName = "controlflow-codex",

    [switch]$Uninstall,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$sourceRoot = Split-Path -Parent $PSScriptRoot
$targetPluginsDir = Join-Path $HomeRoot "plugins"
$targetPlugin = Join-Path $targetPluginsDir $PluginName
$marketplaceDir = Join-Path (Join-Path $HomeRoot ".agents") "plugins"
$marketplacePath = Join-Path $marketplaceDir "marketplace.json"

# Shipped surface (kept in sync with .github/workflows/release.yml).
$shippedItems = @(
    ".codex-plugin",
    "assets",
    "skills",
    "schemas",
    "scripts",
    "plans/templates",
    "plans/examples",
    "tests",
    "evals",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
)

function Remove-InstalledPluginFiles {
    if (Test-Path -LiteralPath $targetPlugin) {
        Remove-Item -LiteralPath $targetPlugin -Recurse -Force
        Write-Output "Removed existing plugin files at $targetPlugin"
    } else {
        Write-Output "No existing plugin files found at $targetPlugin"
    }
}

function Remove-MarketplaceEntry {
    if (-not (Test-Path -LiteralPath $marketplacePath)) {
        Write-Output "Marketplace file not found at $marketplacePath"
        return
    }
    $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
    $remaining = @()
    if ($null -ne $marketplace.PSObject.Properties["plugins"] -and $marketplace.plugins) {
        $remaining = @($marketplace.plugins | Where-Object { $_.name -ne $PluginName })
    }
    $marketplace.plugins = $remaining
    $marketplace | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $marketplacePath -Encoding utf8
    Write-Output "Removed $PluginName marketplace entry from $marketplacePath"
}

function Set-MarketplaceEntry {
    New-Item -ItemType Directory -Path $marketplaceDir -Force | Out-Null
    if (Test-Path -LiteralPath $marketplacePath) {
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
    } else {
        $marketplace = [pscustomobject]@{
            name      = "local-personal"
            interface = [pscustomobject]@{ displayName = "Local Personal Plugins" }
            plugins   = @()
        }
    }
    if (-not $marketplace.PSObject.Properties["plugins"]) {
        $marketplace | Add-Member -NotePropertyName plugins -NotePropertyValue @() -Force
    }
    $remaining = @($marketplace.plugins | Where-Object { $_.name -ne $PluginName })
    $remaining += [pscustomobject]@{
        name     = $PluginName
        source   = [pscustomobject]@{ source = "local"; path = "./plugins/$PluginName" }
        policy   = [pscustomobject]@{ installation = "AVAILABLE"; authentication = "ON_INSTALL" }
        category = "Coding"
    }
    $marketplace.plugins = $remaining
    $marketplace | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $marketplacePath -Encoding utf8
    Write-Output "Updated marketplace at $marketplacePath"
}

function Copy-ShippedFiles {
    New-Item -ItemType Directory -Path $targetPlugin -Force | Out-Null
    foreach ($item in $shippedItems) {
        $src = Join-Path $sourceRoot $item
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Output "Skipping missing source item: $item"
            continue
        }
        $dest = Join-Path $targetPlugin $item
        $destParent = Split-Path $dest -Parent
        if (-not (Test-Path -LiteralPath $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $destParent -Recurse -Force
    }
    Write-Output "Copied plugin files from $sourceRoot to $targetPlugin"
}

function Assert-InstallSmoke {
    $manifest = Join-Path $targetPlugin ".codex-plugin/plugin.json"
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw "Install smoke failed: missing $manifest"
    }
    try {
        $null = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    } catch {
        throw "Install smoke failed: plugin.json is not valid JSON: $($_.Exception.Message)"
    }
    $skillsDir = Join-Path $targetPlugin "skills"
    if (-not (Test-Path -LiteralPath $skillsDir) -or -not (Get-ChildItem -LiteralPath $skillsDir -Recurse -Filter SKILL.md)) {
        throw "Install smoke failed: no SKILL.md files under $skillsDir"
    }
    Write-Output "Install smoke OK: $targetPlugin"
}

if ($Uninstall) {
    if ((Test-Path -LiteralPath $targetPlugin) -and -not $Force) {
        $answer = Read-Host "Remove $targetPlugin? Type YES to continue"
        if ($answer -ne "YES") {
            Write-Output "Uninstall cancelled."
            exit 0
        }
    }
    Remove-InstalledPluginFiles
    Remove-MarketplaceEntry
    Write-Output "Uninstalled $PluginName"
    exit 0
}

if ((Test-Path -LiteralPath $targetPlugin) -and -not $Force) {
    throw "Target plugin already exists at $targetPlugin. Re-run with -Force to replace it (old files are removed first)."
}

Remove-InstalledPluginFiles
Copy-ShippedFiles
Set-MarketplaceEntry
Assert-InstallSmoke
Write-Output "Installed $PluginName to $targetPlugin"
