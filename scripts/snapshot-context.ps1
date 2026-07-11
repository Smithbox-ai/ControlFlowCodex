param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath
)

$ErrorActionPreference = "Stop"

function Get-FileTreeDigest([string[]]$Files) {
    if ($null -eq $Files -or $Files.Count -eq 0) {
        return $null
    }
    $joined = ($Files | Sort-Object) -join "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($bytes)
    } finally {
        $sha256.Dispose()
    }
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ''
}

function Invoke-GitSafe([string]$Root, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $global:LASTEXITCODE = 0
        $allArgs = @("-C", $Root) + $Arguments
        $output = @(& git @allArgs 2>&1)
        $exitCode = $global:LASTEXITCODE
        if ($exitCode -ne 0) {
            return $null
        }
        $strings = @($output | Where-Object { $_ -is [string] })
        return ($strings -join "`n")
    } catch {
        return $null
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Invoke-GitListSafe([string]$Root, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $global:LASTEXITCODE = 0
        $allArgs = @("-C", $Root) + $Arguments
        $output = @(& git @allArgs 2>&1)
        $exitCode = $global:LASTEXITCODE
        if ($exitCode -ne 0) {
            return $null
        }
        $strings = @($output | Where-Object { $_ -is [string] })
        $cleaned = @($strings | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
        return $cleaned
    } catch {
        return $null
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Find-DetectedFrameworks([string[]]$TrackedFiles) {
    $frameworks = [System.Collections.Generic.SortedSet[string]]::new()

    foreach ($file in $TrackedFiles) {
        $lower = $file.ToLowerInvariant()
        if ($lower -match '\.tests\.ps1$' -or $lower -match '\.tests\.ps11$') {
            [void]$frameworks.Add("pester")
        }
        if ($lower -match '_test\.go$') {
            [void]$frameworks.Add("go-testing")
        }
        if ($lower -match '\.spec\.ts$' -or $lower -match '\.spec\.js$' -or $lower -match '\.spec\.tsx$') {
            [void]$frameworks.Add("jasmine")
        }
        if ($lower -match '\.test\.ts$' -or $lower -match '\.test\.js$') {
            [void]$frameworks.Add("jest")
        }
        if ($lower -match 'test_.+\.py$' -or $lower -match '.+_test\.py$') {
            [void]$frameworks.Add("pytest")
        }
        if ($lower -match '\.csproj$') {
            [void]$frameworks.Add("dotnet-test")
        }
    }

    $leafNames = @($TrackedFiles | ForEach-Object { Split-Path $_ -Leaf } | Where-Object { $_ -is [string] })
    if ($leafNames -contains "jest.config.js" -or $leafNames -contains "jest.config.ts" -or $leafNames -contains "jest.config.json") {
        [void]$frameworks.Add("jest")
    }
    if ($leafNames -contains "vitest.config.ts" -or $leafNames -contains "vitest.config.js") {
        [void]$frameworks.Add("vitest")
    }
    if ($leafNames -contains "pytest.ini" -or $leafNames -contains "tox.ini" -or $leafNames -contains "conftest.py") {
        [void]$frameworks.Add("pytest")
    }
    if ($leafNames -contains ".mocharc.yml" -or $leafNames -contains ".mocharc.json" -or $leafNames -contains ".mocharc.js") {
        [void]$frameworks.Add("mocha")
    }

    $result = @($frameworks | Sort-Object)
    return , $result
}

function Find-DetectedPackageManagers([string[]]$TrackedFiles) {
    $managers = [System.Collections.Generic.SortedSet[string]]::new()
    $leafNames = @($TrackedFiles | ForEach-Object { Split-Path $_ -Leaf } | Where-Object { $_ -is [string] })

    if ($leafNames -contains "package.json") {
        [void]$managers.Add("npm")
    }
    if ($leafNames -contains "yarn.lock") {
        [void]$managers.Add("yarn")
    }
    if ($leafNames -contains "pnpm-lock.yaml") {
        [void]$managers.Add("pnpm")
    }
    if ($leafNames -contains "requirements.txt" -or $leafNames -contains "setup.py") {
        [void]$managers.Add("pip")
    }
    if ($leafNames -contains "pyproject.toml") {
        [void]$managers.Add("pip")
    }
    if ($leafNames -contains "poetry.lock") {
        [void]$managers.Add("poetry")
    }
    if ($leafNames -contains "Pipfile") {
        [void]$managers.Add("pipenv")
    }
    if ($leafNames -contains "go.mod") {
        [void]$managers.Add("go-modules")
    }
    if ($leafNames -contains "Cargo.toml") {
        [void]$managers.Add("cargo")
    }
    if ($leafNames -contains "pom.xml") {
        [void]$managers.Add("maven")
    }
    if ($leafNames -contains "build.gradle" -or $leafNames -contains "build.gradle.kts") {
        [void]$managers.Add("gradle")
    }

    foreach ($file in $TrackedFiles) {
        $lower = $file.ToLowerInvariant()
        if ($lower -match '\.csproj$' -or $lower -match '\.sln$' -or $lower -match '\.slnx$' -or $lower -match 'packages\.config$') {
            [void]$managers.Add("nuget")
        }
    }

    $result = @($managers | Sort-Object)
    return , $result
}

function Find-DetectedCiSystems([string[]]$TrackedFiles) {
    $systems = [System.Collections.Generic.SortedSet[string]]::new()

    foreach ($file in $TrackedFiles) {
        $lower = $file.ToLowerInvariant()
        if ($lower -match '^\.github/workflows/.+\.ya?ml$') {
            [void]$systems.Add("github-actions")
        }
        if ($lower -eq ".gitlab-ci.yml") {
            [void]$systems.Add("gitlab-ci")
        }
        if ($lower -eq "azure-pipelines.yml" -or $lower -eq "azure-pipelines.yaml") {
            [void]$systems.Add("azure-pipelines")
        }
        if ($lower -eq "jenkinsfile") {
            [void]$systems.Add("jenkins")
        }
        if ($lower -eq ".circleci/config.yml") {
            [void]$systems.Add("circleci")
        }
        if ($lower -eq ".travis.yml") {
            [void]$systems.Add("travis-ci")
        }
        if ($lower -eq "appveyor.yml") {
            [void]$systems.Add("appveyor")
        }
    }

    $result = @($systems | Sort-Object)
    return , $result
}

function Find-DocsLanguage([string]$Root, [string[]]$TrackedFiles) {
    $readmePath = $null
    foreach ($file in $TrackedFiles) {
        $leaf = Split-Path $file -Leaf
        if ($leaf -ieq "README.md" -or $leaf -ieq "README.rst" -or $leaf -ieq "README") {
            $readmePath = Join-Path $Root $file
            break
        }
    }

    if ($null -eq $readmePath -or -not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
        return "unknown"
    }

    try {
        $content = Get-Content -LiteralPath $readmePath -Raw -ErrorAction Stop
    } catch {
        return "unknown"
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        return "unknown"
    }

    $cyrillicCount = ([regex]::Matches($content, '[\u0400-\u04FF]')).Count
    $cjkCount = ([regex]::Matches($content, '[\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FF]')).Count
    $latinCount = ([regex]::Matches($content, '[a-zA-Z]')).Count

    if ($cyrillicCount -gt 0 -and $cyrillicCount -gt ($latinCount * 0.3)) {
        return "ru"
    }
    if ($cjkCount -gt 0 -and $cjkCount -gt ($latinCount * 0.3)) {
        return "cjk"
    }
    if ($latinCount -gt 0) {
        return "en"
    }
    if ($cyrillicCount -gt 0) {
        return "ru"
    }
    return "unknown"
}

try {
    $repoRootResolved = (Resolve-Path $RepoRoot).Path

    $planResolved = if ([System.IO.Path]::IsPathRooted($PlanPath)) {
        [System.IO.Path]::GetFullPath($PlanPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repoRootResolved $PlanPath))
    }

    $planLeaf = Split-Path $planResolved -Leaf
    if ($planLeaf -notmatch '^(?<slug>.+)-plan\.md$') {
        throw "Plan filename must end with '-plan.md': $planLeaf"
    }
    $taskSlug = $Matches['slug']

    $relativePlanPath = $planResolved.Substring($repoRootResolved.Length) -replace '^[\\/]+', '' -replace '\\', '/'

    $timestamp = (Get-Date).ToUniversalTime().ToString("o")

    $gitCheck = Invoke-GitSafe $repoRootResolved @("rev-parse", "--is-inside-work-tree")
    $gitAvailable = ($null -ne $gitCheck -and $gitCheck.Trim() -ieq "true")

    if ($gitAvailable) {
        $branchRaw = Invoke-GitSafe $repoRootResolved @("rev-parse", "--abbrev-ref", "HEAD")
        $branch = if ($null -ne $branchRaw) { $branchRaw.Trim() } else { $null }

        $headRaw = Invoke-GitSafe $repoRootResolved @("rev-parse", "HEAD")
        $headCommit = if ($null -ne $headRaw) { $headRaw.Trim() } else { $null }

        $statusRaw = Invoke-GitSafe $repoRootResolved @("status", "--porcelain")
        $dirty = if ($null -ne $statusRaw) { -not [string]::IsNullOrWhiteSpace($statusRaw) } else { $false }

        $trackedFiles = Invoke-GitListSafe $repoRootResolved @("ls-files")
        if ($null -eq $trackedFiles) {
            $trackedFiles = @()
        }

        $trackedFileCount = $trackedFiles.Count
        $fileTreeDigest = Get-FileTreeDigest $trackedFiles

        $recentFiles = Invoke-GitListSafe $repoRootResolved @("log", "--name-only", "--pretty=format:", "-10")
        if ($null -eq $recentFiles) {
            $recentFiles = @()
        }
    } else {
        $branch = $null
        $headCommit = $null
        $dirty = $null
        $trackedFiles = @()
        $trackedFileCount = 0
        $fileTreeDigest = $null
        $recentFiles = @()
    }

    $testFrameworks = Find-DetectedFrameworks $trackedFiles
    $packageManagers = Find-DetectedPackageManagers $trackedFiles
    $ciSystems = Find-DetectedCiSystems $trackedFiles
    $docsLanguage = Find-DocsLanguage $repoRootResolved $trackedFiles

    $result = [ordered]@{
        schema_version = "1.0.0"
        plan_path = $relativePlanPath
        task_slug = $taskSlug
        captured_at = $timestamp
        git = [ordered]@{
            available = $gitAvailable
            branch = $branch
            head_commit = $headCommit
            dirty = $dirty
            tracked_files = $trackedFiles
            tracked_file_count = $trackedFileCount
            file_tree_digest = $fileTreeDigest
            recent_files = $recentFiles
        }
        repository = [ordered]@{
            test_frameworks = $testFrameworks
            package_managers = $packageManagers
            ci_systems = $ciSystems
            docs_language = $docsLanguage
        }
    }

    $result | ConvertTo-Json -Depth 5 -Compress
} catch {
    $failure = [ordered]@{
        schema_version = "1.0.0"
        plan_path = $PlanPath.Replace('\', '/')
        task_slug = $null
        captured_at = (Get-Date).ToUniversalTime().ToString("o")
        git = [ordered]@{
            available = $false
            branch = $null
            head_commit = $null
            dirty = $null
            tracked_files = @()
            tracked_file_count = 0
            file_tree_digest = $null
            recent_files = @()
        }
        repository = [ordered]@{
            test_frameworks = @()
            package_managers = @()
            ci_systems = @()
            docs_language = "unknown"
        }
        error = $_.Exception.Message
    }
    $failure | ConvertTo-Json -Depth 5 -Compress
    exit 1
}
