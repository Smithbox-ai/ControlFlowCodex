param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [switch]$SkipTests,

    [switch]$SkipTag,

    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

function Test-SemVer([string]$Version) {
    return $Version -match '^\d+\.\d+\.\d+$'
}

function Invoke-GitSafe([string]$Root, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $global:LASTEXITCODE = 0
        $allArgs = @("-C", $Root) + $Arguments
        $output = @(& git @allArgs 2>&1)
        $exitCode = $global:LASTEXITCODE
        if ($exitCode -ne 0) {
            return $null
        }
        $strings = @($output | Where-Object { $_ -is [string] })
        return ($strings -join "`n")
    } catch {
        return $null
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

try {
    if (-not (Test-SemVer $Version)) {
        throw "Version must be in semver format X.Y.Z: $Version"
    }

    $repoRootResolved = (Resolve-Path $RepoRoot).Path

    $resolvedOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        Join-Path $repoRootResolved "dist"
    } elseif ([System.IO.Path]::IsPathRooted($OutputDir)) {
        $OutputDir
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repoRootResolved $OutputDir))
    }

    if (-not (Test-Path $resolvedOutputDir)) {
        New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
    }

    Write-Output "=== Release $Version ==="

    $pluginJsonPath = Join-Path $repoRootResolved ".codex-plugin/plugin.json"
    if (Test-Path -LiteralPath $pluginJsonPath -PathType Leaf) {
        $pluginJson = Get-Content -LiteralPath $pluginJsonPath -Raw | ConvertFrom-Json
        $pluginJson.version = $Version
        $pluginJson | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $pluginJsonPath -Encoding UTF8
        Write-Output "Updated plugin.json version to $Version"
    }

    if (-not $SkipTests) {
        Write-Output "--- Running contract tests ---"
        $testRunner = Join-Path $repoRootResolved "tests/run-contract-tests.ps1"
        if (-not (Test-Path -LiteralPath $testRunner -PathType Leaf)) {
            throw "Missing test runner: $testRunner"
        }
        $global:LASTEXITCODE = 0
        & $testRunner 2>&1 | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Contract tests failed"
        }
        Write-Output "Tests passed."
    }

    Write-Output "--- Packaging ---"
    $packageName = "controlflow-codex-$Version"
    $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-release-" + [guid]::NewGuid().ToString("N"))
    $stagingPluginDir = Join-Path $stagingDir $packageName

    try {
        New-Item -ItemType Directory -Path $stagingPluginDir -Force | Out-Null

        $excludePatterns = @(
            "\.git$",
            "\.gitignore$",
            "\.vs$",
            "dist$",
            "tests$",
            "docs\\superpowers$",
            "plans\\artifacts$",
            "plans\\[^e].+-plan\.md$",
            "plans\\feedback-loop-contract-plan\.md$",
            "plans\\plan-contract-foundation-plan\.md$",
            "plans\\score-plan-plan\.md$"
        )

        $sourceItems = Get-ChildItem -LiteralPath $repoRootResolved -Force -Directory | Where-Object {
            $name = $_.Name
            -not ($name -eq ".git" -or $name -eq ".vs" -or $name -eq "dist" -or $name -eq "tests" -or $name -eq "docs")
        }

        foreach ($item in $sourceItems) {
            Copy-Item -LiteralPath $item.FullName -Destination $stagingPluginDir -Recurse -Force
        }

        $sourceFiles = Get-ChildItem -LiteralPath $repoRootResolved -Force -File | Where-Object {
            $name = $_.Name
            -not ($name -eq ".gitignore")
        }
        foreach ($file in $sourceFiles) {
            Copy-Item -LiteralPath $file.FullName -Destination $stagingPluginDir -Force
        }

        $plansDir = Join-Path $stagingPluginDir "plans"
        if (Test-Path $plansDir) {
            $planFiles = Get-ChildItem -LiteralPath $plansDir -File -Filter "*-plan.md" -ErrorAction SilentlyContinue
            if ($planFiles) {
                $planFiles | Where-Object { $_.Name -notlike "bugfix-plan.md" -and $_.Name -notlike "refactor-plan.md" -and $_.Name -notlike "migration-plan.md" -and $_.Name -notlike "feature-plan.md" -and $_.Name -notlike "docs-test-only-plan.md" } | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Force
                }
            }
            $artifactsDir = Join-Path $plansDir "artifacts"
            if (Test-Path $artifactsDir) {
                Remove-Item -LiteralPath $artifactsDir -Recurse -Force
            }
        }

        $zipPath = Join-Path $resolvedOutputDir "$packageName.zip"
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force
        }
        Compress-Archive -Path $stagingPluginDir -DestinationPath $zipPath -Force
        Write-Output "Created package: $zipPath"
    } finally {
        if (Test-Path -LiteralPath $stagingDir) {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Output "--- Smoke install ---"
    $smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-smoke-" + [guid]::NewGuid().ToString("N"))
    $smokeSource = Join-Path $smokeRoot "source"
    $smokeHome = Join-Path $smokeRoot "home"

    try {
        New-Item -ItemType Directory -Path $smokeSource -Force | Out-Null
        New-Item -ItemType Directory -Path $smokeHome -Force | Out-Null

        Expand-Archive -LiteralPath $zipPath -DestinationPath $smokeSource -Force
        $extractedDir = Get-ChildItem -LiteralPath $smokeSource -Directory | Select-Object -First 1
        if ($null -eq $extractedDir) {
            throw "Smoke install: extracted package is empty"
        }

        $installScript = Join-Path $extractedDir.FullName "scripts/install.ps1"
        if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
            throw "Smoke install: install.ps1 not found in package"
        }

        $global:LASTEXITCODE = 0
        & $installScript -HomeRoot $smokeHome -Force 2>&1 | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Smoke install failed"
        }

        $installedPlugin = Join-Path $smokeHome "plugins/controlflow-codex"
        if (-not (Test-Path -LiteralPath $installedPlugin -PathType Container)) {
            throw "Smoke install: plugin directory not created at $installedPlugin"
        }

        $marketplacePath = Join-Path $smokeHome ".agents/plugins/marketplace.json"
        if (-not (Test-Path -LiteralPath $marketplacePath -PathType Leaf)) {
            throw "Smoke install: marketplace.json not created"
        }

        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
        $entry = $marketplace.plugins | Where-Object { $_.name -eq "controlflow-codex" }
        if ($null -eq $entry) {
            throw "Smoke install: marketplace entry not found"
        }

        $global:LASTEXITCODE = 0
        & $installScript -HomeRoot $smokeHome -Uninstall -Force 2>&1 | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Smoke uninstall failed"
        }

        if (Test-Path -LiteralPath $installedPlugin -PathType Container) {
            throw "Smoke install: plugin directory still exists after uninstall"
        }

        Write-Output "Smoke install: PASS"
    } finally {
        if (Test-Path -LiteralPath $smokeRoot) {
            Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $SkipTag) {
        Write-Output "--- Creating git tag ---"
        $tagResult = Invoke-GitSafe $repoRootResolved @("tag", "v$Version")
        if ($null -ne $tagResult) {
            Write-Output "Created tag v$Version"
        } else {
            Write-Output "WARNING: Could not create git tag v$Version (git may be read-only or tag may already exist)"
        }
    }

    Write-Output "=== Release $Version complete ==="
    Write-Output "Package: $zipPath"
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
