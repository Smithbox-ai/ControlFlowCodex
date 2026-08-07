$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $repoRoot "scripts/install.ps1"

if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Missing installer script: $installerPath"
}

function Invoke-Installer([string]$HomeRoot, [switch]$Uninstall, [switch]$Force) {
    $global:LASTEXITCODE = 0
    $params = @{ HomeRoot = $HomeRoot }
    if ($Uninstall) { $params["Uninstall"] = $true }
    if ($Force) { $params["Force"] = $true }
    $output = @()
    $caught = $null
    try {
        $output = @(& $installerPath @params 2>&1)
    } catch {
        $caught = $_
        $output = @($_.Exception.Message)
    }
    $exitCode = if ($null -ne $caught) { 1 } else { $global:LASTEXITCODE }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Assert-Path([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Installer smoke: missing $Label at $Path"
    }
}

function Assert-PathAbsent([string]$Path, [string]$Label) {
    if (Test-Path -LiteralPath $Path) {
        throw "Installer smoke: $Label should be absent but exists at $Path"
    }
}

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-install-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $tempHome -Force | Out-Null
    $plug = Join-Path $tempHome "plugins/controlflow-codex"
    $marketplace = Join-Path $tempHome ".agents/plugins/marketplace.json"

    # Fresh install.
    $result = Invoke-Installer $tempHome -Force
    if ($result.ExitCode -ne 0) { throw "Install failed: $($result.Output -join [Environment]::NewLine)" }

    Assert-Path (Join-Path $plug ".codex-plugin/plugin.json") "plugin manifest"
    Assert-Path (Join-Path $plug "skills/controlflow-plan/SKILL.md") "plan skill"
    Assert-Path (Join-Path $plug "skills/controlflow-verify/SKILL.md") "verify skill"
    Assert-Path (Join-Path $plug "skills/controlflow-review/SKILL.md") "review skill"
    Assert-Path (Join-Path $plug "scripts/validate-plan.ps1") "validator script"
    Assert-Path (Join-Path $plug "scripts/detect-drift.ps1") "drift script"
    Assert-Path (Join-Path $plug "scripts/install.ps1") "installer script"
    Assert-Path (Join-Path $plug "plans/templates/plan.meta.json") "nested template"
    Assert-Path (Join-Path $plug "plans/templates/plan.md") "nested template markdown"
    Assert-Path (Join-Path $plug "evals/cases/phantom-api.json") "eval case"
    Assert-Path (Join-Path $plug "README.md") "README"
    Assert-Path (Join-Path $plug "LICENSE") "LICENSE"

    # Working state must not be copied.
    Assert-PathAbsent (Join-Path $plug ".git") "repo .git"
    Assert-PathAbsent (Join-Path $plug ".vs") "IDE .vs"

    # Marketplace entry registered.
    Assert-Path $marketplace "marketplace manifest"
    $mp = Get-Content -LiteralPath $marketplace -Raw | ConvertFrom-Json
    $entry = @($mp.plugins | Where-Object { $_.name -eq "controlflow-codex" })
    if ($entry.Count -ne 1) { throw "Installer smoke: marketplace entry not registered exactly once" }

    # Clean reinstall removes orphaned files from a previous version.
    $stale = Join-Path $plug "scripts/OLD-removed-script.ps1"
    Set-Content -LiteralPath $stale -Value "# stale orphan" -Encoding UTF8
    Assert-Path $stale "stale orphan (pre-reinstall)"

    $reinstall = Invoke-Installer $tempHome -Force
    if ($reinstall.ExitCode -ne 0) { throw "Reinstall failed: $($reinstall.Output -join [Environment]::NewLine)" }
    Assert-PathAbsent $stale "stale orphan (post-reinstall)"
    Assert-Path (Join-Path $plug "scripts/validate-plan.ps1") "validator after reinstall"

    # Installing over an existing target without -Force must refuse.
    $refuse = Invoke-Installer $tempHome
    if ($refuse.ExitCode -eq 0) { throw "Installer smoke: install over existing target without -Force must fail" }

    # Uninstall removes files and marketplace entry.
    $uninstall = Invoke-Installer $tempHome -Uninstall -Force
    if ($uninstall.ExitCode -ne 0) { throw "Uninstall failed: $($uninstall.Output -join [Environment]::NewLine)" }
    Assert-PathAbsent $plug "plugin dir after uninstall"
    if (Test-Path -LiteralPath $marketplace) {
        $mpAfter = Get-Content -LiteralPath $marketplace -Raw | ConvertFrom-Json
        $leftover = @($mpAfter.plugins | Where-Object { $_.name -eq "controlflow-codex" })
        if ($leftover.Count -ne 0) { throw "Installer smoke: marketplace entry not removed on uninstall" }
    }
} finally {
    if (Test-Path -LiteralPath $tempHome) {
        Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$global:LASTEXITCODE = 0
Write-Output "VALID installer smoke contract"

