$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

# Exercise the exact CLI version predicate shipped in the workflow, without
# installing a CLI or requiring credentials.
$evalPath = Join-Path $repo '.github/workflows/eval.yml'
if (Test-Path -LiteralPath $evalPath -PathType Leaf) {
    $eval = Get-Content -LiteralPath $evalPath -Raw
    $match = [regex]::Match($eval, "(?m)^\s*if\(\`$env:CLI_VERSION -cnotmatch '([^']+)'\)")
    Assert $match.Success 'E2E workflow CLI version validation is missing'
    $pattern = $match.Groups[1].Value
    foreach ($version in @('0.160.0', '1.2.3')) { Assert ($version -cmatch $pattern) "Valid CLI version rejected: $version" }
    foreach ($version in @('0.160', 'v0.160.0', '0.160.0;echo', '0x160x0', '')) { Assert ($version -cnotmatch $pattern) "Invalid CLI version accepted: $version" }
} else { Write-Output 'SKIP workflow-only CLI validation: workflow files are not in the portable package' }

$channel = Join-Path $repo 'scripts/assert-release-channel.ps1'
Assert (Test-Path -LiteralPath $channel -PathType Leaf) 'Release channel guard is missing'
& $channel -Version '3.0.0-rc.1' | Out-Null
$blocked=$false
try { & $channel -Version '3.0.0' | Out-Null } catch { $blocked=$_.Exception.Message -match 'Stable releases are blocked' }
Assert $blocked 'Stable release was not blocked pending verified behavioral and callback evidence'
$rejected=$false
try { & $channel -Version '3.0.0-' | Out-Null } catch { $rejected=$true }
Assert $rejected 'Invalid prerelease version was accepted'

$tmpBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tmp = Join-Path $tmpBase ('controlflow-release-metadata-' + [guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory($tmp) | Out-Null
    $archive = Join-Path $tmp 'controlflow-codex-3.0.0-rc.1.zip'
    [IO.File]::WriteAllText($archive, 'release archive fixture')
    $changelog = Join-Path $tmp 'CHANGELOG.md'
    [IO.File]::WriteAllText($changelog, "# Changelog`n`n## Unreleased`n`n- private draft`n`n## 3.0.0-rc.1 — candidate`n`n- Observed candidate change.`n`n## 2.0.0`n`n- Old change.`n")
    $metadata = Join-Path $repo 'scripts/prepare-release-metadata.ps1'
    Assert (Test-Path -LiteralPath $metadata -PathType Leaf) 'Release metadata helper is missing'
    & $metadata -ArchivePath $archive -Version '3.0.0-rc.1' -ChangelogPath $changelog -OutputDirectory $tmp | Out-Null
    $checksum = Join-Path $tmp 'controlflow-codex-3.0.0-rc.1.zip.sha256'
    $notes = Join-Path $tmp 'release-notes.md'
    Assert (Test-Path -LiteralPath $checksum -PathType Leaf) 'Release checksum is missing'
    $expected = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($archive)
    Assert ((Get-Content -LiteralPath $checksum -Raw).Trim() -ceq $expected) 'Release checksum does not match archive bytes and filename'
    $notesText = Get-Content -LiteralPath $notes -Raw
    Assert ($notesText.Contains('Observed candidate change.')) 'Release notes do not contain versioned changelog entry'
    Assert (-not $notesText.Contains('private draft') -and -not $notesText.Contains('Old change.')) 'Release notes include unrelated changelog entries'
    $missingArchive = Join-Path $tmp 'controlflow-codex-9.9.9.zip'
    [IO.File]::WriteAllText($missingArchive, 'different version fixture')
    $rejected=$false
    try { & $metadata -ArchivePath $missingArchive -Version '9.9.9' -ChangelogPath $changelog -OutputDirectory $tmp | Out-Null } catch { $rejected=$_.Exception.Message -match 'versioned changelog entry' }
    Assert $rejected 'Release without a versioned changelog entry was accepted'
    Assert (-not (Test-Path -LiteralPath "$missingArchive.sha256")) 'Missing release notes produced a checksum'
    $rejected=$false
    try { & $metadata -ArchivePath $archive -Version '9.9.9' -ChangelogPath $changelog -OutputDirectory $tmp | Out-Null } catch { $rejected=$_.Exception.Message -match 'archive name' }
    Assert $rejected 'Release archive with a different version was accepted'
    [IO.File]::AppendAllText($changelog, "`n## 3.0.0-rc.1`n`n- Duplicate entry.`n")
    $rejected=$false
    try { & $metadata -ArchivePath $archive -Version '3.0.0-rc.1' -ChangelogPath $changelog -OutputDirectory $tmp | Out-Null } catch { $rejected=$_.Exception.Message -match 'exactly one' }
    Assert $rejected 'Duplicate versioned changelog entries were accepted'
} finally {
    $resolved = [IO.Path]::GetFullPath($tmp)
    if (-not $resolved.StartsWith($tmpBase, [StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('controlflow-release-metadata-')) { throw 'Unsafe test cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output 'VALID release version and metadata contract'
