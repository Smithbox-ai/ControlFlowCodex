param([ValidateSet('All', 'PathAliases', 'PluginCase')][string]$Regression = 'All')
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $repoRoot "scripts/install.ps1"

if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Missing installer script: $installerPath"
}

function Invoke-Installer([string]$HomeRoot, [switch]$Uninstall, [switch]$Force, [string]$Name = 'controlflow-codex', [string]$Script = $installerPath) {
    $global:LASTEXITCODE = 0
    $params = @{ HomeRoot = $HomeRoot; PluginName = $Name }
    if ($Uninstall) { $params["Uninstall"] = $true }
    if ($Force) { $params["Force"] = $true }
    $output = @()
    $caught = $null
    try {
        $output = @(& $Script @params 2>&1)
    } catch {
        $caught = $_
        $output = @($_.Exception.Message)
    }
    $exitCode = if ($null -ne $caught) { 1 } else { $global:LASTEXITCODE }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Assert-Path([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Installer smoke: missing $Label at $Path"
    }
}

function Assert-PathAbsent([string]$Path, [string]$Label) {
    if (Test-Path -LiteralPath $Path) {
        throw "Installer smoke: $Label should be absent but exists at $Path"
    }
}

function New-OwnedFixture([string]$FixtureHome, [switch]$CopyInstaller) {
    $fixtureSource = Join-Path $FixtureHome 'plugins/controlflow-codex'
    $fixtureMarket = Join-Path $FixtureHome '.agents/plugins/marketplace.json'
    New-Item -ItemType Directory -Path $fixtureSource, (Split-Path -Parent $fixtureMarket) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'plugin.json') -Destination (Join-Path $fixtureSource 'plugin.json')
    Set-Content -LiteralPath (Join-Path $fixtureSource 'sentinel.txt') -Value 'preserve source bytes'
    if ($CopyInstaller) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureSource 'scripts') | Out-Null
        foreach ($file in @('install.ps1', 'ControlFlow.Package.psm1')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/$file") -Destination (Join-Path $fixtureSource "scripts/$file")
        }
    }
    Set-Content -LiteralPath $fixtureMarket -Value '{"name":"fixture","plugins":[{"name":"controlflow-codex","keep":"registered"},{"name":"sibling","keep":"sibling"}]}'
    return [pscustomobject]@{ Source = $fixtureSource; Market = $fixtureMarket; MarketBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixtureMarket)); SourceFingerprint = Get-FixtureFingerprint $fixtureSource }
}

function Get-FixtureFingerprint([string]$Source) {
    return (@(Get-ChildItem -LiteralPath $Source -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        [IO.Path]::GetRelativePath($Source, $_.FullName) + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash
    }) -join '\n')
}

function Assert-FixturePreserved($Fixture, [string]$Label) {
    Assert-Path (Join-Path $Fixture.Source 'sentinel.txt') "$Label source bytes"
    if ((Get-FixtureFingerprint $Fixture.Source) -cne $Fixture.SourceFingerprint) { throw "$Label changed source tree or bytes" }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($Fixture.Market)) -cne $Fixture.MarketBytes) { throw "$Label changed registration bytes" }
}

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("controlflow-install-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $tempHome -Force | Out-Null

    if ($Regression -in @('All', 'PathAliases') -and $IsWindows) {
        foreach ($prefix in @('\\?\', '\\.\', '\??\', '//?/')) {
            $fixtureHome = Join-Path $tempHome ('alias-home-' + [guid]::NewGuid().ToString('N'))
            $fixture = New-OwnedFixture $fixtureHome -CopyInstaller
            $aliasHome = $prefix + $fixtureHome
            $copiedInstaller = Join-Path $fixture.Source 'scripts/install.ps1'
            $result = Invoke-Installer $aliasHome -Uninstall -Force -Script $copiedInstaller
            Assert-FixturePreserved $fixture "Namespace alias $prefix uninstall"
            if ($result.ExitCode -eq 0 -or ($result.Output -join '\n') -notmatch 'namespace|alias') { throw "Namespace alias $prefix did not fail explicitly before filesystem operations" }

            # This alias points inside the copied source. Lexical comparisons
            # must never turn source containment into permission to install.
            $nestedAliasHome = $prefix + (Join-Path $fixture.Source 'nested-home')
            $nested = Invoke-Installer $nestedAliasHome -Force -Script $copiedInstaller
            Assert-FixturePreserved $fixture "Namespace alias $prefix nested install"
            if ($nested.ExitCode -eq 0 -or ($nested.Output -join '\n') -notmatch 'namespace|alias') { throw "Namespace alias $prefix nested install did not fail explicitly" }
            Assert-PathAbsent (Join-Path $fixture.Source 'nested-home') 'nested alias installation'
        }
        Import-Module (Join-Path $repoRoot 'scripts/ControlFlow.Package.psm1') -Force
        foreach ($path in @((Join-Path $tempHome 'LEGACY~1/home'), (Join-Path $tempHome 'home.'), (Join-Path $tempHome 'home '), (Join-Path $tempHome 'NUL'))) {
            $rejected = $false
            try { $null = Resolve-ControlFlowPath $path } catch { $rejected = $_.Exception.Message -match 'namespace|alias|device' }
            if (-not $rejected) { throw "Windows alias/device path was not rejected before containment: $path" }
        }
        Write-Output 'VALID Windows namespace, short-name and device path regressions'
    }
    if ($Regression -in @('All', 'PluginCase')) {
        foreach ($name in @('CONTROLFLOW-CODEX', 'ControlFlow-Codex', 'controlflow-CODEX')) {
            foreach ($uninstallMode in @($true, $false)) {
                $fixtureHome = Join-Path $tempHome ('case-home-' + [guid]::NewGuid().ToString('N'))
                $fixture = New-OwnedFixture $fixtureHome
                $result = Invoke-Installer $fixtureHome -Name $name -Force -Uninstall:$uninstallMode
                Assert-FixturePreserved $fixture "PluginName $name"
                if ($result.ExitCode -eq 0 -or ($result.Output -join '\n') -notmatch 'PluginName') { throw "PluginName accepted upper/mixed case: $name" }
            }
        }
        Write-Output 'VALID lowercase-only plugin name regression'
    }
    if ($Regression -ne 'All') { return }
    $plug = Join-Path $tempHome "plugins/controlflow-codex"
    $marketplace = Join-Path $tempHome ".agents/plugins/marketplace.json"

    # Fresh install.
    $result = Invoke-Installer $tempHome -Force
    if ($result.ExitCode -ne 0) { throw "Install failed: $($result.Output -join [Environment]::NewLine)" }

    Assert-Path (Join-Path $plug ".codex-plugin/plugin.json") "plugin manifest"
    Assert-Path (Join-Path $plug "skills/controlflow-plan/SKILL.md") "plan skill"
    Assert-Path (Join-Path $plug "skills/controlflow-verify/SKILL.md") "verify skill"
    Assert-Path (Join-Path $plug "skills/controlflow-review/SKILL.md") "review skill"
    Assert-Path (Join-Path $plug "skills/controlflow/SKILL.md") "v3 entry skill"
    Assert-Path (Join-Path $plug "scripts/validate-contract.ps1") "v3 validator script"
    Assert-Path (Join-Path $plug "scripts/completion-gate.ps1") "v3 completion gate"
    Assert-Path (Join-Path $plug "scripts/install.ps1") "installer script"
    Assert-Path (Join-Path $plug "plans/templates/plan.meta.v3.json") "v3 nested template"
    Assert-Path (Join-Path $plug "plans/examples/small-v3.meta.json") "v3 SMALL example"
    Assert-Path (Join-Path $plug "evals/e2e-fixtures.ps1") "v3 executable eval fixtures"
    Assert-Path (Join-Path $plug "README.md") "README"
    Assert-Path (Join-Path $plug "LICENSE") "LICENSE"

    # Working state must not be copied.
    Assert-PathAbsent (Join-Path $plug ".git") "repo .git"
    Assert-PathAbsent (Join-Path $plug ".vs") "IDE .vs"

    # Marketplace entry registered.
    Assert-Path $marketplace "marketplace manifest"
    $mp = Get-Content -LiteralPath $marketplace -Raw | ConvertFrom-Json
    $entry = @($mp.plugins | Where-Object { $_.name -eq "controlflow-codex" })
    if ($entry.Count -ne 1) { throw "Installer smoke: marketplace entry not registered exactly once" }

    # A native exclusive installation lock protects registration read/modify/write
    # from a second writer, including different plugins under the same HomeRoot.
    $lockPath = Join-Path (Split-Path $marketplace -Parent) '.controlflow-install.lock'
    $heldLock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $concurrent = Invoke-Installer $tempHome -Force
        if ($concurrent.ExitCode -eq 0) { throw 'Concurrent installer ignored the exclusive home registration lock' }
        Assert-Path (Join-Path $plug 'scripts/validate-contract.ps1') 'installed bytes while registration locked'
    } finally { $heldLock.Dispose() }

    # Parse failures must never remove the prior files, even on uninstall.
    $marketBytes = [IO.File]::ReadAllBytes($marketplace)
    Set-Content -LiteralPath $marketplace -Value '{broken json'
    foreach ($uninstallMode in @($false, $true)) {
        $failed = Invoke-Installer $tempHome -Force -Uninstall:$uninstallMode
        if ($failed.ExitCode -eq 0) { throw 'Malformed marketplace was accepted' }
        Assert-Path (Join-Path $plug 'scripts/validate-contract.ps1') 'existing bytes after malformed marketplace'
    }
    [IO.File]::WriteAllBytes($marketplace, $marketBytes)

    # Windows denies atomic rename when another process holds a no-delete file
    # handle. This is a real filesystem failure after the new tree was staged.
    if ($IsWindows) {
        $sentinel = Join-Path $plug 'rollback-sentinel.txt'
        Set-Content -LiteralPath $sentinel 'old installed bytes'
        foreach ($uninstallMode in @($false, $true)) {
            $handle = [IO.File]::Open($marketplace, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $blocked = Invoke-Installer $tempHome -Force -Uninstall:$uninstallMode
                if ($blocked.ExitCode -eq 0) { throw 'Marketplace rename unexpectedly succeeded while locked' }
                Assert-Path $sentinel 'installed bytes after registration failure'
                if ((Get-Content -LiteralPath $sentinel -Raw).Trim() -ne 'old installed bytes') { throw 'Rollback changed installed bytes' }
                if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($marketplace)) -ne [Convert]::ToBase64String($marketBytes)) { throw 'Registration failure mutated marketplace' }
            } finally { $handle.Dispose() }
        }
    }

    # An ancestor junction/symlink must never route registration outside HomeRoot.
    $linkedHome = Join-Path $tempHome 'linked-home'
    $outside = Join-Path $tempHome 'outside-link-target'
    New-Item -ItemType Directory -Path $linkedHome, $outside -Force | Out-Null
    $link = Join-Path $linkedHome '.agents'
    $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path $link -Target $outside | Out-Null
    try {
        $linked = Invoke-Installer $linkedHome -Force
        if ($linked.ExitCode -eq 0 -or (Test-Path -LiteralPath (Join-Path $outside 'plugins/marketplace.json'))) { throw 'Installer followed a linked ancestor' }
    } finally {
        $checkedLink = [IO.Path]::GetFullPath($link)
        if (-not $checkedLink.StartsWith([IO.Path]::GetFullPath($linkedHome) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe link cleanup path' }
        Remove-Item -LiteralPath $checkedLink -Force
    }

    foreach ($name in @('../escape', '..\escape', '.', '..', 'C:\escape', '/escape', 'name/child', 'name\child', 'CON', 'name.', 'name:stream', '')) {
        $bad = Invoke-Installer $tempHome -Force -Name $name
        if ($bad.ExitCode -eq 0) { throw "Accepted unsafe PluginName: '$name'" }
    }

    Assert-Path (Join-Path $plug 'plugin.json') 'portable manifest'
    Assert-Path (Join-Path $plug 'plans/examples/small-v3.meta.json') 'v3 example metadata'
    $obsolete=(Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/package-inventory.json') -Raw|ConvertFrom-Json).obsolete
    foreach($relative in $obsolete){Assert-PathAbsent (Join-Path $plug $relative) "obsolete v2 path $relative"}

    # Invalid copied source must leave old files and marketplace unchanged.
    $broken = Join-Path $tempHome 'broken-source'
    New-Item -ItemType Directory -Path $broken | Out-Null
    Remove-ControlFlowTree $broken $tempHome
    Copy-ControlFlowPackage $repoRoot $broken
    Set-Content -LiteralPath (Join-Path $broken '.codex-plugin/plugin.json') -Value '{}'
    $bad = Invoke-Installer $tempHome -Force -Script (Join-Path $broken 'scripts/install.ps1')
    if ($bad.ExitCode -eq 0) { throw 'Invalid source was installed' }
    Assert-Path (Join-Path $plug 'scripts/validate-contract.ps1') 'old installed bytes after invalid source'
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($marketplace)) -ne [Convert]::ToBase64String($marketBytes)) { throw 'Invalid source mutated marketplace' }

    $overlap = Invoke-Installer $broken -Force -Script (Join-Path $broken 'scripts/install.ps1')
    if ($overlap.ExitCode -eq 0) { throw 'Target inside source root was accepted' }
    Assert-PathAbsent (Join-Path $broken 'plugins/controlflow-codex') 'overlapping target'

    $unownedHome = Join-Path $tempHome 'unowned-home'
    $unowned = Join-Path $unownedHome 'plugins/controlflow-codex'
    New-Item -ItemType Directory -Path $unowned -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $unowned 'keep.txt') 'unowned bytes'
    foreach ($uninstallMode in @($false, $true)) {
        $bad = Invoke-Installer $unownedHome -Force -Uninstall:$uninstallMode
        if ($bad.ExitCode -eq 0) { throw 'Unowned existing target was mutated' }
        Assert-Path (Join-Path $unowned 'keep.txt') 'unowned bytes'
    }

    $mp.plugins += [pscustomobject]@{ name = 'sibling'; custom = 'retained' }
    $mp | Add-Member -NotePropertyName extra -NotePropertyValue 42
    $mp | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $marketplace

    # Clean reinstall removes orphaned files from a previous version.
    $stale = Join-Path $plug "scripts/OLD-removed-script.ps1"
    Set-Content -LiteralPath $stale -Value "# stale orphan" -Encoding UTF8
    Assert-Path $stale "stale orphan (pre-reinstall)"

    $reinstall = Invoke-Installer $tempHome -Force
    if ($reinstall.ExitCode -ne 0) { throw "Reinstall failed: $($reinstall.Output -join [Environment]::NewLine)" }
    Assert-PathAbsent $stale "stale orphan (post-reinstall)"
    Assert-Path (Join-Path $plug "scripts/validate-contract.ps1") "v3 validator after reinstall"
    foreach($relative in $obsolete){Assert-PathAbsent (Join-Path $plug $relative) "obsolete v2 path after reinstall $relative"}

    # Installing over an existing target without -Force must refuse.
    $refuse = Invoke-Installer $tempHome
    if ($refuse.ExitCode -eq 0) { throw "Installer smoke: install over existing target without -Force must fail" }

    # Uninstall removes files and marketplace entry.
    $uninstall = Invoke-Installer $tempHome -Uninstall -Force
    if ($uninstall.ExitCode -ne 0) { throw "Uninstall failed: $($uninstall.Output -join [Environment]::NewLine)" }
    Assert-PathAbsent $plug "plugin dir after uninstall"
    if (Test-Path -LiteralPath $marketplace) {
        $mpAfter = Get-Content -LiteralPath $marketplace -Raw | ConvertFrom-Json
        $leftover = @($mpAfter.plugins | Where-Object { $_.name -eq "controlflow-codex" })
        if ($leftover.Count -ne 0) { throw "Installer smoke: marketplace entry not removed on uninstall" }
        if ($mpAfter.extra -ne 42 -or @($mpAfter.plugins | Where-Object name -eq 'sibling')[0].custom -ne 'retained') { throw 'Marketplace lost sibling or custom metadata' }
    }
} finally {
    if (Test-Path -LiteralPath $tempHome) {
        $tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not [IO.Path]::GetFullPath($tempHome).StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }
        Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$global:LASTEXITCODE = 0
Write-Output "VALID installer smoke contract"

