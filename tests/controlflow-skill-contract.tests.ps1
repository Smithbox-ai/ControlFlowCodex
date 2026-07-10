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

Assert-Contains $verify "XML documentation and business-logic comments" "verify documentation gate"
Assert-Contains $verify "dominant local language" "verify language gate"
Assert-Contains $verify "new abstraction is justified" "verify abstraction gate"
Assert-Contains $verify "user-facing goal statement" "verify goal statement gate"
Assert-Contains $verify "unresolved clarifying questions" "verify clarification gate"
Assert-Contains $verify "success criteria are measurable" "verify success criteria gate"
Assert-Contains $verify "Score Breakdown" "verify score breakdown"
Assert-Contains $verify "Revision Patch Instructions" "verify revision instructions"
Assert-Contains $verify "plan.meta.json" "verify metadata input"

Assert-Contains $review "Documentation and Comment Pass" "review documentation pass"
Assert-Contains $review "speculative abstraction" "review abstraction review wording"
Assert-Contains $review "user explicitly requested a different language" "review language override"
Assert-Contains $review "goal and success criteria" "review goal criteria comparison"
Assert-Contains $review "feedback loop" "review feedback-loop closure"
Assert-Contains $review "plan.meta.json" "review metadata input"
Assert-Contains $review "planned paths" "review metadata path comparison"

Assert-Contains $readme "Structured plan metadata" "README metadata section"
Assert-Contains $readme "-RequirePlanMetadata" "README metadata validator option"
Assert-Contains $readme "plans/artifacts/<task>/plan.meta.json" "README metadata location"

Write-Output "VALID skill behavior contract"
