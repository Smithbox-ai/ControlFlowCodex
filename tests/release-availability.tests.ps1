$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$guard=Join-Path $repo 'scripts/check-github-release.ps1'
if (-not (Test-Path -LiteralPath $guard)) { throw 'GitHub release recovery guard is missing' }
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tmp=Join-Path $base ('controlflow-release-check-'+[guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory($tmp)|Out-Null
    $fake=Join-Path $tmp 'fake-gh.ps1'
    [IO.File]::WriteAllText($fake, 'param([Parameter(ValueFromRemainingArguments=$true)]$rest) if ($env:CF_RELEASE_TEST_FAIL) { exit 1 }; Write-Output $env:CF_RELEASE_TEST_JSON; exit 0')
    $env:CF_RELEASE_TEST_JSON='[[{"tag_name":"v1.0.0"}],[]]'
    & $guard -Repository 'example/project' -Version '3.0.0-rc.1' -GhCommand $fake | Out-Null
    $env:CF_RELEASE_TEST_JSON='[[],[{"tag_name":"v3.0.0-rc.1","draft":true}]]'
    $rejected=$false
    try { & $guard -Repository 'example/project' -Version '3.0.0-rc.1' -GhCommand $fake | Out-Null } catch { $rejected=$_.Exception.Message -match 'already exists' }
    if (-not $rejected) { throw 'An existing draft release was not stopped for safe recovery' }
    $env:CF_RELEASE_TEST_JSON='[[{"tag_name":"v3.0.0-rc.1","draft":false}]]'
    $rejected=$false
    try { & $guard -Repository 'example/project' -Version '3.0.0-rc.1' -GhCommand $fake | Out-Null } catch { $rejected=$_.Exception.Message -match 'already exists' }
    if (-not $rejected) { throw 'An existing published release was not stopped for safe recovery' }
    $env:CF_RELEASE_TEST_JSON='[[{}]]'
    $rejected=$false
    try { & $guard -Repository 'example/project' -Version '3.0.0-rc.1' -GhCommand $fake | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw 'Unverifiable release inventory was accepted' }
    $env:CF_RELEASE_TEST_JSON='[]'
    $rejected=$false
    try { & $guard -Repository 'example/project' -Version '3.0.0-rc.1' -GhCommand $fake | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw 'Missing release inventory page was accepted' }
    $env:CF_RELEASE_TEST_FAIL='1'
    $rejected=$false
    try { & $guard -Repository 'example/project' -Version '3.0.0-rc.1' -GhCommand $fake | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw 'Failed GitHub inventory was accepted' }
} finally {
    Remove-Item Env:CF_RELEASE_TEST_FAIL,Env:CF_RELEASE_TEST_JSON -ErrorAction SilentlyContinue
    $resolved=[IO.Path]::GetFullPath($tmp)
    if (-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('controlflow-release-check-')) { throw 'Unsafe fixture cleanup' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output 'VALID safe existing-release preflight'
$global:LASTEXITCODE=0
