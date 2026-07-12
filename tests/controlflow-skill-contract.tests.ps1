$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Read-Skill([string]$RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing skill file: $RelativePath"
    }

    return Get-Content -LiteralPath $path -Raw
}

function Assert-Contains([string]$Content, [string]$Needle, [string]$Label) {
    $normalizedContent = $Content -replace '\s+', ' '
    $normalizedNeedle = $Needle -replace '\s+', ' '
    if ($normalizedContent -notmatch [regex]::Escape($normalizedNeedle)) {
        throw "Missing '$Label': expected to find '$Needle'"
    }
}

$plan = Read-Skill "skills/controlflow-plan/SKILL.md"
$verify = Read-Skill "skills/controlflow-verify/SKILL.md"
$review = Read-Skill "skills/controlflow-review/SKILL.md"
$readme = Read-Skill "README.md"

Assert-Contains $plan "No Speculative Abstractions" "plan anti-abstraction rule"
Assert-Contains $plan "Context Language Rule" "plan documentation language rule"
Assert-Contains $plan "XML documentation" "plan XML documentation rule"
Assert-Contains $plan "business-logic comments" "plan business-logic comment rule"
Assert-Contains $plan "Feedback Loop Contract" "plan feedback-loop section"
Assert-Contains $plan "Goal Statement" "plan goal statement field"
Assert-Contains $plan "ask clarifying questions" "plan clarification loop"
Assert-Contains $plan "Success Criteria must be measurable" "plan measurable success criteria"
Assert-Contains $plan "Artifact B" "plan metadata artifact"
Assert-Contains $plan "plans/artifacts/<task>/plan.meta.json" "plan metadata location"
Assert-Contains $plan "schemas/plan-meta.schema.json" "plan metadata schema"
Assert-Contains $plan "Template Library" "plan template library section"
Assert-Contains $plan "bugfix-plan-template.md" "plan bugfix template mapping"
Assert-Contains $plan "refactor-plan-template.md" "plan refactor template mapping"
Assert-Contains $plan "migration-plan-template.md" "plan migration template mapping"
Assert-Contains $plan "feature-plan-template.md" "plan feature template mapping"
Assert-Contains $plan "docs-test-only-plan-template.md" "plan docs template mapping"
Assert-Contains $plan "do not select a template speculatively" "plan template ambiguity rule"
Assert-Contains $plan "score-plan.ps1" "plan deterministic scorer command"
Assert-Contains $plan "does not execute declared plan commands" "plan scorer safety boundary"
Assert-Contains $plan "snapshot-context.ps1" "plan context snapshot command"
Assert-Contains $plan "context-snapshot.json" "plan context snapshot artifact"
Assert-Contains $plan "before authoring the plan" "plan snapshot timing"
Assert-Contains $plan "Multi-Candidate Planning" "plan multi-candidate section"
Assert-Contains $plan "MEDIUM" "plan multi-candidate tier reference"
Assert-Contains $plan "score-plan.ps1" "plan scorer in multi-candidate"
Assert-Contains $plan "revision-request.json" "plan revision request artifact"
Assert-Contains $plan "next_action" "plan revision action"

Assert-Contains $verify "XML documentation and business-logic comments" "verify documentation gate"
Assert-Contains $verify "dominant local language" "verify language gate"
Assert-Contains $verify "new abstraction is justified" "verify abstraction gate"
Assert-Contains $verify "user-facing goal statement" "verify goal statement gate"
Assert-Contains $verify "unresolved clarifying questions" "verify clarification gate"
Assert-Contains $verify "success criteria are measurable" "verify success criteria gate"
Assert-Contains $verify "Score Breakdown" "verify score breakdown"
Assert-Contains $verify "Revision Patch Instructions" "verify revision instructions"
Assert-Contains $verify "plan.meta.json" "verify metadata input"
Assert-Contains $verify "score-plan.ps1" "verify deterministic scorer input"
Assert-Contains $verify "does not replace adversarial verification" "verify scorer boundary"
Assert-Contains $verify "validate-revision.ps1" "verify revision validator"
Assert-Contains $verify "does not apply plan changes automatically" "verify revision boundary"

Assert-Contains $review "Documentation and Comment Pass" "review documentation pass"
Assert-Contains $review "speculative abstraction" "review abstraction review wording"
Assert-Contains $review "user explicitly requested a different language" "review language override"
Assert-Contains $review "goal and success criteria" "review goal criteria comparison"
Assert-Contains $review "feedback loop" "review feedback-loop closure"
Assert-Contains $review "plan.meta.json" "review metadata input"
Assert-Contains $review "planned paths" "review metadata path comparison"
Assert-Contains $review "context-snapshot" "review snapshot comparison input"
Assert-Contains $review "detect-drift.ps1" "review drift detector command"
Assert-Contains $review "blocking_scope_drift" "review drift classification"

Assert-Contains $readme "Structured plan metadata" "README metadata section"
Assert-Contains $readme "-RequirePlanMetadata" "README metadata validator option"
Assert-Contains $readme "plans/artifacts/<task>/plan.meta.json" "README metadata location"
Assert-Contains $readme "Plan templates" "README template section"
Assert-Contains $readme "not validated execution plans" "README template boundary"
Assert-Contains $readme "Deterministic plan scoring" "README scoring section"
Assert-Contains $readme "criteria_coverage" "README scoring metric"
Assert-Contains $readme "does not execute declared plan commands" "README scoring safety boundary"
Assert-Contains $readme "Context snapshot" "README snapshot section"
Assert-Contains $readme "snapshot-context.ps1" "README snapshot command"
Assert-Contains $readme "context-snapshot.json" "README snapshot artifact location"
Assert-Contains $readme "Scope drift detection" "README drift section"
Assert-Contains $readme "detect-drift.ps1" "README drift command"
Assert-Contains $readme "blocking_scope_drift" "README drift classification"
Assert-Contains $readme "Release workflow" "README release section"
Assert-Contains $readme "release.ps1" "README release command"
Assert-Contains $readme "semver" "README release semver reference"
Assert-Contains $readme "Revision loop" "README revision section"

Write-Output "VALID skill behavior contract"
