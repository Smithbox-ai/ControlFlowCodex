$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

# The V4 workflow must stop before installation/authentication while the native
# provenance capabilities are unavailable. It has no active model-trial CLI pin.
$evalPath = Join-Path $repo '.github/workflows/eval.yml'
if (Test-Path -LiteralPath $evalPath -PathType Leaf) {
    $eval = Get-Content -LiteralPath $evalPath -Raw
    Assert ($eval.Contains('-Variant v4 -Collector stdout-jsonl -Execute')) 'E2E workflow lacks the explicit V4 protocol gate'
    Assert ($eval -notmatch 'CLI_VERSION|npm install|OPENAI_API_KEY|codex login|\.codex/sessions|prepare-e2e-cache') 'E2E workflow installs/authenticates or retains retired telemetry before the protocol gate'
    $blocked=$false
    try { & (Join-Path $repo 'evals/run-e2e.ps1') -RepoRoot $repo -Variant v4 -Collector stdout-jsonl -Execute -CliPath (Join-Path $repo '__missing_cli_must_not_be_used__') | Out-Null }
    catch { $blocked=$_.Exception.Message -match '^BLOCKED before any CLI/model/session access:' }
    Assert $blocked 'E2E workflow command failed to block before CLI/model/session access'
} else { Write-Output 'SKIP workflow-only protocol validation: workflow files are not in the portable package' }

# Exercise the publication command without contacting GitHub, and check the
# dependency and artifact boundaries declared by the release configuration.
$releasePath = Join-Path $repo '.github/workflows/release.yml'
if (Test-Path -LiteralPath $releasePath -PathType Leaf) {
    $release = Get-Content -LiteralPath $releasePath -Raw
    $ci = Get-Content -LiteralPath (Join-Path $repo '.github/workflows/ci.yml') -Raw
    $checks = [ordered]@{}
    $uses = @([regex]::Matches($release, '(?m)^\s+(?:- )?uses: (?<action>[^@\r\n]+)@(?<ref>[^\s#]+)'))
    $checks['Every release action must use an immutable commit SHA'] = $uses.Count -eq 3 -and @($uses | Where-Object { $_.Groups['ref'].Value -cnotmatch '^[a-f0-9]{40}$' }).Count -eq 0
    $checkoutPin = [regex]::Match($ci, 'actions/checkout@(?<sha>[a-f0-9]{40})').Groups['sha'].Value
    $checkouts = @($uses | Where-Object { $_.Groups['action'].Value -ceq 'actions/checkout' })
    $checks['Release checkout pins must match CI'] = $checkoutPin.Length -eq 40 -and $checkouts.Count -eq 2 -and @($checkouts | Where-Object { $_.Groups['ref'].Value -cne $checkoutPin }).Count -eq 0
    $upload = [regex]::Match($release, '(?m)^        uses: actions/upload-artifact@(?<ref>[^\s#]+)[^\r\n]*\r?\n[\s\S]*?^          path: \|\r?\n(?<paths>(?:^            [^\r\n]+\r?\n)+)')
    $checks['Artifact upload must use verified upload-artifact v4.6.2'] = $upload.Success -and $upload.Groups['ref'].Value -ceq 'ea165f8d65b6e75b540449e92b4886f43607fa02'
    $artifactPaths = @($upload.Groups['paths'].Value -split '\r?\n' | ForEach-Object { $_.Trim() })
    foreach ($suffix in @('.zip', '.zip.sha256', '.zip.inventory.json')) {
        $checks["Recovery artifact is missing $suffix"] = ('dist/controlflow-codex-${{ steps.package.outputs.version }}' + $suffix) -cin $artifactPaths
    }
    $checks['Recovery artifact is missing release notes'] = 'dist/release-notes.md' -cin $artifactPaths
    $checks['Release dependencies must not use a floating Pester installation'] = $release -notmatch 'Install-Module|Set-PSRepository'
    $installSteps = @([regex]::Matches($release, '(?m)^      - name: Install Pester\r?\n        shell: pwsh\r?\n        run: \|\r?\n(?<code>(?:^          [^\r\n]*\r?\n)+)'))
    $checks['Both release jobs must install pinned Pester'] = $installSteps.Count -eq 2
    for ($i = 0; $i -lt $installSteps.Count; $i++) {
        $install = $installSteps[$i].Groups['code'].Value
        $checks["Pester job $i must download version 5.9.1"] = $install.Contains("'https://www.powershellgallery.com/api/v2/package/Pester/5.9.1'")
        $checks["Pester job $i must verify the CI package SHA256 before extraction"] = $install -match '(?s)Get-FileHash[^\r\n]+-cne ''8dd4060fc3bc895f05bd655e4ab82abe346de54a4e6415dfb727cc8378672b69''[^\r\n]+throw ''Pester package hash mismatch''[^\r\n]+\r?\n\s+\[IO\.Compression\.ZipFile\]::ExtractToDirectory'
    }
    $contractSteps = @([regex]::Matches($release, '(?m)^      - name: Run contract suite\r?\n[\s\S]*?^        run: \|\r?\n(?<code>(?:^          [^\r\n]*\r?\n)+)'))
    $checks['Both contract suites must import the verified Pester package'] = $contractSteps.Count -eq 2 -and @($contractSteps | Where-Object { $_.Groups['code'].Value -notmatch 'Import-Module \(Join-Path \$env:RUNNER_TEMP ''Pester5/Pester.psd1''\) -Force\r?\n\s+\./tests/run-contract-tests.ps1 -UsePester' }).Count -eq 0
    $packageJob = [regex]::Match($release, '(?ms)^  package:\r?\n(?<job>.*)$').Groups['job'].Value
    $checks['Package checkout must retain credentials for ensure-release-tag git push'] = $packageJob -notmatch 'persist-credentials: false' -and $packageJob.Contains('scripts/ensure-release-tag.ps1')

    $publish = [regex]::Match($release, '(?m)^      - name: Publish versioned archive[^\r\n]*\r?\n[\s\S]*?^        run: \|\r?\n(?<code>(?:^          [^\r\n]*(?:\r?\n|$))+)')
    Assert $publish.Success 'Release publication step is missing or cannot be tested'
    $publishCode = ($publish.Groups['code'].Value -split '\r?\n' | Where-Object { $_.StartsWith('          ') } | ForEach-Object { $_.Substring(10) }) -join "`n"
    $savedVersion = $env:RELEASE_VERSION
    try {
        $env:RELEASE_VERSION = '3.0.0-rc.1'
        $script:releaseArguments = @()
        & {
            param([scriptblock]$Body)
            function gh {
                param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
                $script:releaseArguments = @($Arguments)
                $global:LASTEXITCODE = 0
            }
            & $Body
        } ([scriptblock]::Create($publishCode))
        foreach ($suffix in @('', '.sha256', '.inventory.json')) {
            $checks["GitHub Release publication is missing archive$suffix"] = "dist/controlflow-codex-3.0.0-rc.1.zip$suffix" -cin $script:releaseArguments
        }
        $checks['Publication must verify the tag and mark candidate releases as prereleases'] = '--verify-tag' -cin $script:releaseArguments -and '--prerelease' -cin $script:releaseArguments
        $checks['Publication must use the preserved versioned notes'] = $script:releaseArguments.IndexOf('--notes-file') -ge 0 -and $script:releaseArguments[$script:releaseArguments.IndexOf('--notes-file') + 1] -ceq 'dist/release-notes.md'
    } finally { $env:RELEASE_VERSION = $savedVersion; Remove-Variable releaseArguments -Scope Script -ErrorAction SilentlyContinue }
    $failedChecks = @($checks.Keys | Where-Object { -not $checks[$_] })
    Assert ($failedChecks.Count -eq 0) ("Release workflow contract failures:`n" + ($failedChecks -join "`n"))
} else { Write-Output 'SKIP release workflow validation: workflow files are not in the portable package' }

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
