param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$PlanPath
)

$ErrorActionPreference = "Stop"

function Get-JsonProperty([object]$Object, [string]$Name, [string]$Label) {
    if ($null -eq $Object) {
        throw "Revision request $Label is missing"
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Revision request $Label is missing required property '$Name'"
    }

    if ($property.Value -is [System.Array]) {
        Write-Output -NoEnumerate $property.Value
        return
    }

    return $property.Value
}

function Assert-NonEmptyString([object]$Value, [string]$Label) {
    if (-not ($Value -is [string]) -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "Revision request $Label must be a non-empty string"
    }

    return $Value
}

function Assert-ExactProperties([object]$Object, [string[]]$RequiredProperties, [string]$Label) {
    if ($null -eq $Object -or $Object -is [string] -or $Object -is [System.Array]) {
        throw "Revision request $Label must be an object"
    }

    $actualProperties = @($Object.PSObject.Properties.Name)
    foreach ($name in $RequiredProperties) {
        if ($actualProperties -notcontains $name) {
            throw "Revision request $Label is missing required property '$name'"
        }
    }

    foreach ($name in $actualProperties) {
        if ($RequiredProperties -notcontains $name) {
            throw "Revision request $Label has unsupported property '$name'"
        }
    }
}

$repoRootResolved = (Resolve-Path -LiteralPath $RepoRoot).Path
$planResolved = if ([IO.Path]::IsPathRooted($PlanPath)) {
    [IO.Path]::GetFullPath($PlanPath)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRootResolved $PlanPath))
}
$planLeaf = Split-Path $planResolved -Leaf
if ($planLeaf -notmatch '^(?<slug>.+)-plan\.md$') {
    throw "Plan filename must end with '-plan.md': $planLeaf"
}
$taskSlug = $Matches['slug']

$validatePlanPath = Join-Path $PSScriptRoot "validate-plan.ps1"
& $validatePlanPath -RepoRoot $repoRootResolved -PlanPath $planResolved -RequirePlanMetadata -RequireVerifyVerdict
if (($null -ne $LASTEXITCODE) -and ($LASTEXITCODE -ne 0)) {
    throw "Plan validation failed with exit code $LASTEXITCODE"
}

$verdictPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/verify-verdict.md"
$verdictContent = Get-Content -LiteralPath $verdictPath -Raw
$statusMatch = [regex]::Match(
    $verdictContent,
    '(?mi)^\*\*Status:\*\*\s*[\x60]?(APPROVED|NEEDS_REVISION|REJECTED)[\x60]?\s*$'
)
$classificationMatch = [regex]::Match(
    $verdictContent,
    '(?mi)^\*\*Failure Classification:\*\*\s*[\x60]?(fixable|needs_replan|escalate)[\x60]?\s*$'
)
if (-not $statusMatch.Success) {
    throw "Verify verdict status must be APPROVED, NEEDS_REVISION, or REJECTED"
}

$verdictStatus = $statusMatch.Groups[1].Value
$requestPath = Join-Path $repoRootResolved "plans/artifacts/$taskSlug/revision-request.json"
if ($verdictStatus -eq "APPROVED") {
if (Test-Path -LiteralPath $requestPath) {
        throw "Approved verify verdict must not have a revision request: $requestPath"
    }

    Write-Output "VALID approved verdict without revision request: $verdictPath"
    return
}

if (-not $classificationMatch.Success) {
    throw "Non-approved verify verdict requires Failure Classification"
}
if (-not (Test-Path -LiteralPath $requestPath -PathType Leaf)) {
    throw "Non-approved verify verdict requires revision request: $requestPath"
}

try {
    $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
} catch {
    throw "Revision request is not valid JSON '$requestPath': $($_.Exception.Message)"
}

$requestProperties = @(
    "schema_version",
    "plan_path",
    "source_verdict_path",
    "source_verdict_status",
    "failure_classification",
    "next_action",
    "summary",
    "items"
)
$itemProperties = @("id", "location", "finding", "required_change", "acceptance_criteria")
Assert-ExactProperties $request $requestProperties "document"

$schemaVersion = Assert-NonEmptyString (Get-JsonProperty $request "schema_version" "document") "schema_version"
if ($schemaVersion -cne "1.0.0") {
    throw "Revision request schema_version must be '1.0.0'"
}

$expectedPlanPath = $planResolved.Substring($repoRootResolved.Length).
    TrimStart([char]'\', [char]'/').Replace('\', '/')
$expectedVerdictPath = "plans/artifacts/$taskSlug/verify-verdict.md"
$allowedActions = @{
    "NEEDS_REVISION/fixable" = "revise"
    "REJECTED/needs_replan" = "replan"
    "REJECTED/escalate" = "escalate"
}
$mappingKey = "$verdictStatus/$($classificationMatch.Groups[1].Value)"

$requestPlanPath = Assert-NonEmptyString (Get-JsonProperty $request "plan_path" "document") "plan_path"
if ($requestPlanPath -cne $expectedPlanPath) {
    throw "Revision request plan_path '$requestPlanPath' must match '$expectedPlanPath'"
}

$requestVerdictPath = Assert-NonEmptyString (Get-JsonProperty $request "source_verdict_path" "document") "source_verdict_path"
if ($requestVerdictPath -cne $expectedVerdictPath) {
    throw "Revision request source_verdict_path '$requestVerdictPath' must match '$expectedVerdictPath'"
}

$requestStatus = Assert-NonEmptyString (Get-JsonProperty $request "source_verdict_status" "document") "source_verdict_status"
if ($requestStatus -cne $verdictStatus) {
    throw "Revision request source_verdict_status '$requestStatus' must match '$verdictStatus'"
}

$failureClassification = Assert-NonEmptyString (Get-JsonProperty $request "failure_classification" "document") "failure_classification"
$verdictClassification = $classificationMatch.Groups[1].Value
if ($failureClassification -cne $verdictClassification) {
    throw "Revision request failure_classification '$failureClassification' must match '$verdictClassification'"
}

if (-not $allowedActions.ContainsKey($mappingKey)) {
    throw "Verify verdict status/classification is not actionable: '$mappingKey'"
}
$nextAction = Assert-NonEmptyString (Get-JsonProperty $request "next_action" "document") "next_action"
if ($nextAction -cne $allowedActions[$mappingKey]) {
    throw "Revision request next_action '$nextAction' must be '$($allowedActions[$mappingKey])'"
}

[void](Assert-NonEmptyString (Get-JsonProperty $request "summary" "document") "summary")
$items = Get-JsonProperty $request "items" "document"
if ($null -eq $items -or $items -is [string] -or -not ($items -is [System.Array]) -or $items.Count -eq 0) {
    throw "Revision request items must be a non-empty array"
}

$itemIds = @{}
foreach ($item in $items) {
    Assert-ExactProperties $item $itemProperties "item"
    $itemId = Assert-NonEmptyString (Get-JsonProperty $item "id" "item") "item id"
    if ($itemIds.ContainsKey($itemId)) {
        throw "Revision request items must use unique ids: '$itemId'"
    }
    $itemIds[$itemId] = $true

    foreach ($property in $itemProperties | Where-Object { $_ -ne "id" }) {
        [void](Assert-NonEmptyString (Get-JsonProperty $item $property "item '$itemId'") "item '$itemId' $property")
    }
}

Write-Output "VALID revision request: $requestPath"
