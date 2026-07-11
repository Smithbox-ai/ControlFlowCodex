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
    <#
    Returns $null when git fails or is unavailable.
    Returns a plain string (joined output) on success.
    #>
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
    <#
    Returns $null when git fails or is unavailable.
    Returns a sorted string array on success.
    #>
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
        $cleaned = @($strings | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Sort-Object)
        return $cleaned
    } catch {
        return $null
    } finally {
        $ErrorActionPreference = $previousPreference
    }
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
    } else {
        $branch = $null
        $headCommit = $null
        $dirty = $null
        $trackedFiles = @()
        $trackedFileCount = 0
        $fileTreeDigest = $null
    }

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
        }
    }

    $result | ConvertTo-Json -Depth 4 -Compress
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
        }
        error = $_.Exception.Message
    }
    $failure | ConvertTo-Json -Depth 4 -Compress
    exit 1
}
