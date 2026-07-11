param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath
)

$ErrorActionPreference = "Stop"

$RequiredRiskCategories = @(
    "data_volume",
    "performance",
    "concurrency",
    "access_control",
    "migration_rollback",
    "dependency",
    "operability"
)

function Add-Issue([System.Collections.ArrayList]$Issues, [string]$Message) {
    [void]$Issues.Add($Message)
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

function Get-StringArray([object]$Value) {
    if ($null -eq $Value -or $Value -is [string] -or -not ($Value -is [System.Array])) {
        return @()
    }

    return @($Value | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-Percentage([int]$Numerator, [int]$Denominator) {
    if ($Denominator -le 0) {
        return 0
    }

    return [int][Math]::Round((100.0 * $Numerator) / $Denominator, 0, [MidpointRounding]::AwayFromZero)
}

function Test-DependencyCycle([hashtable]$DependencyMap) {
    $states = @{}

    function Visit-Dependency([string]$Node) {
        if ($states[$Node] -eq "visiting") {
            return $true
        }
        if ($states[$Node] -eq "visited") {
            return $false
        }

        $states[$Node] = "visiting"
        foreach ($dependency in @($DependencyMap[$Node] | Where-Object { $null -ne $_ })) {
            if (Visit-Dependency $dependency) {
                return $true
            }
        }
        $states[$Node] = "visited"
        return $false
    }

    foreach ($node in $DependencyMap.Keys) {
        if (Visit-Dependency $node) {
            return $true
        }
    }

    return $false
}

function Get-MarkdownCompleteness([string]$Content, [System.Collections.ArrayList]$Issues) {
    $requirements = @(
        @{ Label = "plan title"; Pattern = "(?m)^# Plan:\s+.+$" },
        @{ Label = "status"; Pattern = "(?m)^\*\*Status:\*\*\s*.+$" },
        @{ Label = "agent"; Pattern = "(?m)^\*\*Agent:\*\*\s*.+$" },
        @{ Label = "schema version"; Pattern = "(?m)^\*\*Schema Version:\*\*\s*.+$" },
        @{ Label = "complexity tier"; Pattern = "(?m)^\*\*Complexity Tier:\*\*\s*.+$" },
        @{ Label = "confidence"; Pattern = "(?m)^\*\*Confidence:\*\*\s*.+$" },
        @{ Label = "context heading"; Pattern = "(?m)^## Context & Analysis\s*$" },
        @{ Label = "goal statement"; Pattern = "(?m)^Goal Statement:\s*\S.+$" },
        @{ Label = "design decisions heading"; Pattern = "(?m)^## Design Decisions\s*$" },
        @{ Label = "implementation phases heading"; Pattern = "(?m)^## Implementation Phases\s*$" },
        @{ Label = "phase heading"; Pattern = "(?m)^### Phase\s+.+$" },
        @{ Label = "inter-phase contracts heading"; Pattern = "(?m)^## Inter-Phase Contracts\s*$" },
        @{ Label = "open questions heading"; Pattern = "(?m)^## Open Questions\s*$" },
        @{ Label = "risks heading"; Pattern = "(?m)^## Risks\s*$" },
        @{ Label = "semantic risk review heading"; Pattern = "(?m)^## Semantic Risk Review\s*$" },
        @{ Label = "success criteria"; Pattern = "(?ms)^## Success Criteria\s*$\s*(?:[-*]\s+\S.+?)(?=^##\s|\z)" },
        @{ Label = "handoff heading"; Pattern = "(?m)^## Handoff\s*$" },
        @{ Label = "execution notes"; Pattern = "(?m)^## Notes for (?:Execution|Orchestration)\s*$" },
        @{ Label = "progress heading"; Pattern = "(?m)^## Progress\s*$" },
        @{ Label = "discoveries heading"; Pattern = "(?m)^## Discoveries\s*$" },
        @{ Label = "decision log heading"; Pattern = "(?m)^## Decision Log\s*$" },
        @{ Label = "outcomes heading"; Pattern = "(?m)^## Outcomes\s*$" },
        @{ Label = "idempotence heading"; Pattern = "(?m)^## Idempotence & Recovery\s*$" }
    )

    $satisfied = 0
    foreach ($requirement in $requirements) {
        if ([regex]::IsMatch($Content, $requirement.Pattern)) {
            $satisfied++
        } else {
            Add-Issue $Issues "Plan Markdown is missing $($requirement.Label)."
        }
    }

    return Get-Percentage $satisfied $requirements.Count
}

function Get-VerdictReadiness([string]$VerdictPath, [System.Collections.ArrayList]$Issues) {
    if (-not (Test-Path -LiteralPath $VerdictPath -PathType Leaf)) {
        Add-Issue $Issues "Verify verdict is missing: $VerdictPath"
        return 0
    }

    $content = Get-Content -LiteralPath $VerdictPath -Raw
    $requirements = @(
        @{ Label = "verdict title"; Pattern = "(?m)^# ControlFlow Verify Verdict\s*$" },
        @{ Label = "approved verdict status"; Pattern = "(?mi)^\*\*Status:\*\*\s*[\x60]?APPROVED[\x60]?\s*$" },
        @{ Label = "findings"; Pattern = "(?m)^## Findings\s*$" },
        @{ Label = "score breakdown"; Pattern = "(?m)^## Score Breakdown\s*$" },
        @{ Label = "evidence"; Pattern = "(?m)^## Evidence\s*$" },
        @{ Label = "recommendation"; Pattern = "(?m)^## Recommendation\s*$" }
    )

    foreach ($requirement in $requirements) {
        if (-not [regex]::IsMatch($content, $requirement.Pattern)) {
            Add-Issue $Issues "Verify verdict is missing $($requirement.Label)."
            return 0
        }
    }

    return 100
}

try {
    $repoRootResolved = (Resolve-Path -LiteralPath $RepoRoot).Path
    $planResolved = if ([System.IO.Path]::IsPathRooted($PlanPath)) {
        [System.IO.Path]::GetFullPath($PlanPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repoRootResolved $PlanPath))
    }

    if (-not (Test-Path -LiteralPath $planResolved -PathType Leaf)) {
        throw "Plan file is missing: $planResolved"
    }

    $relativePlanPath = $planResolved.Substring($repoRootResolved.Length).TrimStart([char]'\', [char]'/').Replace('\', '/')
    $planLeaf = Split-Path $planResolved -Leaf
    if ($planLeaf -notmatch '^(?<slug>.+)-plan\.md$') {
        throw "Plan filename must end with '-plan.md': $planLeaf"
    }
    $taskSlug = $Matches['slug']
    $metadataPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/plan.meta.json"
    $verdictPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/verify-verdict.md"
    $issues = New-Object System.Collections.ArrayList
    $planContent = Get-Content -LiteralPath $planResolved -Raw

    $completeness = Get-MarkdownCompleteness $planContent $issues
    $executability = 0
    $criteriaCoverage = 0
    $dependencySanity = 0
    $riskCoverage = 0
    $metadata = $null

    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        Add-Issue $issues "Plan metadata is missing: $metadataPath"
    } else {
        try {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        } catch {
            Add-Issue $issues "Plan metadata is not valid JSON: $metadataPath"
        }
    }

    if ($null -ne $metadata) {
        $phases = @((Get-PropertyValue $metadata "phases") | Where-Object { $null -ne $_ })
        if ($phases.Count -eq 0) {
            Add-Issue $issues "Plan metadata has no phases."
        } else {
            $declaredFiles = 0
            $existingFiles = 0
            $phasesWithCommands = 0
            $coveredPhaseCriteria = 0
            $phaseIds = @()
            $dependencyMap = @{}
            $dependencyFailure = $false

            foreach ($phase in $phases) {
                $phaseId = Get-PropertyValue $phase "id"
                if ($phaseId -is [string] -and -not [string]::IsNullOrWhiteSpace($phaseId)) {
                    if ($phaseIds -contains $phaseId) {
                        Add-Issue $issues "Plan metadata repeats phase id '$phaseId'."
                        $dependencyFailure = $true
                    } else {
                        $phaseIds += $phaseId
                    }
                } else {
                    Add-Issue $issues "Plan metadata has a phase without a non-empty id."
                    $dependencyFailure = $true
                }

                $phaseFiles = Get-StringArray (Get-PropertyValue $phase "files")
                $declaredFiles += $phaseFiles.Count
                foreach ($file in $phaseFiles) {
                    $filePath = [System.IO.Path]::GetFullPath((Join-Path $repoRootResolved $file))
                    if (Test-Path -LiteralPath $filePath -PathType Leaf) {
                        $existingFiles++
                    } else {
                        Add-Issue $issues "Declared phase file is missing: $file"
                    }
                }

                $phaseCommands = Get-StringArray (Get-PropertyValue $phase "commands")
                if ($phaseCommands.Count -gt 0) {
                    $phasesWithCommands++
                }

                $phaseCriteria = Get-StringArray (Get-PropertyValue $phase "success_criteria")
                if ($phaseCriteria.Count -gt 0) {
                    $coveredPhaseCriteria++
                } else {
                    Add-Issue $issues "Phase '$phaseId' has no success criteria."
                }

                if ($phaseId -is [string] -and -not [string]::IsNullOrWhiteSpace($phaseId)) {
                    $dependencies = Get-PropertyValue $phase "dependencies"
                    if ($null -eq $dependencies -or $dependencies -is [string] -or -not ($dependencies -is [System.Array])) {
                        Add-Issue $issues "Phase '$phaseId' dependencies must be an array of non-empty strings."
                        $dependencyFailure = $true
                        $dependencyMap[$phaseId] = @()
                    } else {
                        $dependencyValues = @()
                        foreach ($dependency in $dependencies) {
                            if (-not ($dependency -is [string]) -or [string]::IsNullOrWhiteSpace($dependency)) {
                                Add-Issue $issues "Phase '$phaseId' has an invalid dependency."
                                $dependencyFailure = $true
                            } else {
                                $dependencyValues += $dependency
                            }
                        }
                        $dependencyMap[$phaseId] = $dependencyValues
                    }
                }
            }

            $fileCoverage = Get-Percentage $existingFiles $declaredFiles
            $commandCoverage = Get-Percentage $phasesWithCommands $phases.Count
            $executability = [int][Math]::Round(($fileCoverage + $commandCoverage) / 2.0, 0, [MidpointRounding]::AwayFromZero)

            $topLevelCriteria = Get-StringArray (Get-PropertyValue $metadata "success_criteria")
            if ($topLevelCriteria.Count -eq 0) {
                Add-Issue $issues "Plan metadata has no top-level success criteria."
            }
            $criteriaNumerator = $coveredPhaseCriteria
            $criteriaDenominator = $phases.Count
            if ($topLevelCriteria.Count -gt 0) {
                $criteriaNumerator++
            }
            $criteriaDenominator++
            $criteriaCoverage = Get-Percentage $criteriaNumerator $criteriaDenominator

            foreach ($phaseId in $dependencyMap.Keys) {
                foreach ($dependency in @($dependencyMap[$phaseId] | Where-Object { $null -ne $_ })) {
                    if ($dependency -eq $phaseId) {
                        Add-Issue $issues "Phase '$phaseId' depends on itself."
                        $dependencyFailure = $true
                    } elseif ($phaseIds -notcontains $dependency) {
                        Add-Issue $issues "Phase '$phaseId' depends on unknown phase '$dependency'."
                        $dependencyFailure = $true
                    }
                }
            }
            if (-not $dependencyFailure -and (Test-DependencyCycle $dependencyMap)) {
                Add-Issue $issues "Plan metadata phase dependencies contain a cycle."
                $dependencyFailure = $true
            }
            if (-not $dependencyFailure) {
                $dependencySanity = 100
            }

            $riskCounts = @{}
            foreach ($category in $RequiredRiskCategories) {
                $riskCounts[$category] = 0
            }
            $riskContractFailure = $false
            $semanticRisks = Get-PropertyValue $metadata "semantic_risks"
            if ($null -eq $semanticRisks -or $semanticRisks -is [string] -or -not ($semanticRisks -is [System.Array])) {
                Add-Issue $issues "Plan metadata semantic_risks must be an array."
                $riskContractFailure = $true
            } else {
                foreach ($risk in $semanticRisks) {
                    $category = Get-PropertyValue $risk "category"
                    if (-not ($category -is [string]) -or [string]::IsNullOrWhiteSpace($category)) {
                        Add-Issue $issues "Semantic risk is missing a non-empty category."
                        $riskContractFailure = $true
                    } elseif (-not $riskCounts.ContainsKey($category)) {
                        Add-Issue $issues "Semantic risk category '$category' is unsupported."
                        $riskContractFailure = $true
                    } else {
                        $riskCounts[$category]++
                    }

                    $applicability = Get-PropertyValue $risk "applicability"
                    if ($applicability -notin @("applicable", "not_applicable")) {
                        Add-Issue $issues "Semantic risk '$category' has unsupported applicability '$applicability'."
                        $riskContractFailure = $true
                    }

                    $impact = Get-PropertyValue $risk "impact"
                    if ($impact -notin @("LOW", "MEDIUM", "HIGH")) {
                        Add-Issue $issues "Semantic risk '$category' has unsupported impact '$impact'."
                        $riskContractFailure = $true
                    }
                }
            }
            $coveredRiskCategories = 0
            foreach ($category in $RequiredRiskCategories) {
                if ($riskCounts[$category] -eq 1) {
                    $coveredRiskCategories++
                } else {
                    Add-Issue $issues "Semantic risk category '$category' must appear exactly once."
                    $riskContractFailure = $true
                }
            }
            if (-not $riskContractFailure) {
                $riskCoverage = Get-Percentage $coveredRiskCategories $RequiredRiskCategories.Count
            }
        }
    }

    $evidenceReadiness = Get-VerdictReadiness $verdictPath $issues
    $aggregateScore = [int][Math]::Round((
        $completeness + $executability + $criteriaCoverage + $dependencySanity + $riskCoverage + $evidenceReadiness
    ) / 6.0, 0, [MidpointRounding]::AwayFromZero)
    $metricValues = @($completeness, $executability, $criteriaCoverage, $dependencySanity, $riskCoverage, $evidenceReadiness)
    if (@($metricValues | Where-Object { $_ -lt 80 }).Count -eq 0) {
        $verdict = "APPROVED"
    } elseif ($aggregateScore -ge 50) {
        $verdict = "NEEDS_REVISION"
    } else {
        $verdict = "REJECTED"
    }

    $result = [ordered]@{
        schema_version = "1.0.0"
        plan_path = $relativePlanPath
        task_slug = $taskSlug
        aggregate_score = $aggregateScore
        verdict = $verdict
        metrics = [ordered]@{
            completeness = $completeness
            executability = $executability
            criteria_coverage = $criteriaCoverage
            dependency_sanity = $dependencySanity
            risk_coverage = $riskCoverage
            evidence_readiness = $evidenceReadiness
        }
        issues = @($issues)
    }

    $result | ConvertTo-Json -Depth 6 -Compress
} catch {
    $failure = [ordered]@{
        schema_version = "1.0.0"
        plan_path = $PlanPath.Replace('\', '/')
        task_slug = $null
        aggregate_score = 0
        verdict = "REJECTED"
        metrics = [ordered]@{
            completeness = 0
            executability = 0
            criteria_coverage = 0
            dependency_sanity = 0
            risk_coverage = 0
            evidence_readiness = 0
        }
        issues = @($_.Exception.Message)
    }
    $failure | ConvertTo-Json -Depth 6 -Compress
    exit 1
}
