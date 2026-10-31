param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$Version,
    [ValidateSet('Universal','NativeLegacy', IgnoreCase=$false)][string]$Flavor = 'Universal'
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
$suffix = if ($Flavor -ceq 'NativeLegacy') { '-native-legacy' } else { '' }
$archiveName = "$($manifest.name)-$($manifest.version)$suffix.zip"
$archive = Join-Path $tempRoot $archiveName
try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Copy-ControlFlowPackage $sourceRoot $staging
    if ($Flavor -ceq 'NativeLegacy') {
        # Transform only our own validated staging tree; canonical source stays portable.
        Remove-Item -LiteralPath (Assert-ControlFlowContained (Join-Path $staging 'plugin.json') $staging)
        $null = Assert-ControlFlowPackage $staging $manifest.version -Flavor $Flavor
    }
    # ZipFile includes dot directories on Unix, unlike Compress-Archive.
    [IO.Compression.ZipFile]::CreateFromDirectory($staging, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $extract)
    $extractedRoot = Join-Path $extract $manifest.name
    $null = Assert-ControlFlowPackage $extractedRoot $manifest.version -Flavor $Flavor
    $expected = @(Get-ControlFlowPackageFiles $staging -Flavor $Flavor)
    $actual = @(Get-ChildItem -LiteralPath $extractedRoot -File -Recurse -Force | ForEach-Object { [IO.Path]::GetRelativePath($extractedRoot, $_.FullName).Replace('\', '/') } | Sort-Object)
    if (@(Compare-Object $expected $actual).Count) { throw 'Extracted archive file inventory differs from staging' }
    foreach ($relative in $expected) {
        if ((Get-FileHash -LiteralPath (Join-Path $staging $relative)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $extractedRoot $relative)).Hash) { throw "Extracted bytes differ: $relative" }
    }
    $global:LASTEXITCODE = 0
    & (Join-Path $extractedRoot 'scripts/validate-contract.ps1') -Path (Join-Path $extractedRoot 'plans/examples/small-v4.meta.json') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Extracted package V4 draft example validation failed' }
    & (Join-Path $extractedRoot 'scripts/install.ps1') -Flavor $Flavor -HomeRoot (Join-Path $tempRoot 'smoke-home') -Force -DryRun | Out-Null
    & (Join-Path $extractedRoot 'scripts/install.ps1') -Flavor $Flavor -HomeRoot (Join-Path $tempRoot 'smoke-home') -Force | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Extracted package installation failed' }
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $destination = Assert-ControlFlowContained (Join-Path $outputDir $archiveName) $outputDir
    $checksumPath = Assert-ControlFlowContained ($destination+'.sha256') $outputDir
    $inventoryPath = Assert-ControlFlowContained ($destination+'.inventory.json') $outputDir
    foreach ($outputPath in @($destination,$checksumPath,$inventoryPath)) {
        if ((Test-Path -LiteralPath $outputPath) -and -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Package output must be a regular file: $outputPath" }
    }
    Copy-Item -LiteralPath $archive -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($checksumPath, "$hash  $archiveName`n")
    $receipt = [ordered]@{ schema_version=1; flavor=$Flavor; name=$manifest.name; version=$manifest.version; archive_sha256=$hash; callbacks='NOT_RUN'; host_compatibility=if($Flavor -ceq 'NativeLegacy'){'Codex 0.166.0-alpha.5.1 Legacy loader path; other hosts unverified; exact native trust and callbacks still required'}else{'AgentPlugin format; hooks unavailable in Codex 0.166.0-alpha.5.1'}; files=@(foreach($p in $expected){[ordered]@{path=$p;sha256=(Get-FileHash -LiteralPath (Join-Path $staging $p)).Hash.ToLowerInvariant()}}) }
    [IO.File]::WriteAllText($inventoryPath, ($receipt|ConvertTo-Json -Depth 10))
    Write-Output "VALID extracted package $destination (flavor $Flavor, version $($manifest.version), $($actual.Count) files; callbacks NOT_RUN)"
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-ControlFlowTree $tempRoot $tempBase }
}
$global:LASTEXITCODE = 0
