param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [string]$BaseCommit
)

$ErrorActionPreference = "Stop"

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-Property([object]$Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    if ($property.Value -is [System.Array]) {
        Write-Output -NoEnumerate $property.Value
        return
    }
    return $property.Value
}

function Invoke-GitListSafe([string]$Root, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $global:LASTEXITCODE = 0
        $allArgs = @("-C", $Root) + $Arguments
        $output = @(& git @allArgs 2>&1)
        if ($global:LASTEXITCODE -ne 0) {
            return $null
        }
        $strings = @($output | Where-Object { $_ -is [string] } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().Replace('\', '/') } | Sort-Object -Unique)
        return , $strings
    } catch {
        return $null
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Invoke-GitSafe([string]$Root, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $global:LASTEXITCODE = 0
        $allArgs = @("-C", $Root) + $Arguments
        $output = @(& git @allArgs 2>&1)
        if ($global:LASTEXITCODE -ne 0) {
            return $null
        }
        $strings = @($output | Where-Object { $_ -is [string] })
        return ($strings -join "`n").Trim()
    } catch {
        return $null
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Convert-GlobToRegex([string]$Glob) {
    $escaped = [regex]::Escape($Glob)
    $escaped = $escaped -replace '\\\*\\\*', '.*'
    $escaped = $escaped -replace '\\\*', '[^/]*'
    return '^' + $escaped + '$'
}

function Test-PathMatchesScope([string]$Path, [string[]]$ScopeGlobs) {
    foreach ($glob in $ScopeGlobs) {
        $pattern = Convert-GlobToRegex $glob
        if ($Path -match $pattern) {
            return $true
        }
    }
    return $false
}

function New-EmptyResult([string]$PlanPath, [string]$Error) {
    $failure = [ordered]@{
        schema_version = "2.0.0"
        plan_path = $PlanPath.Replace('\', '/')
        task_slug = $null
        base_commit = $null
        head_commit = $null
        changed_file_count = 0
        summary = [ordered]@{
            planned = 0
            unplanned = 0
            scope_but_unmatched = 0
        }
        classifications = @()
        scope_but_unmatched = @()
        verdict = "ERROR"
        error = $Error
    }
    $failure | ConvertTo-Json -Depth 5 -Compress
}

try {
    $repoRootResolved = (Resolve-Path $RepoRoot).Path

    $planResolved = if ([System.IO.Path]::IsPathRooted($PlanPath)) {
        [System.IO.Path]::GetFullPath($PlanPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repoRootResolved $PlanPath))
    }

    if (-not (Test-Path -LiteralPath $planResolved -PathType Leaf)) {
        throw "Missing plan file: $planResolved"
    }

    $planLeaf = Split-Path $planResolved -Leaf
    if ($planLeaf -notmatch '^(?<slug>.+)-plan\.md$') {
        throw "Plan filename must end with '-plan.md': $planLeaf"
    }
    $taskSlug = $Matches['slug']

    $relativePlanPath = $planResolved.Substring($repoRootResolved.Length) -replace '^[\\/]+', '' -replace '\\', '/'

    $metadataPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/plan.meta.json"
    $metadata = Read-JsonFile $metadataPath
    if ($null -eq $metadata) {
        throw "Missing plan metadata: $metadataPath"
    }

    $scopeGlobs = @()
    $scopeProp = Get-Property $metadata "scope"
    if ($null -ne $scopeProp -and $scopeProp -is [System.Array]) {
        $scopeGlobs = @($scopeProp | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    }
    if ($scopeGlobs.Count -eq 0) {
        throw "plan.meta.json has no scope patterns"
    }

    $baselineCommit = $null
    $baseline = Get-Property $metadata "baseline"
    if ($null -ne $baseline) {
        $commit = Get-Property $baseline "commit"
        if ($commit -is [string] -and -not [string]::IsNullOrWhiteSpace($commit)) {
            $baselineCommit = $commit.Trim()
        }
    }

    $resolvedBase = $baselineCommit
    if ([string]::IsNullOrWhiteSpace($resolvedBase)) {
        $resolvedBase = $BaseCommit
    }
    if ([string]::IsNullOrWhiteSpace($resolvedBase)) {
        $resolvedBase = "HEAD"
    }

    $baseResolved = Invoke-GitSafe $repoRootResolved @("rev-parse", $resolvedBase)
    $baseSha = if ($null -ne $baseResolved -and $baseResolved -ne "") { $baseResolved } else { $resolvedBase }

    $headRaw = Invoke-GitSafe $repoRootResolved @("rev-parse", "HEAD")
    $headSha = if ($null -ne $headRaw -and $headRaw -ne "") { $headRaw } else { "HEAD" }

    $committed = Invoke-GitListSafe $repoRootResolved @("diff", "--name-only", $baseSha, $headSha)
    $staged = Invoke-GitListSafe $repoRootResolved @("diff", "--name-only", "--cached")
    $unstaged = Invoke-GitListSafe $repoRootResolved @("diff", "--name-only")
    $untracked = Invoke-GitListSafe $repoRootResolved @("ls-files", "--others", "--exclude-standard")

    $changed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($list in @($committed, $staged, $unstaged, $untracked)) {
        if ($null -ne $list) {
            foreach ($p in $list) { [void]$changed.Add($p) }
        }
    }
    $changedFiles = @($changed | Sort-Object)

    $classifications = [System.Collections.ArrayList]::new()
    $plannedCount = 0
    $unplannedCount = 0

    foreach ($file in $changedFiles) {
        $classification = if (Test-PathMatchesScope $file $scopeGlobs) { "planned" } else { "unplanned" }
        if ($classification -eq "planned") { $plannedCount++ } else { $unplannedCount++ }
        [void]$classifications.Add([ordered]@{ path = $file; classification = $classification })
    }

    $scopeButUnmatched = [System.Collections.ArrayList]::new()
    $changedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $changedFiles) { [void]$changedSet.Add($file) }
    foreach ($glob in $scopeGlobs) {
        $matched = $false
        foreach ($file in $changedSet) {
            if (Test-PathMatchesScope $file @($glob)) { $matched = $true; break }
        }
        if (-not $matched) { [void]$scopeButUnmatched.Add($glob) }
    }

    $verdict = if ($unplannedCount -gt 0) { "DRIFT_DETECTED" } else { "CLEAN" }

    $result = [ordered]@{
        schema_version = "2.0.0"
        plan_path = $relativePlanPath
        task_slug = $taskSlug
        base_commit = $baseSha
        head_commit = $headSha
        changed_file_count = $changedFiles.Count
        summary = [ordered]@{
            planned = $plannedCount
            unplanned = $unplannedCount
            scope_but_unmatched = $scopeButUnmatched.Count
        }
        classifications = @($classifications)
        scope_but_unmatched = @($scopeButUnmatched)
        verdict = $verdict
    }

    $result | ConvertTo-Json -Depth 5 -Compress
} catch {
    New-EmptyResult $PlanPath $_.Exception.Message
    exit 1
}
