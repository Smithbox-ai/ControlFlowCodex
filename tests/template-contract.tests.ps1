$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$templateRoot = Join-Path $repoRoot "plans/templates"
$headings = @(
    "# Plan:",
    "## Context & Analysis",
    "## Design Decisions",
    "## Implementation Phases",
    "## Inter-Phase Contracts",
    "## Open Questions",
    "## Risks",
    "## Semantic Risk Review",
    "## Success Criteria",
    "## Handoff",
    "## Notes for Execution",
    "## Progress",
    "## Discoveries",
    "## Decision Log",
    "## Outcomes",
    "## Idempotence & Recovery"
)
$fields = @(
    "schema_version",
    "plan_path",
    "goal",
    "complexity_tier",
    "phases",
    "semantic_risks",
    "success_criteria"
)
$invariants = @{
    "bugfix" = "Reproduce the observed regression before implementation."
    "refactor" = "Characterize and preserve behavior before structural change."
    "migration" = "State compatibility, backup or rollback, and safety gates."
    "feature" = "Connect requested behavior to a measurable acceptance criterion."
    "docs-test-only" = "Limit scope to documentation or tests; runtime behavior must not change."
}

foreach ($kind in $invariants.Keys) {
    $markdownPath = Join-Path $templateRoot "${kind}-plan-template.md"
    $metadataPath = Join-Path $templateRoot "${kind}-plan-template.meta.json"
    if (-not (Test-Path -LiteralPath $markdownPath -PathType Leaf)) {
        throw "Missing Markdown template: $markdownPath"
    }
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Missing metadata template: $metadataPath"
    }

    $markdown = Get-Content -LiteralPath $markdownPath -Raw
    foreach ($heading in $headings) {
        if ($markdown -notmatch [regex]::Escape($heading)) {
            throw "Template '$kind' is missing heading '$heading'"
        }
    }
    if ($markdown -notmatch [regex]::Escape("Task-Type Invariant: $($invariants[$kind])")) {
        throw "Template '$kind' is missing its task-type invariant"
    }

    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    } catch {
        throw "Metadata template '$kind' is not valid JSON: $($_.Exception.Message)"
    }
    foreach ($field in $fields) {
        if ($null -eq $metadata.PSObject.Properties[$field]) {
            throw "Metadata template '$kind' is missing '$field'"
        }
    }
}

Write-Output "VALID template library contract"
