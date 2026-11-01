param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Version,
    [string]$GhCommand='gh'
)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'assert-release-channel.ps1') -Version $Version | Out-Null
if ($Repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid GitHub repository identity' }
$tag="v$Version"
$global:LASTEXITCODE=0
$response=@(& $GhCommand api --paginate --slurp "repos/$Repository/releases?per_page=100" 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'GitHub release inventory unavailable; publication is blocked' }
try { $pages=ConvertFrom-Json -InputObject ($response -join "`n") -AsHashtable -NoEnumerate }
catch { throw 'GitHub release inventory invalid; publication is blocked' }
if ($pages -isnot [array] -or $pages.Count -eq 0) { throw 'GitHub release inventory invalid; publication is blocked' }
foreach ($page in $pages) {
    if ($page -isnot [array]) { throw 'GitHub release inventory page invalid; publication is blocked' }
    foreach ($release in $page) {
        if ($release -isnot [System.Collections.IDictionary] -or -not $release.ContainsKey('tag_name') -or [string]::IsNullOrWhiteSpace($release.tag_name)) { throw 'GitHub release inventory entry invalid; publication is blocked' }
        if ($release.tag_name -ceq $tag) { throw "GitHub Release $tag already exists; inspect its draft state and assets before any recovery. See docs/release.md." }
    }
}
Write-Output "VALID no existing GitHub Release for $tag"
