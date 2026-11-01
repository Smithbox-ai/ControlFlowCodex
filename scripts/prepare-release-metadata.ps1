param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$ChangelogPath,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'

if ($Version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') { throw 'Invalid release version' }
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw 'Release archive is missing' }
$archiveName = [IO.Path]::GetFileName($ArchivePath)
if ($archiveName -cne "controlflow-codex-$Version.zip") { throw 'Release archive name does not match the version' }
if (-not (Test-Path -LiteralPath $ChangelogPath -PathType Leaf)) { throw 'Changelog is missing' }

$lines = @(Get-Content -LiteralPath $ChangelogPath)
$headingPattern = '^##\s+' + [regex]::Escape($Version) + '(?:\s|$)'
$headings = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -cmatch $headingPattern) { $i } })
if ($headings.Count -ne 1) { throw 'Expected exactly one versioned changelog entry' }
$start = [int]$headings[0]
$end = $start + 1
while ($end -lt $lines.Count -and $lines[$end] -cnotmatch '^##\s+') { $end++ }
$notes = ($lines[$start..($end - 1)] -join "`n").Trim()
if ($end -le ($start + 1) -or [string]::IsNullOrWhiteSpace(($lines[($start + 1)..($end - 1)] -join "`n"))) { throw 'Versioned changelog entry is empty' }
$hash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$output = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($output) | Out-Null
$encoding = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $output ($archiveName + '.sha256')), "$hash  $archiveName`n", $encoding)
[IO.File]::WriteAllText((Join-Path $output 'release-notes.md'), "$notes`n", $encoding)
Write-Output "VALID release metadata for $archiveName"
