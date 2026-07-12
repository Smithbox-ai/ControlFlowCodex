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

    $properties = @($Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
    if ($properties.Count -ne 1) {
        throw "Revision request $Label is missing required property '$Name'"
    }
    $property = $properties[0]

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
        if ($actualProperties -cnotcontains $name) {
            throw "Revision request $Label is missing required property '$name'"
        }
    }

    foreach ($name in $actualProperties) {
        if ($RequiredProperties -cnotcontains $name) {
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
$repoRootPrefix = $repoRootResolved.TrimEnd([char]'\', [char]'/') + [IO.Path]::DirectorySeparatorChar
if (-not $planResolved.StartsWith($repoRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Plan path must be inside RepoRoot: $planResolved"
}
$expectedPlanPath = $planResolved.Substring($repoRootResolved.Length).
    TrimStart([char]'\', [char]'/').Replace('\', '/')
if ($expectedPlanPath -cnotmatch '^plans/.+-plan\.md$') {
    throw "Plan path must match 'plans/<slug>-plan.md': $expectedPlanPath"
}

$validatePlanPath = Join-Path $PSScriptRoot "validate-plan.ps1"
$global:LASTEXITCODE = 0
& $validatePlanPath -RepoRoot $repoRootResolved -PlanPath $planResolved -RequirePlanMetadata -RequireVerifyVerdict
$validatePlanExitCode = $global:LASTEXITCODE
if (($null -ne $validatePlanExitCode) -and ($validatePlanExitCode -ne 0)) {
    throw "Plan validation failed with exit code $validatePlanExitCode"
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
    if (-not (Test-Path -LiteralPath $requestPath)) {
        Write-Output "VALID approved verdict without revision request: $verdictPath"
        return
    }
    if (-not (Test-Path -LiteralPath $requestPath -PathType Leaf)) {
        throw "Retained revision request must be a JSON file: $requestPath"
    }
}

if (($verdictStatus -ne "APPROVED") -and (-not $classificationMatch.Success)) {
    throw "Non-approved verify verdict requires Failure Classification"
}
if (($verdictStatus -ne "APPROVED") -and (-not (Test-Path -LiteralPath $requestPath -PathType Leaf))) {
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

$expectedVerdictPath = "plans/artifacts/$taskSlug/verify-verdict.md"
$allowedActions = @{
    "NEEDS_REVISION/fixable" = "revise"
    "REJECTED/needs_replan" = "replan"
    "REJECTED/escalate" = "escalate"
}

$requestPlanPath = Assert-NonEmptyString (Get-JsonProperty $request "plan_path" "document") "plan_path"
if ($requestPlanPath -cne $expectedPlanPath) {
    throw "Revision request plan_path '$requestPlanPath' must match '$expectedPlanPath'"
}

$requestVerdictPath = Assert-NonEmptyString (Get-JsonProperty $request "source_verdict_path" "document") "source_verdict_path"
if ($requestVerdictPath -cne $expectedVerdictPath) {
    throw "Revision request source_verdict_path '$requestVerdictPath' must match '$expectedVerdictPath'"
}

$requestStatus = Assert-NonEmptyString (Get-JsonProperty $request "source_verdict_status" "document") "source_verdict_status"
if (($verdictStatus -ne "APPROVED") -and ($requestStatus -cne $verdictStatus)) {
    throw "Revision request source_verdict_status '$requestStatus' must match '$verdictStatus'"
}

$failureClassification = Assert-NonEmptyString (Get-JsonProperty $request "failure_classification" "document") "failure_classification"
$mappingKey = if ($verdictStatus -eq "APPROVED") {
    "$requestStatus/$failureClassification"
} else {
    $verdictClassification = $classificationMatch.Groups[1].Value
    if ($failureClassification -cne $verdictClassification) {
        throw "Revision request failure_classification '$failureClassification' must match '$verdictClassification'"
    }
    "$verdictStatus/$verdictClassification"
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
