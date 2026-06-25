param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [switch]$RequireVerifyVerdict
)

$ErrorActionPreference = "Stop"

function Read-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing file: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw
}

function Assert-Contains([string]$Content, [string]$Needle, [string]$Label) {
    if ($Content -notmatch [regex]::Escape($Needle)) {
        throw "Missing required section '$Label'"
    }
}

function Assert-OrderedHeadings([string]$Content, [string[]]$Headings, [string]$Label) {
    $lastIndex = -1
    foreach ($heading in $Headings) {
        $match = [regex]::Match($Content, "(?m)^" + [regex]::Escape($heading) + "\s*$")
        if (-not $match.Success) {
            throw "Missing required $Label heading '$heading'"
        }
        if ($match.Index -le $lastIndex) {
            throw "$Label headings are out of order at '$heading'"
        }
        $lastIndex = $match.Index
    }
}

function Assert-SemanticRiskRows([string]$Content) {
    $required = @(
        "data_volume",
        "performance",
        "concurrency",
        "access_control",
        "migration_rollback",
        "dependency",
        "operability"
    )
    $counts = @{}
    foreach ($category in $required) {
        $counts[$category] = 0
    }

    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -notmatch '^\s*\|') {
            continue
        }
        $columns = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`') })
        if ($columns.Count -lt 5) {
            continue
        }
        $category = $columns[0].ToLowerInvariant()
        if ($counts.ContainsKey($category)) {
            $counts[$category]++
        }
    }

    $errors = @()
    foreach ($category in $required) {
        if ($counts[$category] -ne 1) {
            $errors += "$category=$($counts[$category])"
        }
    }
    if ($errors.Count -gt 0) {
        throw "Semantic Risk Review must contain every category exactly once: $($errors -join ', ')"
    }
}

$repoRootResolved = (Resolve-Path $RepoRoot).Path
$planResolved = if ([System.IO.Path]::IsPathRooted($PlanPath)) {
    [System.IO.Path]::GetFullPath($PlanPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRootResolved $PlanPath))
}
$planContent = Read-Text $planResolved

$requiredSections = @(
    "# Plan:",
    "**Status:**",
    "**Agent:**",
    "**Schema Version:**",
    "**Complexity Tier:**",
    "**Confidence:**",
    "## Context & Analysis",
    "## Design Decisions",
    "## Implementation Phases",
    "## Inter-Phase Contracts",
    "## Open Questions",
    "## Risks",
    "## Semantic Risk Review",
    "## Success Criteria",
    "## Handoff"
)
foreach ($section in $requiredSections) {
    Assert-Contains $planContent $section $section
}

if (($planContent -notmatch '(?m)^## Notes for Execution\s*$') -and
    ($planContent -notmatch '(?m)^## Notes for Orchestration\s*$')) {
    throw "Missing required execution-notes section"
}

Assert-OrderedHeadings $planContent @(
    "## Progress",
    "## Discoveries",
    "## Decision Log",
    "## Outcomes",
    "## Idempotence & Recovery"
) "lifecycle"

Assert-SemanticRiskRows $planContent

$planLeaf = Split-Path $planResolved -Leaf
if ($planLeaf -notmatch '^(?<slug>.+)-plan\.md$') {
    throw "Plan filename must end with '-plan.md': $planLeaf"
}
$taskSlug = $Matches['slug']

if ($RequireVerifyVerdict) {
    $verdictPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/verify-verdict.md"
    $verdictContent = Read-Text $verdictPath
    Assert-Contains $verdictContent "# ControlFlow Verify Verdict" "verify verdict title"
    Assert-Contains $verdictContent "**Status:**" "verify verdict status"
    Assert-Contains $verdictContent "## Findings" "verify verdict findings"
    Assert-Contains $verdictContent "## Evidence" "verify verdict evidence"
    Assert-Contains $verdictContent "## Recommendation" "verify verdict recommendation"

    $statusMatch = [regex]::Match(
        $verdictContent,
        '(?mi)^\*\*Status:\*\*\s*`?(APPROVED|NEEDS_REVISION|REJECTED)`?\s*$'
    )
    if (-not $statusMatch.Success) {
        throw "Verify verdict status must be APPROVED, NEEDS_REVISION, or REJECTED"
    }
    if (($statusMatch.Groups[1].Value -ne "APPROVED") -and
        ($verdictContent -notmatch '(?mi)^\*\*Failure Classification:\*\*')) {
        throw "Non-approved verify verdict requires Failure Classification"
    }

    Write-Output "VALID verify verdict: $verdictPath"
}

Write-Output "VALID plan: $planResolved"