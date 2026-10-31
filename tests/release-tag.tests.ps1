$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $root 'scripts/ensure-release-tag.ps1'
if (-not (Test-Path -LiteralPath $helper)) { throw 'Release tag recovery helper is missing' }
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp=Join-Path $tempBase ('controlflow-release-tag-'+[guid]::NewGuid().ToString('N'))
function Git([string]$dir,[string[]]$argsList) {
    $exe=@(Get-Command git -CommandType Application)[0].Source
    $output = @(& $exe -C $dir @argsList 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $($argsList -join ' ') : $($output -join ' ')" }
    return ($output -join "`n").Trim()
}
function Assert([bool]$ok,[string]$message) { if (-not $ok) { throw $message } }
try {
    [IO.Directory]::CreateDirectory($temp) | Out-Null
    $remote=Join-Path $temp 'remote.git'; $checkout=Join-Path $temp 'checkout'
    [IO.Directory]::CreateDirectory($remote) | Out-Null
    [IO.Directory]::CreateDirectory($checkout) | Out-Null
    Git $remote @('init','--bare','-q') | Out-Null
    Git $checkout @('init','-q') | Out-Null
    Git $checkout @('config','user.email','fixture@example.invalid') | Out-Null
    Git $checkout @('config','user.name','Fixture') | Out-Null
    Git $checkout @('remote','add','origin',$remote) | Out-Null
    [IO.File]::WriteAllText((Join-Path $checkout 'file.txt'),'first')
    Git $checkout @('add','file.txt') | Out-Null
    Git $checkout @('commit','-qm','first') | Out-Null
    $head=Git $checkout @('rev-parse','HEAD')
    & $helper -RepoRoot $checkout -Version '3.0.0-rc.1' -ExpectedCommit $head -CreateIfMissing | Out-Null
    Assert ((Git $remote @('rev-parse','refs/tags/v3.0.0-rc.1')) -ceq $head) 'Initial tag was not pushed to exact commit'
    & $helper -RepoRoot $checkout -Version '3.0.0-rc.1' -ExpectedCommit $head -CreateIfMissing | Out-Null
    Git $checkout @('tag','-d','v3.0.0-rc.1') | Out-Null
    & $helper -RepoRoot $checkout -Version '3.0.0-rc.1' -ExpectedCommit $head -CreateIfMissing | Out-Null
    Assert ((Git $checkout @('rev-parse','refs/tags/v3.0.0-rc.1')) -ceq $head) 'Retry did not fetch the matching remote tag'
    Git $checkout @('tag','-d','v3.0.0-rc.1') | Out-Null
    Git $checkout @('tag','-a','v3.0.0-rc.1','-m','different tag object') | Out-Null
    $rejected=$false
    try { & $helper -RepoRoot $checkout -Version '3.0.0-rc.1' -ExpectedCommit $head -CreateIfMissing | Out-Null } catch { $rejected=$true }
    Assert $rejected 'Different local and remote tag objects were accepted'
    Assert ((Git $remote @('rev-parse','refs/tags/v3.0.0-rc.1')) -ceq $head) 'Retry changed the remote tag'
    Git $checkout @('tag','-d','v3.0.0-rc.1') | Out-Null
    [IO.File]::WriteAllText((Join-Path $checkout 'file.txt'),'second')
    Git $checkout @('add','file.txt') | Out-Null
    Git $checkout @('commit','-qm','second') | Out-Null
    $current=Git $checkout @('rev-parse','HEAD')
    $rejected=$false
    try { & $helper -RepoRoot $checkout -Version '3.0.0-rc.1' -ExpectedCommit $head -CreateIfMissing | Out-Null } catch { $rejected=$_.Exception.Message -match 'package source commit' }
    Assert $rejected 'Changed checkout commit was accepted after packaging'
    $rejected=$false
    try { & $helper -RepoRoot $checkout -Version '3.0.0-rc.1' -ExpectedCommit $current -CreateIfMissing | Out-Null } catch { $rejected=$_.Exception.Message -match 'Remote release tag points to a different commit' }
    Assert $rejected 'Remote tag pointing at another checkout was accepted'
    Assert ((Git $remote @('rev-parse','refs/tags/v3.0.0-rc.1')) -ceq $head) 'Mismatched retry modified remote tag'
    $rejected=$false
    try { & $helper -RepoRoot $checkout -Version '3.0.0-rc.2' -ExpectedCommit $current | Out-Null } catch { $rejected=$true }
    Assert $rejected 'Missing tag was created without explicit create permission'
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    if (-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('controlflow-release-tag-')) { throw 'Unsafe fixture cleanup' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output 'VALID idempotent release tag recovery'
