param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$Version
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ControlFlow.Package.psm1') -Force
$sourceRoot = Resolve-ControlFlowPath (Split-Path -Parent $PSScriptRoot)
$manifest = Assert-ControlFlowPackage $sourceRoot $Version
$outputDir = Resolve-ControlFlowPath $OutputDirectory
$tempBase = Resolve-ControlFlowPath ([IO.Path]::GetTempPath())
$tempRoot = Assert-ControlFlowContained (Join-Path $tempBase ('controlflow-package-' + [guid]::NewGuid().ToString('N'))) $tempBase
$staging = Join-Path $tempRoot $manifest.name
$extract = Join-Path $tempRoot 'extracted'
$archive = Join-Path $tempRoot "$($manifest.name)-$($manifest.version).zip"
try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Copy-ControlFlowPackage $sourceRoot $staging
    # ZipFile includes dot directories on Unix, unlike Compress-Archive.
    [IO.Compression.ZipFile]::CreateFromDirectory($staging, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $extract)
    $extractedRoot = Join-Path $extract $manifest.name
    $null = Assert-ControlFlowPackage $extractedRoot $manifest.version
    $expected = @(Get-ControlFlowPackageFiles $staging)
    $actual = @(Get-ChildItem -LiteralPath $extractedRoot -File -Recurse -Force | ForEach-Object { [IO.Path]::GetRelativePath($extractedRoot, $_.FullName).Replace('\', '/') } | Sort-Object)
    if (@(Compare-Object $expected $actual).Count) { throw 'Extracted archive file inventory differs from staging' }
    foreach ($relative in $expected) {
        if ((Get-FileHash -LiteralPath (Join-Path $staging $relative)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $extractedRoot $relative)).Hash) { throw "Extracted bytes differ: $relative" }
    }
    $global:LASTEXITCODE = 0
    & (Join-Path $extractedRoot 'scripts/validate-contract.ps1') -Path (Join-Path $extractedRoot 'plans/examples/small-v3.meta.json') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Extracted package v3 SMALL example validation failed' }
    & (Join-Path $extractedRoot 'scripts/install.ps1') -HomeRoot (Join-Path $tempRoot 'smoke-home') -Force | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Extracted package installation failed' }
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $destination = Assert-ControlFlowContained (Join-Path $outputDir "$($manifest.name)-$($manifest.version).zip") $outputDir
    Copy-Item -LiteralPath $archive -Destination $destination -Force
    Write-Output "VALID extracted package $destination (version $($manifest.version), $($actual.Count) files)"
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-ControlFlowTree $tempRoot $tempBase }
}
$global:LASTEXITCODE = 0
