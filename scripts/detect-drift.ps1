param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [string]$BaseCommit,

    [string]$HeadCommit
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

function Get-PropertyValue([object]$Object, [string]$Name) {
    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    if ($property.Value -is [System.Array]) {
        Write-Output -NoEnumerate $property.Value
        return
    }
    return $property.Value
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
        return , $cleaned
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

    $metadataPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/plan.meta.json"
    $metadata = Read-JsonFile $metadataPath
    if ($null -eq $metadata) {
        throw "Missing plan metadata: $metadataPath"
    }

    $plannedFiles = [System.Collections.Generic.SortedSet[string]]::new()
    $phases = Get-PropertyValue $metadata "phases"
    if ($null -ne $phases -and $phases -is [System.Array]) {
        foreach ($phase in $phases) {
            $files = Get-PropertyValue $phase "files"
            if ($null -ne $files -and $files -is [System.Array]) {
                foreach ($file in $files) {
                    if ($file -is [string] -and -not [string]::IsNullOrWhiteSpace($file)) {
                        [void]$plannedFiles.Add($file.Trim().Replace('\', '/'))
                    }
                }
            }
        }
    }
    $plannedFilesArray = @($plannedFiles | Sort-Object)

    $snapshotPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/context-snapshot.json"
    $snapshot = Read-JsonFile $snapshotPath

    $resolvedBase = $BaseCommit
    if ([string]::IsNullOrWhiteSpace($resolvedBase)) {
        if ($null -ne $snapshot) {
            $snapGit = Get-PropertyValue $snapshot "git"
            if ($null -ne $snapGit) {
                $snapCommit = Get-PropertyValue $snapGit "head_commit"
                if ($snapCommit -is [string] -and -not [string]::IsNullOrWhiteSpace($snapCommit)) {
                    $resolvedBase = $snapCommit
                }
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($resolvedBase)) {
        $resolvedBase = "HEAD~1"
    }

    $resolvedHead = $HeadCommit
    if ([string]::IsNullOrWhiteSpace($resolvedHead)) {
        $headRaw = Invoke-GitSafe $repoRootResolved @("rev-parse", "HEAD")
        $resolvedHead = if ($null -ne $headRaw) { $headRaw.Trim() } else { "HEAD" }
    }

    $baseResolved = Invoke-GitSafe $repoRootResolved @("rev-parse", $resolvedBase)
    $baseSha = if ($null -ne $baseResolved) { $baseResolved.Trim() } else { $resolvedBase }

    $headResolved = Invoke-GitSafe $repoRootResolved @("rev-parse", $resolvedHead)
    $headSha = if ($null -ne $headResolved) { $headResolved.Trim() } else { $resolvedHead }

    $changedFiles = Invoke-GitListSafe $repoRootResolved @("diff", "--name-only", "$baseSha", $headSha)
    if ($null -eq $changedFiles) {
        $changedFiles = @()
    }
    $changedFiles = @($changedFiles | ForEach-Object { $_.Replace('\', '/') } | Sort-Object)

    $classifications = [System.Collections.ArrayList]::new()
    $approvedCount = 0
    $justifiedCount = 0
    $blockingCount = 0

    $plannedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $plannedFilesArray) {
        [void]$plannedSet.Add($file)
    }

    foreach ($file in $changedFiles) {
        $classification = "blocking_scope_drift"
        if ($plannedSet.Contains($file)) {
            $classification = "approved_follow_through"
            $approvedCount++
        } else {
            $blockingCount++
        }
        [void]$classifications.Add([ordered]@{
            path = $file
            classification = $classification
        })
    }

    $plannedButUnchanged = [System.Collections.ArrayList]::new()
    $changedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $changedFiles) {
        [void]$changedSet.Add($file)
    }
    foreach ($file in $plannedFilesArray) {
        if (-not $changedSet.Contains($file)) {
            [void]$plannedButUnchanged.Add($file)
        }
    }

    $verdict = "CLEAN"
    if ($blockingCount -gt 0) {
        $verdict = "DRIFT_DETECTED"
    }

    $result = [ordered]@{
        schema_version = "1.0.0"
        plan_path = $relativePlanPath
        task_slug = $taskSlug
        base_commit = $baseSha
        head_commit = $headSha
        changed_file_count = $changedFiles.Count
        planned_file_count = $plannedFilesArray.Count
        summary = [ordered]@{
            approved_follow_through = $approvedCount
            justified_deviation = $justifiedCount
            blocking_scope_drift = $blockingCount
            planned_but_unchanged = $plannedButUnchanged.Count
        }
        classifications = @($classifications)
        planned_but_unchanged = @($plannedButUnchanged)
        verdict = $verdict
    }

    $result | ConvertTo-Json -Depth 5 -Compress
} catch {
    $failure = [ordered]@{
        schema_version = "1.0.0"
        plan_path = $PlanPath.Replace('\', '/')
        task_slug = $null
        base_commit = $null
        head_commit = $null
        changed_file_count = 0
        planned_file_count = 0
        summary = [ordered]@{
            approved_follow_through = 0
            justified_deviation = 0
            blocking_scope_drift = 0
            planned_but_unchanged = 0
        }
        classifications = @()
        planned_but_unchanged = @()
        verdict = "ERROR"
        error = $_.Exception.Message
    }
    $failure | ConvertTo-Json -Depth 5 -Compress
    exit 1
}
