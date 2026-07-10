param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [switch]$RequireVerifyVerdict,

    [switch]$RequirePlanMetadata
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

function Get-JsonProperty([object]$Object, [string]$Name, [string]$Label) {
    if ($null -eq $Object) {
        throw "Metadata $Label is missing"
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Metadata $Label is missing required property '$Name'"
    }

    if ($property.Value -is [System.Array]) {
        Write-Output -NoEnumerate $property.Value
        return
    }

    return $property.Value
}

function Assert-NonEmptyString([object]$Value, [string]$Label) {
    if (-not ($Value -is [string]) -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "Metadata $Label must be a non-empty string"
    }

    return $Value.Trim()
}

function Assert-NonEmptyStringArray([object]$Value, [string]$Label) {
    if ($null -eq $Value -or $Value -is [string] -or -not ($Value -is [System.Array]) -or $Value.Count -eq 0) {
        throw "Metadata $Label must be a non-empty array"
    }

    foreach ($item in $Value) {
        [void](Assert-NonEmptyString $item "$Label item")
    }
}

function Assert-PlanMetadata(
    [string]$Content,
    [string]$MetadataPath,
    [string]$ExpectedPlanPath
) {
    try {
        $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
    } catch {
        throw "Metadata file is not valid JSON '$MetadataPath': $($_.Exception.Message)"
    }

    $schemaVersion = Assert-NonEmptyString (Get-JsonProperty $metadata "schema_version" "document") "schema_version"
    if ($schemaVersion -cne "1.0.0") {
        throw "Metadata schema_version must be '1.0.0': $MetadataPath"
    }

    $metadataPlanPath = Assert-NonEmptyString (Get-JsonProperty $metadata "plan_path" "document") "plan_path"
    $normalizedPlanPath = $metadataPlanPath.Replace('\', '/')
    if ($normalizedPlanPath -cne $ExpectedPlanPath) {
        throw "Metadata plan_path '$metadataPlanPath' must match '$ExpectedPlanPath'"
    }

    $metadataGoal = Assert-NonEmptyString (Get-JsonProperty $metadata "goal" "document") "goal"
    $goalMatch = [regex]::Match($Content, '(?mi)^Goal Statement:\s*(?<goal>.+?)\s*$')
    if (-not $goalMatch.Success) {
        throw "Plan must contain a Goal Statement before metadata can be required"
    }
    $planGoal = $goalMatch.Groups["goal"].Value.Trim()
    if ($metadataGoal -cne $planGoal) {
        throw "Metadata goal must match the Markdown Goal Statement"
    }

    $metadataTier = Assert-NonEmptyString (Get-JsonProperty $metadata "complexity_tier" "document") "complexity_tier"
    if ($metadataTier -notin @("TRIVIAL", "SMALL", "MEDIUM", "LARGE")) {
        throw "Metadata complexity_tier must be TRIVIAL, SMALL, MEDIUM, or LARGE"
    }
    $tierMatch = [regex]::Match($Content, '(?mi)^\*\*Complexity Tier:\*\*\s*(?<tier>TRIVIAL|SMALL|MEDIUM|LARGE)\s*$')
    if (-not $tierMatch.Success) {
        throw "Plan must contain a supported Complexity Tier before metadata can be required"
    }
    if ($metadataTier -cne $tierMatch.Groups["tier"].Value) {
        throw "Metadata complexity_tier must match the Markdown Complexity Tier"
    }

    $phases = Get-JsonProperty $metadata "phases" "document"
    if ($null -eq $phases -or $phases -is [string] -or -not ($phases -is [System.Array]) -or $phases.Count -eq 0) {
        throw "Metadata phases must be a non-empty array"
    }

    $phaseIds = @()
    foreach ($phase in $phases) {
        $phaseId = Assert-NonEmptyString (Get-JsonProperty $phase "id" "phase") "phase id"
        if ($phaseIds -contains $phaseId) {
            throw "Metadata phases must use unique ids: '$phaseId'"
        }
        $phaseIds += $phaseId

        [void](Assert-NonEmptyString (Get-JsonProperty $phase "objective" "phase '$phaseId'") "phase '$phaseId' objective")
        Assert-NonEmptyStringArray (Get-JsonProperty $phase "files" "phase '$phaseId'") "phase '$phaseId' files"
        Assert-NonEmptyStringArray (Get-JsonProperty $phase "commands" "phase '$phaseId'") "phase '$phaseId' commands"
        Assert-NonEmptyStringArray (Get-JsonProperty $phase "success_criteria" "phase '$phaseId'") "phase '$phaseId' success_criteria"

        $phaseHeading = "(?m)^### Phase " + [regex]::Escape($phaseId) + "(?:\s|$)"
        if ($Content -notmatch $phaseHeading) {
            throw "Metadata phase '$phaseId' must match a Markdown phase heading"
        }
    }

    foreach ($phase in $phases) {
        $phaseId = Assert-NonEmptyString (Get-JsonProperty $phase "id" "phase") "phase id"
        $dependencies = Get-JsonProperty $phase "dependencies" "phase '$phaseId'"
        if ($null -eq $dependencies -or $dependencies -is [string] -or -not ($dependencies -is [System.Array])) {
            throw "Metadata phase '$phaseId' dependencies must be an array"
        }

        foreach ($dependency in $dependencies) {
            $dependencyId = Assert-NonEmptyString $dependency "phase '$phaseId' dependency"
            if ($dependencyId -eq $phaseId) {
                throw "Metadata phase '$phaseId' cannot depend on itself"
            }
            if ($phaseIds -notcontains $dependencyId) {
                throw "Metadata phase '$phaseId' depends on unknown phase '$dependencyId'"
            }
        }
    }

    $semanticRisks = Get-JsonProperty $metadata "semantic_risks" "document"
    if ($null -eq $semanticRisks -or $semanticRisks -is [string] -or -not ($semanticRisks -is [System.Array])) {
        throw "Metadata semantic_risks must be an array"
    }

    $requiredRiskCategories = @(
        "data_volume",
        "performance",
        "concurrency",
        "access_control",
        "migration_rollback",
        "dependency",
        "operability"
    )
    $riskCounts = @{}
    foreach ($category in $requiredRiskCategories) {
        $riskCounts[$category] = 0
    }

    foreach ($risk in $semanticRisks) {
        $category = Assert-NonEmptyString (Get-JsonProperty $risk "category" "semantic risk") "semantic risk category"
        if (-not $riskCounts.ContainsKey($category)) {
            throw "Metadata semantic risk category is unsupported: '$category'"
        }
        $riskCounts[$category]++

        $applicability = Assert-NonEmptyString (Get-JsonProperty $risk "applicability" "semantic risk '$category'") "semantic risk '$category' applicability"
        if ($applicability -notin @("applicable", "not_applicable")) {
            throw "Metadata semantic risk '$category' has unsupported applicability '$applicability'"
        }

        $impact = Assert-NonEmptyString (Get-JsonProperty $risk "impact" "semantic risk '$category'") "semantic risk '$category' impact"
        if ($impact -notin @("LOW", "MEDIUM", "HIGH")) {
            throw "Metadata semantic risk '$category' has unsupported impact '$impact'"
        }
    }

    $missingRiskCategories = @($requiredRiskCategories | Where-Object { $riskCounts[$_] -ne 1 })
    if ($missingRiskCategories.Count -gt 0) {
        throw "Metadata semantic_risks must contain every category exactly once: $($missingRiskCategories -join ', ')"
    }

    Assert-NonEmptyStringArray (Get-JsonProperty $metadata "success_criteria" "document") "success_criteria"
}

function Assert-VerdictScoreBreakdown([string]$Content) {
    foreach ($dimension in @(
        "completeness",
        "executability",
        "dependency sanity",
        "evidence readiness",
        "risk handling"
    )) {
        $pattern = "(?mi)^\s*\|\s*" + [regex]::Escape($dimension) + "\s*\|\s*(?<score>\d{1,3}\s*/\s*100|LOW|MEDIUM|HIGH|(?:0(?:\.\d+)?|1(?:\.0+)?))\s*\|"
        $match = [regex]::Match($Content, $pattern)
        if (-not $match.Success) {
            throw "Verify verdict score dimension '$dimension' must include a 0-100 score or confidence band"
        }

        $score = $match.Groups["score"].Value
        if ($score -match '^\d{1,3}\s*/\s*100$') {
            $numericScore = [int]([regex]::Match($score, '^\d+').Value)
            if ($numericScore -gt 100) {
                throw "Verify verdict score dimension '$dimension' cannot exceed 100"
            }
        }
    }
}

function Assert-VerdictSectionHasContent([string]$Content, [string]$Heading, [string]$Label) {
    $pattern = "(?ms)^" + [regex]::Escape($Heading) + "\s*$\s*(?<body>.*?)(?=^##\s|\z)"
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success -or [string]::IsNullOrWhiteSpace($match.Groups["body"].Value)) {
        throw "Verify verdict $Label must contain revision guidance"
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

if ($RequirePlanMetadata) {
    $relativePlanPath = $planResolved.Substring($repoRootResolved.Length).TrimStart([char]'\', [char]'/').Replace('\', '/')
    $metadataPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/plan.meta.json"
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Missing plan metadata: $metadataPath"
    }

    Assert-PlanMetadata $planContent $metadataPath $relativePlanPath
    Write-Output "VALID plan metadata: $metadataPath"
}

if ($RequireVerifyVerdict) {
    $verdictPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/verify-verdict.md"
    $verdictContent = Read-Text $verdictPath
    Assert-Contains $verdictContent "# ControlFlow Verify Verdict" "verify verdict title"
    Assert-Contains $verdictContent "**Status:**" "verify verdict status"
    Assert-Contains $verdictContent "## Findings" "verify verdict findings"
    Assert-Contains $verdictContent "## Score Breakdown" "verify verdict score breakdown"
    Assert-Contains $verdictContent "## Revision Patch Instructions" "verify verdict revision instructions"
    Assert-Contains $verdictContent "## Evidence" "verify verdict evidence"
    Assert-Contains $verdictContent "## Recommendation" "verify verdict recommendation"

    Assert-VerdictScoreBreakdown $verdictContent
    Assert-VerdictSectionHasContent $verdictContent "## Revision Patch Instructions" "revision patch instructions"

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
