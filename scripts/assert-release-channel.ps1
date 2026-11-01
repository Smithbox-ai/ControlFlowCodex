param([Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = 'Stop'

# A prerelease identifier is required until evidence can be verified by a
# release protocol; tests or a human-supplied success flag do not establish it.
if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$') { throw 'Invalid release version' }
$prerelease = $Matches[4]
if (-not $prerelease) { throw 'Stable releases are blocked until a verified release evidence protocol covers real paired A/B trials and host callbacks. Publish only a prerelease meanwhile.' }
foreach ($identifier in $prerelease.Split('.')) {
    if ($identifier -cmatch '^0[0-9]+$') { throw 'Invalid release version: numeric prerelease identifier has a leading zero' }
}
Write-Output "VALID prerelease channel $Version"
