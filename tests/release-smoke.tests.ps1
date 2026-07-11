$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseScript = Join-Path $repoRoot "scripts/release.ps1"
$pluginJsonPath = Join-Path $repoRoot ".codex-plugin/plugin.json"

if (-not (Test-Path -LiteralPath $releaseScript -PathType Leaf)) {
    throw "Missing release script: $releaseScript"
}

$originalPluginJson = Get-Content -LiteralPath $pluginJsonPath -Raw
$testVersion = "0.9.9"
$tempOutputDir = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-release-test-" + [guid]::NewGuid().ToString("N"))

try {
    $global:LASTEXITCODE = 0
    $output = @(& $releaseScript -RepoRoot $repoRoot -Version $testVersion -SkipTests -SkipTag -OutputDir $tempOutputDir 2>&1)
    $exitCode = $global:LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Release script failed with exit code $exitCode`: $($output -join [Environment]::NewLine)"
    }

    $outputText = $output -join [Environment]::NewLine
    if ($outputText -notmatch "Smoke install: PASS") {
        throw "Release smoke install did not pass"
    }

    $expectedZip = Join-Path $tempOutputDir "controlflow-codex-$testVersion.zip"
    if (-not (Test-Path -LiteralPath $expectedZip -PathType Leaf)) {
        throw "Release package not created: $expectedZip"
    }

    $global:LASTEXITCODE = 0
    $badVersionOutput = @(& $releaseScript -RepoRoot $repoRoot -Version "invalid" -SkipTests -SkipTag -OutputDir $tempOutputDir 2>&1)
    $badExitCode = $global:LASTEXITCODE
    if ($badExitCode -eq 0) {
        throw "Release script must reject an invalid version format"
    }
    $global:LASTEXITCODE = 0

} finally {
    [System.IO.File]::WriteAllText($pluginJsonPath, $originalPluginJson, (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $tempOutputDir) {
        Remove-Item -LiteralPath $tempOutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "VALID release smoke contract"
