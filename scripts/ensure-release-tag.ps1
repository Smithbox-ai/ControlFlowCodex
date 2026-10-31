param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$ExpectedCommit,
    [switch]$CreateIfMissing
)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'assert-release-channel.ps1') -Version $Version | Out-Null
$tag="v$Version"
$ref="refs/tags/$tag"
$git=@(Get-Command git -CommandType Application)[0].Source

function Invoke-Git([string[]]$Arguments, [int[]]$Allowed=@(0)) {
    $output=@(& $git -C $RepoRoot @Arguments 2>$null)
    $code=$LASTEXITCODE
    if ($code -notin $Allowed) { throw "Git observation failed ($($Arguments[0]), exit $code); no tag will be overwritten" }
    return @{code=$code;lines=$output}
}
function Get-RemoteTag {
    $observation=Invoke-Git @('ls-remote','--tags','origin',$ref,"$ref^{}")
    $value=@{object='';commit=''}
    foreach ($line in $observation.lines) {
        $parts=([string]$line).Split("`t")
        if ($parts.Count -ne 2 -or $parts[0] -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') { throw 'Invalid remote tag observation' }
        if ($parts[1] -ceq $ref) { if ($value.object) { throw 'Duplicate remote tag' }; $value.object=$parts[0] }
        elseif ($parts[1] -ceq "$ref^{}") { if ($value.commit) { throw 'Duplicate peeled remote tag' }; $value.commit=$parts[0] }
        else { throw 'Unexpected remote tag observation' }
    }
    if ($value.commit -and -not $value.object) { throw 'Remote tag object is missing' }
    if ($value.object -and -not $value.commit) { $value.commit=$value.object }
    return $value
}
function Get-LocalTag {
    $found=Invoke-Git @('rev-parse','--verify','--quiet',$ref) @(0,1)
    if ($found.code -eq 1) { return @{object='';commit=''} }
    if ($found.lines.Count -ne 1 -or [string]$found.lines[0] -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') { throw 'Invalid local tag observation' }
    $peeled=Invoke-Git @('rev-parse','--verify',"$ref^{commit}")
    if ($peeled.lines.Count -ne 1 -or [string]$peeled.lines[0] -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') { throw 'Invalid local tag commit' }
    return @{object=[string]$found.lines[0];commit=[string]$peeled.lines[0]}
}

$headResult=Invoke-Git @('rev-parse','--verify','HEAD^{commit}')
if ($headResult.lines.Count -ne 1 -or [string]$headResult.lines[0] -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') { throw 'Invalid checkout commit' }
$head=[string]$headResult.lines[0]
if ($ExpectedCommit -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$' -or $head -cne $ExpectedCommit) { throw 'Checkout commit differs from the package source commit' }
$local=Get-LocalTag; $remote=Get-RemoteTag
if ($local.commit -and $local.commit -cne $head) { throw 'Local release tag points to a different commit' }
if ($remote.commit -and $remote.commit -cne $head) { throw 'Remote release tag points to a different commit' }
if ($local.object -and $remote.object -and $local.object -cne $remote.object) { throw 'Local and remote release tag objects differ' }
if (-not $local.object -and $remote.object) {
    Invoke-Git @('fetch','--no-tags','origin',"${ref}:${ref}") | Out-Null
    $local=Get-LocalTag
    if ($local.object -cne $remote.object -or $local.commit -cne $head) { throw 'Fetched tag changed during observation' }
}
if (-not $remote.object) {
    if (-not $CreateIfMissing) { throw 'Remote release tag is missing; no tag was created' }
    if (-not $local.object) {
        Invoke-Git @('tag',$tag,$head) | Out-Null
        $local=Get-LocalTag
    }
    # No force: a concurrent tag creation rejects the push instead of overwriting.
    Invoke-Git @('push','origin',"${ref}:${ref}") | Out-Null
}
$verified=Get-RemoteTag
if (-not $local.object -or $local.object -cne $verified.object -or $verified.commit -cne $head) { throw 'Release tag verification failed after fetch or push' }
Write-Output "VALID release tag $tag at $head"
