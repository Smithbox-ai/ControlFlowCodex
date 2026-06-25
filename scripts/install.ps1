<#
.SYNOPSIS
  Install or uninstall the ControlFlow for Codex plugin into the home-local
  plugin directory and marketplace manifest.

.PARAMETER HomeRoot
  Home root that contains the `plugins/` directory and `.agents/plugins/`
  marketplace. Defaults to $HOME.

.PARAMETER Uninstall
  Remove the installed plugin and its marketplace entry instead of installing.

.PARAMETER Force
  Replace an existing installation without prompting, or remove without
  prompting when uninstalling.
#>
param(
    [string]$HomeRoot = $HOME,
    [switch]$Uninstall,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$pluginName = "controlflow-codex"
$sourceRoot = Split-Path -Parent $PSScriptRoot
$targetPluginsDir = Join-Path $HomeRoot "plugins"
$targetPlugin = Join-Path $targetPluginsDir $pluginName
$marketplaceDir = Join-Path $HomeRoot ".agents\plugins"
$marketplacePath = Join-Path $marketplaceDir "marketplace.json"

if ($Uninstall) {
    if ((Test-Path $targetPlugin) -and -not $Force) {
        $answer = Read-Host "Remove $targetPlugin? Type YES to continue"
        if ($answer -ne "YES") {
            Write-Output "Uninstall cancelled."
            exit 0
        }
    }

    if (Test-Path $targetPlugin) {
        Remove-Item -LiteralPath $targetPlugin -Recurse -Force
        Write-Output "Removed $targetPlugin"
    } else {
        Write-Output "Plugin directory not found at $targetPlugin"
    }

    if (Test-Path $marketplacePath) {
        $marketplace = Get-Content $marketplacePath -Raw | ConvertFrom-Json
        $plugins = @($marketplace.plugins | Where-Object { $_.name -ne $pluginName })
        if ($null -eq $marketplace.PSObject.Properties["plugins"]) {
            $marketplace | Add-Member -NotePropertyName plugins -NotePropertyValue $plugins -Force
        } else {
            $marketplace.plugins = $plugins
        }
        $marketplace | ConvertTo-Json -Depth 8 | Set-Content $marketplacePath
        Write-Output "Removed $pluginName marketplace entry from $marketplacePath"
    } else {
        Write-Output "Marketplace file not found at $marketplacePath"
    }
    exit 0
}

# ── Install ────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Path $targetPluginsDir -Force | Out-Null
New-Item -ItemType Directory -Path $marketplaceDir -Force | Out-Null

if ((Test-Path $targetPlugin) -and -not $Force) {
    throw "Target plugin already exists at $targetPlugin. Re-run with -Force to replace it."
}

if (Test-Path $targetPlugin) {
    Remove-Item -LiteralPath $targetPlugin -Recurse -Force
}

Copy-Item -LiteralPath $sourceRoot -Destination $targetPlugin -Recurse -Force

if (Test-Path $marketplacePath) {
    $marketplace = Get-Content $marketplacePath -Raw | ConvertFrom-Json
} else {
    $marketplace = [pscustomobject]@{
        name      = "local-personal"
        interface = [pscustomobject]@{ displayName = "Local Personal Plugins" }
        plugins   = @()
    }
}

if (-not $marketplace.plugins) {
    $marketplace | Add-Member -NotePropertyName plugins -NotePropertyValue @() -Force
}

$existing = @($marketplace.plugins | Where-Object { $_.name -eq $pluginName })
$updatedPlugins = @($marketplace.plugins | Where-Object { $_.name -ne $pluginName })
$updatedPlugins += [pscustomobject]@{
    name     = $pluginName
    source   = [pscustomobject]@{
        source = "local"
        path   = "./plugins/$pluginName"
    }
    policy   = [pscustomobject]@{
        installation    = "AVAILABLE"
        authentication  = "ON_INSTALL"
    }
    category = "Coding"
}

$marketplace.plugins = $updatedPlugins
$marketplace | ConvertTo-Json -Depth 8 | Set-Content $marketplacePath

Write-Output "Installed $pluginName to $targetPlugin"
Write-Output "Updated marketplace at $marketplacePath"
if ($existing.Count -gt 0) {
    Write-Output "Existing marketplace entry was replaced."
}