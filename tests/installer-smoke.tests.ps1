$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $repoRoot "scripts/install.ps1"
$temporaryHome = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-codex-install-smoke-" + [guid]::NewGuid().ToString("N"))
$pluginPath = Join-Path (Join-Path $temporaryHome "plugins") "controlflow-codex"
$marketplacePath = Join-Path (Join-Path (Join-Path $temporaryHome ".agents") "plugins") "marketplace.json"

$installerContent = Get-Content -LiteralPath $installerPath -Raw
$portableMarketplaceDirectory = 'Join-Path (Join-Path $HomeRoot ".agents") "plugins"'
if ($installerContent -notmatch [regex]::Escape($portableMarketplaceDirectory)) {
    throw "Installer must construct the marketplace directory with nested Join-Path calls"
}

try {
    & $installerPath -HomeRoot $temporaryHome -Force

    if (-not (Test-Path -LiteralPath $pluginPath -PathType Container)) {
        throw "Installer did not create plugin directory: $pluginPath"
    }
    if (-not (Test-Path -LiteralPath $marketplacePath -PathType Leaf)) {
        throw "Installer did not create marketplace manifest: $marketplacePath"
    }

    $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
    $installedEntries = @($marketplace.plugins | Where-Object { $_.name -eq "controlflow-codex" })
    if ($installedEntries.Count -ne 1) {
        throw "Installer marketplace entry count must be 1, found $($installedEntries.Count)"
    }

    & $installerPath -HomeRoot $temporaryHome -Uninstall -Force

    if (Test-Path -LiteralPath $pluginPath) {
        throw "Uninstaller did not remove plugin directory: $pluginPath"
    }

    $marketplaceAfterUninstall = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
    $remainingEntries = @($marketplaceAfterUninstall.plugins | Where-Object { $_.name -eq "controlflow-codex" })
    if ($remainingEntries.Count -ne 0) {
        throw "Uninstaller did not remove marketplace entry"
    }
} finally {
    if (Test-Path -LiteralPath $temporaryHome) {
        Remove-Item -LiteralPath $temporaryHome -Recurse -Force
    }
}

Write-Output "VALID installer smoke contract"
