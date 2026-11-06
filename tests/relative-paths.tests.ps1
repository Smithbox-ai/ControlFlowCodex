param([ValidateSet('All','CoreIdentity','CoreGit','CorePath','SourceDigest','PackagePath','InstallerDryRun','PackageOutput','Providers','NativeAbsolute','UnixLiteralBackslash')][string]$Case = 'All')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$originalProcessDirectory = [Environment]::CurrentDirectory
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$fixture = Join-Path $tempBase ('cf-relative-paths-' + [guid]::NewGuid().ToString('N'))
$failures = [Collections.Generic.List[string]]::new()
function Assert-RelativePath([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Test-RelativePathCase([string]$Name, [scriptblock]$Action) {
    if ($Case -notin @('All', $Name)) { return }
    try {
        & $Action
        Assert-RelativePath ([Environment]::CurrentDirectory -ceq $processDirectory) "$Name changed the process working directory"
        Assert-RelativePath ((Get-Location).ProviderPath -ceq $locationDirectory) "$Name changed the PowerShell location"
        Write-Output "VALID relative paths $Name"
    } catch {
        $failures.Add("${Name}: $($_.Exception.Message)")
        Write-Output "INVALID relative paths ${Name}: $($_.Exception.Message)"
    }
}
try {
    $processDirectory = Join-Path $fixture 'process'
    $locationDirectory = Join-Path $fixture 'location'
    New-Item -ItemType Directory -Path $processDirectory, $locationDirectory -Force | Out-Null
    foreach ($directory in @($processDirectory, $locationDirectory)) {
        & git init -q -- $directory
        if ($LASTEXITCODE -ne 0) { throw 'Relative-path fixture git init failed' }
        $emptyIgnore = Join-Path $directory '.git/fixture-ignore'
        [IO.File]::WriteAllText($emptyIgnore, '')
        & git -C $directory config core.excludesFile $emptyIgnore
        if ($LASTEXITCODE -ne 0) { throw 'Relative-path fixture ignore configuration failed' }
    }
    # Installer tests can leave modules with the same name loaded from extracted
    # archives. Select the module returned by this exact import, not its name.
    $core = Import-Module (Join-Path $repoRoot 'scripts/ControlFlow.Core.psm1') -Force -DisableNameChecking -PassThru
    Import-Module (Join-Path $repoRoot 'scripts/ControlFlow.Package.psm1') -Force -DisableNameChecking
    [Environment]::CurrentDirectory = $processDirectory
    Set-Location -LiteralPath $locationDirectory
    Assert-RelativePath ([Environment]::CurrentDirectory -ceq $processDirectory) 'Fixture requires distinct process and PowerShell working directories'

    # Replacing PS-aware resolution with Path.GetFullPath('.') selects the other real Git repository.
    Test-RelativePathCase CoreIdentity {
        $identity = & $core { Get-CFIdentity '.' }
        Assert-RelativePath ($identity.worktree_realpath -ceq $locationDirectory) "RepoRoot '.' selected $($identity.worktree_realpath), expected $locationDirectory"
        Assert-RelativePath ($identity.git_dir_realpath -ceq (Join-Path $locationDirectory '.git')) 'Relative repository selected the wrong Git directory'
    }
    Test-RelativePathCase CorePath {
        $resolved = & $core { Get-CFFullPath './missing/../artifact.json' }
        Assert-RelativePath ($resolved -ceq (Join-Path $locationDirectory 'artifact.json')) 'Core relative file path ignored the PowerShell location'
    }
    Test-RelativePathCase CoreGit {
        $top = & $core { Get-CFGitText '.' @('rev-parse', '--show-toplevel') }
        Assert-RelativePath ($top.Replace('/', [IO.Path]::DirectorySeparatorChar) -ceq $locationDirectory) 'Relative Git execution selected the process working directory'
    }
    Test-RelativePathCase SourceDigest {
        [IO.File]::WriteAllText((Join-Path $locationDirectory 'owned.txt'), 'location source')
        [IO.File]::WriteAllText((Join-Path $locationDirectory 'removed.txt'), 'baseline source')
        & git -C $locationDirectory add -- owned.txt removed.txt
        if ($LASTEXITCODE -ne 0) { throw 'Source digest fixture git add failed' }
        & git -C $locationDirectory -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm baseline
        if ($LASTEXITCODE -ne 0) { throw 'Source digest fixture baseline commit failed' }
        $baseline = (& git -C $locationDirectory rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Source digest fixture baseline observation failed' }
        & git -C $locationDirectory rm -q -- removed.txt
        if ($LASTEXITCODE -ne 0) { throw 'Source digest fixture git rm failed' }
        & git -C $locationDirectory -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm remove
        if ($LASTEXITCODE -ne 0) { throw 'Source digest fixture removal commit failed' }
        [IO.File]::WriteAllText((Join-Path $processDirectory 'removed.txt'), 'unrelated process directory decoy')
        $source = Get-ControlFlowSourceDigest -RepoRoot '.' -Baseline $baseline
        $removed = @($source.entries | Where-Object path -CEQ 'removed.txt')
        Assert-RelativePath ($removed.Count -eq 1 -and $removed[0].mode -ceq 'deleted' -and $removed[0].hash -ceq 'deleted') 'Source digest read baseline-only content from the process working directory'
        $owned = @($source.entries | Where-Object path -CEQ 'owned.txt')
        $expectedHash = (Get-FileHash -LiteralPath (Join-Path $locationDirectory 'owned.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-RelativePath ($source.entries.Count -eq 2 -and $owned.Count -eq 1 -and $owned[0].hash -ceq $expectedHash) 'Source digest did not observe the PowerShell-relative repository'
        $child = Join-Path $locationDirectory 'child'
        New-Item -ItemType Directory -Path $child | Out-Null
        [IO.File]::WriteAllText((Join-Path $child 'removed.txt'), 'unrelated child directory decoy')
        $fromRoot = Get-ControlFlowSourceDigest -RepoRoot $locationDirectory -Baseline $baseline
        Push-Location -LiteralPath $child
        try { $fromChild = Get-ControlFlowSourceDigest -RepoRoot '.' -Baseline $baseline } finally { Pop-Location }
        $removedFromChild = @($fromChild.entries | Where-Object path -CEQ 'removed.txt')
        Assert-RelativePath ($removedFromChild.Count -eq 1 -and $removedFromChild[0].mode -ceq 'deleted') 'Source digest read baseline-only content from a child directory'
        Assert-RelativePath ($fromChild.digest -ceq $fromRoot.digest) 'Source digest changed when RepoRoot selected a child of the same repository'
    }
    Test-RelativePathCase PackagePath {
        $resolved = Resolve-ControlFlowPath './home'
        Assert-RelativePath ($resolved -ceq (Join-Path $locationDirectory 'home')) 'Package HomeRoot ignored the PowerShell location'
    }
    Test-RelativePathCase InstallerDryRun {
        $output = @(& (Join-Path $repoRoot 'scripts/install.ps1') -HomeRoot './home' -DryRun 3>$null)
        $target = Join-Path $locationDirectory 'home/plugins/controlflow-codex'
        Assert-RelativePath (($output -join "`n").Contains(" to $target (selection:")) "Installer DryRun did not report the PowerShell-relative target: $($output -join ' ')"
        foreach ($directory in @($processDirectory, $locationDirectory)) {
            Assert-RelativePath (-not (Test-Path -LiteralPath (Join-Path $directory 'home'))) 'Installer DryRun created a home directory'
        }
    }
    # package.ps1 resolves OutputDirectory with this shared resolver before archive staging.
    Test-RelativePathCase PackageOutput {
        $resolved = Resolve-ControlFlowPath './dist/releases'
        Assert-RelativePath ($resolved -ceq (Join-Path $locationDirectory 'dist/releases')) 'Package OutputDirectory ignored the PowerShell location'
        Assert-RelativePath (-not (Test-Path -LiteralPath $resolved)) 'Package output resolution created directories'
    }
    Test-RelativePathCase NativeAbsolute {
        $nativePath = if ($IsWindows) { '\\controlflow-fixture.invalid\share\file' } else { $locationDirectory }
        $link = Join-Path $fixture 'linked'
        if ($IsWindows) { New-Item -ItemType Junction -Path $link -Target $locationDirectory | Out-Null }
        else { [IO.Directory]::CreateSymbolicLink($link, $locationDirectory) | Out-Null }
        try {
            Push-Location Env:
            try {
                $resolved = & $core { param($value) Get-CFFullPath $value } $nativePath
                Assert-RelativePath ($resolved -ceq $nativePath) 'A native absolute filesystem path depended on the active provider'
                $rejected = $false
                try { $null = Resolve-ControlFlowPath $link } catch { $rejected = $_.Exception.Message -match 'Link/reparse' }
                Assert-RelativePath $rejected 'Package native absolute paths skipped their link protection from a non-filesystem provider'
            } finally { Pop-Location }
        } finally { [IO.Directory]::Delete($link) }
    }
    if (-not $IsWindows) {
        Test-RelativePathCase UnixLiteralBackslash {
            $literalRoot = [IO.Path]::Combine($fixture, 'literal\name')
            [IO.Directory]::CreateDirectory($literalRoot) | Out-Null
            try {
                $corePath = & $core { param($value) Get-CFFullPath $value } $literalRoot
                Assert-RelativePath ($corePath -ceq $literalRoot) 'Core absolute Unix paths rewrote a literal backslash'
                Assert-RelativePath ((Resolve-ControlFlowPath $literalRoot) -ceq $literalRoot) 'Package absolute Unix paths rewrote a literal backslash'
                $link = [IO.Path]::Combine($literalRoot, 'linked')
                [IO.Directory]::CreateSymbolicLink($link, $locationDirectory) | Out-Null
                $rejected = $false
                try { $null = Resolve-ControlFlowPath $link } catch { $rejected = $_.Exception.Message -match 'Link/reparse' }
                Assert-RelativePath $rejected 'Package Unix paths with a literal backslash skipped their link protection'
            } finally { [IO.Directory]::Delete($literalRoot, $true) }
        }
    } elseif ($Case -in @('All','UnixLiteralBackslash')) {
        Write-Output 'SKIP relative paths UnixLiteralBackslash: requires Unix native path semantics'
    }
    Test-RelativePathCase Providers {
        foreach ($resolver in @({ param($Path) & $core { param($value) Get-CFFullPath $value } $Path }, { param($Path) Resolve-ControlFlowPath $Path })) {
            $rejected = $false
            try { $null = & $resolver 'Env:CONTROLFLOW_RELATIVE_PATH_TEST' } catch { $rejected = $_.Exception.Message -match 'FILESYSTEM|FileSystem' }
            Assert-RelativePath $rejected 'A non-filesystem provider path was not rejected explicitly'
            Push-Location Env:
            try {
                $rejected = $false
                try { $null = & $resolver '.' } catch { $rejected = $_.Exception.Message -match 'FILESYSTEM|FileSystem' }
                Assert-RelativePath $rejected 'A relative path from a non-filesystem location was not rejected explicitly'
                Assert-RelativePath ((& $resolver $locationDirectory) -ceq $locationDirectory) 'A native absolute filesystem path depended on the active provider'
                $filesystemPath = 'FileSystem::' + $locationDirectory
                Assert-RelativePath ((& $resolver $filesystemPath) -ceq $locationDirectory) 'An explicitly qualified filesystem path depended on the active provider'
            } finally { Pop-Location }
        }
    }
} finally {
    Set-Location -LiteralPath $originalLocation.Path
    [Environment]::CurrentDirectory = $originalProcessDirectory
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (-not $resolvedFixture.StartsWith($tempBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolvedFixture).StartsWith('cf-relative-paths-')) { throw 'Unsafe relative-path fixture cleanup' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
if ($failures.Count) { throw ($failures -join "`n") }
