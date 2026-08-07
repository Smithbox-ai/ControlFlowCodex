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

function Assert-NotContains([string]$Content, [string]$Needle, [string]$Label) {
    if ($Content -match [regex]::Escape($Needle)) {
        throw "Forbidden '$Label' still present: '$Needle' (removed in Compact vNext)"
    }
}

$plan = Read-Skill "skills/controlflow-plan/SKILL.md"
$verify = Read-Skill "skills/controlflow-verify/SKILL.md"
$review = Read-Skill "skills/controlflow-review/SKILL.md"
$planYaml = Read-Skill "skills/controlflow-plan/agents/openai.yaml"
$verifyYaml = Read-Skill "skills/controlflow-verify/agents/openai.yaml"
$reviewYaml = Read-Skill "skills/controlflow-review/agents/openai.yaml"
$readme = Read-Skill "README.md"

# --- plan skill: compact durable contract ---
Assert-Contains $plan 'after native `/plan`' 'plan positions after native /plan'
Assert-Contains $plan "plans/artifacts/<task-slug>/plan.meta.json" "plan metadata artifact"
Assert-Contains $plan "schema_version: 2.0.0" "plan v2 schema version"
Assert-Contains $plan "baseline" "plan baseline field"
Assert-Contains $plan "dirty_paths" "plan dirty_paths field"
Assert-Contains $plan "scope" "plan scope field"
Assert-Contains $plan "criteria" "plan criteria field"
Assert-Contains $plan "checks" "plan checks field"
Assert-Contains $plan "risks" "plan risks field"
Assert-Contains $plan "phases" "plan phases field"
Assert-Contains $plan "TRIVIAL" "plan trivial tier"
Assert-Contains $plan "LARGE" "plan large tier"
Assert-Contains $plan "scripts/validate-plan.ps1" "plan validator command"
Assert-Contains $plan '$controlflow-verify' 'plan hands off to verify'
Assert-Contains $plan "not_applicable" "plan sparse risks rule"
Assert-Contains $plan "Do not duplicate native execution" "plan native boundary"

# plan skill must NOT reference removed runtime surface
Assert-NotContains $plan "score-plan.ps1" "plan scorer reference"
Assert-NotContains $plan "revision-request.json" "plan revision handoff"
Assert-NotContains $plan "snapshot-context.ps1" "plan snapshot script"
Assert-NotContains $plan "context-snapshot.json" "plan snapshot artifact"
Assert-NotContains $plan "Multi-Candidate Planning" "plan multi-candidate section"
Assert-NotContains $plan "bugfix-plan-template" "plan bugfix template"
Assert-NotContains $plan "Semantic Risk Review" "plan forced seven-row risk table"

# --- verify skill: five questions + compact verdict ---
Assert-Contains $verify "Five questions" "verify five questions section"
Assert-Contains $verify "APPROVED | NEEDS_REVISION | REPLAN" "verify verdict statuses"
Assert-Contains $verify "verify-verdict.md" "verify verdict artifact"
Assert-Contains $verify "plan.meta.json" "verify metadata input"
Assert-Contains $verify "Try to break the plan" "verify adversarial stance"
Assert-Contains $verify "Residual uncertainty" "verify residual uncertainty section"

Assert-NotContains $verify "score-plan.ps1" "verify scorer reference"
Assert-NotContains $verify "validate-revision.ps1" "verify revision validator"
Assert-NotContains $verify "revision-request.json" "verify revision handoff"
Assert-NotContains $verify "Score Breakdown" "verify score breakdown"
Assert-NotContains $verify "Mirage Catalog" "verify mirage catalog"
Assert-NotContains $verify "P1 Phantom API" "verify mirage codes"

# --- review skill: four conformance checks ---
Assert-Contains $review "Four checks" "review four checks section"
Assert-Contains $review "detect-drift.ps1" "review drift detector command"
Assert-Contains $review "planned" "review planned classification"
Assert-Contains $review "unplanned" "review unplanned classification"
Assert-Contains $review "plan.meta.json" "review metadata input"
Assert-Contains $review 'native `/review`' 'review delegates to native /review'
Assert-Contains $review "Success criteria vs evidence" "review criteria-vs-evidence check"

Assert-NotContains $review "context-snapshot" "review snapshot reference"
Assert-NotContains $review "blocking_scope_drift" "review old drift classification"
Assert-NotContains $review "Documentation and Comment Pass" "review generic docs pass"
Assert-NotContains $review "Over-Engineering Pass" "review generic over-engineering pass"

# --- yaml policies: all three explicit-only ---
Assert-Contains $planYaml "allow_implicit_invocation: false" "plan implicit invocation disabled"
Assert-Contains $verifyYaml "allow_implicit_invocation: false" "verify implicit invocation disabled"
Assert-Contains $reviewYaml "allow_implicit_invocation: false" "review implicit invocation disabled"

# --- README: compact vNext framing ---
Assert-Contains $readme "Compact" "README compact framing"
Assert-Contains $readme "durable execution contract" "README durable contract"
Assert-Contains $readme "plan.meta.json" "README metadata reference"
Assert-Contains $readme "detect-drift.ps1" "README drift command"
Assert-Contains $readme "validate-plan.ps1" "README validator command"
Assert-Contains $readme "evals" "README eval methodology"
Assert-NotContains $readme "score-plan.ps1" "README runtime scorer reference"
Assert-NotContains $readme "revision-request" "README revision loop reference"
Assert-NotContains $readme "snapshot-context.ps1" "README snapshot command"

Write-Output "VALID skill behavior contract"

