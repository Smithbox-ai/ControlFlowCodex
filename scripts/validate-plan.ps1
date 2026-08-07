param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath,

    [switch]$RequirePlanMetadata,

    [switch]$RequireVerifyVerdict
)

$ErrorActionPreference = "Stop"

function Assert-NonEmptyString([object]$Value, [string]$Label) {
    if (-not ($Value -is [string]) -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "Metadata $Label must be a non-empty string"
    }
    return $Value.Trim()
}

function Assert-StringArray([object]$Value, [string]$Label, [bool]$RequireNonEmpty) {
    if ($null -eq $Value -or $Value -is [string] -or -not ($Value -is [System.Array])) {
        throw "Metadata $Label must be an array"
    }
    if ($RequireNonEmpty -and $Value.Count -eq 0) {
        throw "Metadata $Label must be a non-empty array"
    }
    foreach ($item in $Value) {
        if (-not ($item -is [string]) -or [string]::IsNullOrWhiteSpace($item)) {
            throw "Metadata $Label must contain only non-empty strings"
        }
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

function Assert-PlanMetadata([string]$MetadataPath) {
    try {
        $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
    } catch {
        throw "Metadata file is not valid JSON '$MetadataPath': $($_.Exception.Message)"
    }

    $schemaVersion = Assert-NonEmptyString (Get-Property $metadata "schema_version") "schema_version"
    if ($schemaVersion -cne "2.0.0") {
        throw "Metadata schema_version must be '2.0.0': $MetadataPath (got '$schemaVersion')"
    }

    Assert-NonEmptyString (Get-Property $metadata "goal") "goal" | Out-Null

    $tier = Get-Property $metadata "tier"
    if ($tier -cnotin @("TRIVIAL", "SMALL", "MEDIUM", "LARGE")) {
        throw "Metadata tier must be TRIVIAL, SMALL, MEDIUM, or LARGE (got '$tier')"
    }

    $baseline = Get-Property $metadata "baseline"
    if ($null -eq $baseline -or -not ($baseline -is [pscustomobject])) {
        throw "Metadata baseline must be an object with commit and dirty_paths"
    }
    Assert-NonEmptyString (Get-Property $baseline "commit") "baseline.commit" | Out-Null
    Assert-StringArray (Get-Property $baseline "dirty_paths") "baseline.dirty_paths" $false

    Assert-StringArray (Get-Property $metadata "scope") "scope" $true
    Assert-StringArray (Get-Property $metadata "criteria") "criteria" $true
    Assert-StringArray (Get-Property $metadata "checks") "checks" $true

    $risks = Get-Property $metadata "risks"
    if ($null -ne $risks) {
        if (-not ($risks -is [pscustomobject])) {
            throw "Metadata risks must be an object keyed by risk category"
        }
        $allowedImpacts = @("LOW", "MEDIUM", "HIGH")
        foreach ($category in $risks.PSObject.Properties.Name) {
            $risk = $risks.PSObject.Properties[$category].Value
            if (-not ($risk -is [pscustomobject])) {
                throw "Metadata risks.$category must be an object with impact"
            }
            $impact = Get-Property $risk "impact"
            if ($impact -cnotin $allowedImpacts) {
                throw "Metadata risks.$category.impact must be LOW, MEDIUM, or HIGH (got '$impact')"
            }
            $mitigation = Get-Property $risk "mitigation"
            if ($null -ne $mitigation) {
                Assert-NonEmptyString $mitigation "risks.$category.mitigation" | Out-Null
            }
            $extraRiskProps = @($risk.PSObject.Properties.Name | Where-Object { $_ -notin @("impact", "mitigation") })
            if ($extraRiskProps.Count -gt 0) {
                throw "Metadata risks.$category has unknown properties: $($extraRiskProps -join ', ')"
            }
        }
    }

    $phases = Get-Property $metadata "phases"
    if ($null -ne $phases) {
        if (-not ($phases -is [System.Array])) {
            throw "Metadata phases must be an array"
        }
        $phaseIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($phase in $phases) {
            if (-not ($phase -is [pscustomobject])) {
                throw "Each phase must be an object"
            }
            $id = Assert-NonEmptyString (Get-Property $phase "id") "phase.id"
            if (-not $phaseIds.Add($id)) {
                throw "Duplicate phase id: $id"
            }
            Assert-NonEmptyString (Get-Property $phase "objective") "phase.objective" | Out-Null
            Assert-StringArray (Get-Property $phase "criteria") "phase.criteria" $true
            $dependsOn = Get-Property $phase "depends_on"
            if ($null -ne $dependsOn) { Assert-StringArray $dependsOn "phase.depends_on" $false }
            $phaseScope = Get-Property $phase "scope"
            if ($null -ne $phaseScope) { Assert-StringArray $phaseScope "phase.scope" $false }
            $phaseChecks = Get-Property $phase "checks"
            if ($null -ne $phaseChecks) { Assert-StringArray $phaseChecks "phase.checks" $false }
            $extraPhaseProps = @($phase.PSObject.Properties.Name | Where-Object { $_ -notin @("id", "objective", "criteria", "depends_on", "scope", "checks") })
            if ($extraPhaseProps.Count -gt 0) {
                throw "Phase '$id' has unknown properties: $($extraPhaseProps -join ', ')"
            }
        }
    }

    $extraProps = @($metadata.PSObject.Properties.Name | Where-Object {
        $_ -notin @("schema_version", "goal", "tier", "baseline", "scope", "criteria", "checks", "risks", "phases")
    })
    if ($extraProps.Count -gt 0) {
        throw "Metadata has unknown properties: $($extraProps -join ', ')"
    }
}

function Assert-VerifyVerdict([string]$VerdictPath) {
    if (-not (Test-Path -LiteralPath $VerdictPath -PathType Leaf)) {
        throw "Missing verify verdict: $VerdictPath"
    }
    $content = Get-Content -LiteralPath $VerdictPath -Raw

    $statusMatch = [regex]::Match($content, '(?mi)^\s*Status:\s*`?(APPROVED|NEEDS_REVISION|REPLAN)`?\s*$')
    if (-not $statusMatch.Success) {
        throw "Verify verdict status must be APPROVED, NEEDS_REVISION, or REPLAN"
    }
    if ($content -notmatch '(?mi)^\s*##\s*Findings\s*$') {
        throw "Verify verdict must include a ## Findings section"
    }

    Write-Output "VALID verify verdict: $VerdictPath"
}

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

if ($RequirePlanMetadata) {
    $metadataPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/plan.meta.json"
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Missing plan metadata: $metadataPath"
    }
    Assert-PlanMetadata $metadataPath
    Write-Output "VALID plan metadata: $metadataPath"
}

if ($RequireVerifyVerdict) {
    $verdictPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/verify-verdict.md"
    Assert-VerifyVerdict $verdictPath
}

Write-Output "VALID plan: $planResolved"
