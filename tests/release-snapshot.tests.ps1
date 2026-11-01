$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$workflowPath=Join-Path $repo '.github/workflows/release.yml'
if (-not (Test-Path -LiteralPath $workflowPath)) { Write-Output 'SKIP workflow snapshot test: workflows are not packaged'; return }
$workflow=Get-Content -LiteralPath $workflowPath -Raw
$match=[regex]::Match($workflow,'(?m)^      - name: Build package\r?\n[\s\S]*?^        run: \|\r?\n(?<code>(?:^          [^\r\n]*\r?\n|^\r?\n)*)(?=^      - name:)')
if (-not $match.Success) { throw 'Release package step is missing or cannot be tested' }
$code=(($match.Groups['code'].Value -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { if (-not $_.StartsWith('          ')) { throw 'Invalid workflow indentation' }; $_.Substring(10) }) -join "`n")
$runner=[scriptblock]::Create($code)
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tmp=Join-Path $base ('controlflow-release-snapshot-'+[guid]::NewGuid().ToString('N'))
$saved=@{};foreach($key in @('RUNNER_TEMP','GITHUB_WORKSPACE','GITHUB_OUTPUT','RELEASE_VERSION','EXPECTED_SOURCE_SHA','GIT_NO_REPLACE_OBJECTS','INPUT_VERSION','GITHUB_REF','GITHUB_REPOSITORY','GITHUB_EVENT_NAME','CF_TEST_TAMPER_HELPER')){$saved[$key]=[Environment]::GetEnvironmentVariable($key)}
function Invoke-TestGit([string]$dir,[string[]]$arguments) { $exe=@(Get-Command git -CommandType Application)[0].Source; $out=@(& $exe -C $dir @arguments 2>&1); if($LASTEXITCODE -ne 0){throw "Git fixture failed: $($out -join ' ')"};return ($out -join "`n").Trim() }
try {
    [IO.Directory]::CreateDirectory($tmp)|Out-Null
    $fixture=Join-Path $tmp 'work';$runnerTemp=Join-Path $tmp 'runner';[IO.Directory]::CreateDirectory((Join-Path $fixture 'scripts'))|Out-Null;[IO.Directory]::CreateDirectory($runnerTemp)|Out-Null
    $packager=@'
param([string]$OutputDirectory,[string]$Version)
$root=Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $root 'extra.txt')) { throw 'Untracked file leaked into package source' }
if ((Get-Content -LiteralPath (Join-Path $root 'tracked.txt') -Raw) -cne 'committed') { throw 'Modified checkout file leaked into package source' }
if ($env:CF_TEST_TAMPER_HELPER) { [IO.File]::WriteAllText((Join-Path $root 'scripts/prepare-release-metadata.ps1'),'throw "Tampered helper executed"') }
[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
[IO.File]::WriteAllText((Join-Path $OutputDirectory "controlflow-codex-$Version.zip"),'snapshot-built')
$global:LASTEXITCODE=0
'@
    $metadata=@'
param([string]$ArchivePath,[string]$Version,[string]$ChangelogPath,[string]$OutputDirectory)
if ((Get-Content -LiteralPath $ChangelogPath -Raw) -cne 'committed changelog') { throw 'Wrong changelog source' }
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'release-notes.md'),'ok')
[IO.File]::WriteAllText("$ArchivePath.sha256",'ok')
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'scripts/package.ps1'),$packager)
    [IO.File]::WriteAllText((Join-Path $fixture 'scripts/prepare-release-metadata.ps1'),$metadata)
    $guards=@{
        'assert-release-channel.ps1' = 'param($Version) [IO.File]::WriteAllText((Join-Path $env:RUNNER_TEMP "verified-channel"),"yes")'
        'check-github-release.ps1' = 'param($Repository,$Version) [IO.File]::WriteAllText((Join-Path $env:RUNNER_TEMP "verified-check"),"yes")'
        'ensure-release-tag.ps1' = 'param($RepoRoot,$Version,$ExpectedCommit,[switch]$CreateIfMissing) [IO.File]::WriteAllText((Join-Path $env:RUNNER_TEMP "verified-tag"),"yes")'
    }
    foreach($name in $guards.Keys){[IO.File]::WriteAllText((Join-Path $fixture "scripts/$name"),$guards[$name])}
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/verify-release-snapshot.ps1') -Destination (Join-Path $fixture 'scripts/verify-release-snapshot.ps1')
    [IO.File]::WriteAllText((Join-Path $fixture 'plugin.json'),'{"version":"3.0.0-rc.1"}')
    [IO.File]::WriteAllText((Join-Path $fixture 'tracked.txt'),'committed')
    [IO.File]::WriteAllText((Join-Path $fixture 'marker.txt'),'$Format:%H$')
    [IO.File]::WriteAllText((Join-Path $fixture 'CHANGELOG.md'),'committed changelog')
    Invoke-TestGit $fixture @('init','-q')|Out-Null;Invoke-TestGit $fixture @('config','user.email','fixture@example.invalid')|Out-Null;Invoke-TestGit $fixture @('config','user.name','Fixture')|Out-Null;Invoke-TestGit $fixture @('config','core.autocrlf','false')|Out-Null;Invoke-TestGit $fixture @('add','.')|Out-Null;Invoke-TestGit $fixture @('update-index','--chmod=+x','marker.txt')|Out-Null;Invoke-TestGit $fixture @('commit','-qm','initial')|Out-Null
    $head=Invoke-TestGit $fixture @('rev-parse','HEAD')
    [IO.File]::WriteAllText((Join-Path $fixture 'tracked.txt'),'tampered')
    [IO.File]::WriteAllText((Join-Path $fixture 'extra.txt'),'untracked')
    [IO.File]::WriteAllText((Join-Path $fixture 'CHANGELOG.md'),'tampered')
    foreach($name in $guards.Keys){[IO.File]::WriteAllText((Join-Path $fixture "scripts/$name"),'throw "Untrusted checkout helper was executed"')}
    $env:RUNNER_TEMP=$runnerTemp;$env:GITHUB_WORKSPACE=$fixture;$env:GITHUB_OUTPUT=Join-Path $tmp 'step-output';$env:RELEASE_VERSION='3.0.0-rc.1';$env:EXPECTED_SOURCE_SHA=$head
    $env:INPUT_VERSION='';$env:GITHUB_REF='refs/heads/main';$env:GITHUB_REPOSITORY='fixture/project';$env:GITHUB_EVENT_NAME='workflow_dispatch'
    Push-Location $fixture
    try { & $runner | Out-Null } finally { Pop-Location }
    if ((Get-Content -LiteralPath (Join-Path $fixture 'dist/controlflow-codex-3.0.0-rc.1.zip') -Raw) -cne 'snapshot-built') { throw 'Snapshot package was not produced' }
    if (-not ((Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw).Contains("source_sha=$head"))) { throw 'Package source SHA was not exported' }
    foreach($name in @('verified-channel','verified-check','verified-tag')){if(-not (Test-Path -LiteralPath (Join-Path $runnerTemp $name))){throw "Verified snapshot helper did not run: $name"}}
    $env:CF_TEST_TAMPER_HELPER='1';$rejected=$false
    Push-Location $fixture
    try { try { & $runner | Out-Null } catch { $rejected=$_.Exception.Message -match 'Extracted content differs' } } finally { Pop-Location }
    Remove-Item Env:CF_TEST_TAMPER_HELPER
    if (-not $rejected) { throw 'Mutated snapshot helper was executed or accepted' }
    $verifyTar=Join-Path $tmp 'verify.tar';$verifyExtract=Join-Path $tmp 'verify-extract'
    Invoke-TestGit $fixture @('archive','--format=tar',"--output=$verifyTar",$head)|Out-Null
    [IO.Directory]::CreateDirectory($verifyExtract)|Out-Null
    [System.Formats.Tar.TarFile]::ExtractToDirectory($verifyTar,$verifyExtract,$false)
    [IO.File]::WriteAllText((Join-Path $verifyExtract 'tracked.txt'),'changed after extraction')
    $rejected=$false
    try { & (Join-Path $repo 'scripts/verify-release-snapshot.ps1') -RepoRoot $fixture -Commit $head -TarPath $verifyTar -ExtractedRoot $verifyExtract | Out-Null } catch { $rejected=$_.Exception.Message -match 'Extracted content differs' }
    if (-not $rejected) { throw 'Modified extracted file was accepted' }
    $env:EXPECTED_SOURCE_SHA=('0' * 40);$rejected=$false
    Push-Location $fixture
    try { try { & $runner | Out-Null } catch { $rejected=$true } } finally { Pop-Location }
    if (-not $rejected) { throw 'Package accepted a checkout commit different from the original workflow source' }
    $env:EXPECTED_SOURCE_SHA=$head
    $attrs=Join-Path $fixture '.git/info/attributes'
    foreach ($attribute in @('tracked.txt export-ignore','marker.txt export-subst','scripts/verify-release-snapshot.ps1 export-ignore')) {
        [IO.File]::WriteAllText($attrs,$attribute+"`n")
        $rejected=$false
        Push-Location $fixture
        try { try { & $runner | Out-Null } catch { $rejected=$true } } finally { Pop-Location }
        if (-not $rejected) { throw "Altered archive accepted: $attribute" }
        if ((Get-Content -LiteralPath $attrs -Raw).Trim() -cne $attribute) { throw 'Snapshot check modified user Git attributes' }
    }
    Remove-Item -LiteralPath $attrs
    Invoke-TestGit $fixture @('config','tar.umask','0111')|Out-Null
    $rejected=$false
    Push-Location $fixture
    try { try { & $runner | Out-Null } catch { $rejected=$_.Exception.Message -match 'executable mode' } } finally { Pop-Location }
    if (-not $rejected) { throw 'Modified executable bit in archive was accepted' }
    Invoke-TestGit $fixture @('config','--unset','tar.umask')|Out-Null
    $blob=Invoke-TestGit $fixture @('rev-parse','HEAD:marker.txt')
    Invoke-TestGit $fixture @('update-index','--add','--cacheinfo',"120000,$blob,link.txt")|Out-Null
    Invoke-TestGit $fixture @('commit','-qm','symlink-mode')|Out-Null
    $env:EXPECTED_SOURCE_SHA=Invoke-TestGit $fixture @('rev-parse','HEAD');$rejected=$false
    Push-Location $fixture
    try { try { & $runner | Out-Null } catch { $rejected=$_.Exception.Message -match 'Unsupported Git source mode' } } finally { Pop-Location }
    if (-not $rejected) { throw 'Symlink source was not rejected before extraction' }
    Invoke-TestGit $fixture @('update-index','--force-remove','link.txt')|Out-Null
    Invoke-TestGit $fixture @('update-index','--add','--cacheinfo',"160000,$head,submodule")|Out-Null
    Invoke-TestGit $fixture @('commit','-qm','submodule-mode')|Out-Null
    $env:EXPECTED_SOURCE_SHA=Invoke-TestGit $fixture @('rev-parse','HEAD');$rejected=$false
    Push-Location $fixture
    try { try { & $runner | Out-Null } catch { $rejected=$_.Exception.Message -match 'Unsupported Git source mode' } } finally { Pop-Location }
    if (-not $rejected) { throw 'Submodule source was not rejected before extraction' }

    # Exercise the real package script, too, from a committed isolated source
    # snapshot. Inject the current metadata helper because it may still be
    # uncommitted in the checkout where this regression test is being run.
    $real=Join-Path $tmp 'real-work';$realTar=Join-Path $tmp 'real-source.tar'
    $realHead=Invoke-TestGit $repo @('rev-parse','HEAD')
    Invoke-TestGit $repo @('archive','--format=tar',"--output=$realTar",$realHead)|Out-Null
    [IO.Directory]::CreateDirectory($real)|Out-Null
    [System.Formats.Tar.TarFile]::ExtractToDirectory($realTar,$real,$false)
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/prepare-release-metadata.ps1') -Destination (Join-Path $real 'scripts/prepare-release-metadata.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/verify-release-snapshot.ps1') -Destination (Join-Path $real 'scripts/verify-release-snapshot.ps1') -Force
    foreach($name in $guards.Keys){[IO.File]::WriteAllText((Join-Path $real "scripts/$name"),$guards[$name])}
    Invoke-TestGit $real @('init','-q')|Out-Null;Invoke-TestGit $real @('config','user.email','fixture@example.invalid')|Out-Null;Invoke-TestGit $real @('config','user.name','Fixture')|Out-Null;Invoke-TestGit $real @('config','core.autocrlf','false')|Out-Null;Invoke-TestGit $real @('add','.')|Out-Null;Invoke-TestGit $real @('commit','-qm','package-source')|Out-Null
    $realCommit=Invoke-TestGit $real @('rev-parse','HEAD')
    $expectedReadme=[IO.File]::ReadAllBytes((Join-Path $real 'README.md'))
    [IO.File]::WriteAllText((Join-Path $real 'README.md'),'modified after tests')
    [IO.File]::WriteAllText((Join-Path $real 'scripts/untracked-leak.ps1'),'must not ship')
    $env:GITHUB_WORKSPACE=$real;$env:EXPECTED_SOURCE_SHA=$realCommit;$env:GITHUB_OUTPUT=Join-Path $tmp 'real-step-output'
    $env:RELEASE_VERSION=(Get-Content -LiteralPath (Join-Path $real 'plugin.json') -Raw | ConvertFrom-Json).version
    Push-Location $real
    try { & $runner | Out-Null } finally { Pop-Location }
    $realZip=Join-Path $real "dist/controlflow-codex-$($env:RELEASE_VERSION).zip"
    $unpacked=Join-Path $tmp 'real-unpacked';[IO.Compression.ZipFile]::ExtractToDirectory($realZip,$unpacked)
    $installedRoot=Join-Path $unpacked 'controlflow-codex'
    if (Test-Path -LiteralPath (Join-Path $installedRoot 'scripts/untracked-leak.ps1')) { throw 'Real package included an untracked file' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $installedRoot 'README.md'))) -cne [Convert]::ToBase64String($expectedReadme)) { throw 'Real package included modified README bytes' }
} finally {
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key])}
    $resolved=[IO.Path]::GetFullPath($tmp)
    if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('controlflow-release-snapshot-')){throw 'Unsafe fixture cleanup'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
Write-Output 'VALID release package is built from the exact Git snapshot'
