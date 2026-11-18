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
        throw "Forbidden retired runtime '$Label' still present: '$Needle'"
    }
}

$plan = Read-Skill "skills/controlflow-plan/SKILL.md"
$verify = Read-Skill "skills/controlflow-verify/SKILL.md"
$review = Read-Skill "skills/controlflow-review/SKILL.md"
$entry = Read-Skill "skills/controlflow/SKILL.md"
$execution = Read-Skill "skills/controlflow/references/execution.md"
$progress = Read-Skill "skills/controlflow/references/progress.md"
$reviewReference = Read-Skill "skills/controlflow/references/review.md"
$planYaml = Read-Skill "skills/controlflow-plan/agents/openai.yaml"
$verifyYaml = Read-Skill "skills/controlflow-verify/agents/openai.yaml"
$reviewYaml = Read-Skill "skills/controlflow-review/agents/openai.yaml"
$readme = Read-Skill "README.md"
$evidence = Read-Skill "skills/controlflow/references/evidence.md"
$runtime = Read-Skill "docs/v4-runtime.md"

# --- plan skill: compact durable contract ---
Assert-Contains $plan 'while native Plan Mode is active' 'plan does not write state in native Plan Mode'
Assert-Contains $progress 'Outside native Plan Mode' 'native TODO uses the host mode as well as tool availability'
Assert-Contains $execution 'Omit `-SessionId`' 'manual fallback never binds a native Stop hook'
Assert-Contains $execution 'separate native planning thread' 'active run isolation when native Stop lacks Plan Mode identity'
Assert-Contains $plan 'nested `AGENTS.md`' 'affected paths can have instructions outside the initial discovery chain'
Assert-Contains $plan "get-storage-paths.ps1" "canonical external plan location"
Assert-Contains $execution "get-storage-paths.ps1" "external storage setup"
Assert-Contains $readme "CONTROLFLOW_STATE_ROOT" "external storage configuration"
foreach($guidance in @($plan,$verify,$review,$execution)) { Assert-NotContains $guidance 'plans/artifacts' 'project bookkeeping path' }
Assert-Contains $plan "schema_version: 4.0.0" "plan V4 schema version"
Assert-Contains $plan "baseline" "plan baseline field"
Assert-Contains $plan "dirty_paths" "plan dirty_paths field"
Assert-Contains $plan "scope" "plan scope field"
Assert-Contains $plan "criteria" "plan criteria field"
Assert-Contains $plan "checks" "plan checks field"
Assert-Contains $plan "risks" "plan risks field"
Assert-Contains $plan "phases" "plan phases field"
Assert-Contains $plan "light profile" "safe docs proportionality"
Assert-Contains $plan "LARGE" "plan large tier"
Assert-Contains $plan "scripts/validate-contract.ps1" "plan validator command"
Assert-Contains $plan '../controlflow-verify/SKILL.md' 'the agent reads Verify instead of impersonating an explicit skill invocation'
Assert-Contains $execution '../../controlflow-review/SKILL.md' 'the agent reads Review instead of impersonating an explicit skill invocation'
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

# --- execution policy: current justification, not numerical architecture gates ---
foreach ($principle in @('smallest coherent', 'not fewest lines', 'repository conventions',
    'demonstrated duplication', 'meaningful boundary', 'testability', 'side-effect isolation',
    'one-use', 'new file', 'hypothetical future reuse', 'unrelated refactoring', 'obsolete',
    'compatibility', 'comments', 'validation effort to risk')) {
    Assert-Contains $execution $principle "proportional implementation: $principle"
}

# --- verify skill: six questions + compact verdict ---
Assert-Contains $verify "Six questions" "verify six questions section"
Assert-Contains $verify "material speculative architecture" "preflight proportionality question"
Assert-Contains $verify "concrete unnecessary" "preflight requires a concrete proportionality finding"
Assert-Contains $verify "counts alone" "preflight permits justified architecture"
Assert-Contains $verify "APPROVED | NEEDS_REVISION | REPLAN" "verify verdict statuses"
Assert-Contains $verify "review rationale inside the active run directory" "bound review rationale"
Assert-Contains $verify "plan.meta.json" "verify metadata input"
Assert-Contains $verify "Try to break the plan" "verify adversarial stance"
Assert-Contains $verify "Residual uncertainty" "verify residual uncertainty section"

Assert-NotContains $verify "score-plan.ps1" "verify scorer reference"
Assert-NotContains $verify "validate-revision.ps1" "verify revision validator"
Assert-NotContains $verify "revision-request.json" "verify revision handoff"
Assert-NotContains $verify "Score Breakdown" "verify score breakdown"
Assert-NotContains $verify "Mirage Catalog" "verify mirage catalog"
Assert-NotContains $verify "P1 Phantom API" "verify mirage codes"
Assert-NotContains $verify '`/review`' 'generic Git diff review is outside plan preflight'

# --- review skill: five conformance checks ---
Assert-Contains $review "Five checks" "review five checks section"
foreach ($signal in @('Implementation proportionality', 'material', 'fragmentation',
    'speculative extensibility', 'compatibility', 'unrelated refactoring',
    'maintenance burden', 'behavioral surface', 'raw line counts', 'file/class size thresholds')) {
    Assert-Contains $review $signal "conformance proportionality: $signal"
}
Assert-Contains $review "completion-gate.ps1" "current scope and evidence gate"
Assert-Contains $review "planned" "review planned classification"
Assert-Contains $review "unplanned" "review unplanned classification"
Assert-Contains $review "plan.meta.json" "review metadata input"
Assert-Contains $review 'native `/review`' 'review delegates to native /review'
Assert-Contains $review "Success criteria vs evidence" "review criteria-vs-evidence check"

Assert-NotContains $review "context-snapshot" "review snapshot reference"
Assert-NotContains $review "blocking_scope_drift" "review old drift classification"
Assert-NotContains $review "Documentation and Comment Pass" "review generic docs pass"
Assert-NotContains $review "Over-Engineering Pass" "review generic over-engineering pass"

# --- existing tiers and native ownership remain intact ---
$trivial = [regex]::Match($entry, '(?ms)^- \*\*TRIVIAL:\*\* .*?(?=^- \*\*|\z)').Value
$small = [regex]::Match($entry, '(?ms)^- \*\*SMALL:\*\* .*?(?=^- \*\*|\z)').Value
Assert-Contains $entry 'new legacy runs are rejected' 'V4-only new admission'
Assert-Contains $small 'compact V4 profile' 'SMALL keeps profile-sensitive gates'
Assert-Contains $plan 'do not add mandatory readers or diagrams' 'light docs avoid ceremony'
Assert-Contains $execution 'Light docs follow their packet/applicable-evidence path' 'light docs keep compact current evidence'
Assert-Contains $verify 'zero shipped subagents' 'no new verifier agent requirement'
Assert-Contains $review 'reuse native `/review` findings' 'native generic review ownership and reuse'
Assert-Contains $review 'a specific reviewer or review mode' 'the contract controls independent reviewer requirements'

# --- yaml policies: all three explicit-only ---
Assert-Contains $planYaml "allow_implicit_invocation: false" "plan implicit invocation disabled"
Assert-Contains $verifyYaml "allow_implicit_invocation: false" "verify implicit invocation disabled"
Assert-Contains $reviewYaml "allow_implicit_invocation: false" "review implicit invocation disabled"
foreach ($skill in @(@($entry,'controlflow'),@($plan,'controlflow-plan'),@($review,'controlflow-review'),@($verify,'controlflow-verify'))) {
    Assert-Contains $skill[0] ('$controlflow-codex:'+$skill[1]) 'documented native invocation is namespaced'
}

# --- README: compact vNext framing ---
Assert-Contains $readme "Compact" "README compact framing"
Assert-Contains $readme "durable execution contract" "README durable contract"
Assert-Contains $readme "contract_path" "README canonical metadata reference"
Assert-Contains $readme "completion-gate.ps1" "README completion gate"
Assert-Contains $readme "validate-contract.ps1" "README current validator command"
Assert-Contains $readme "evals" "README eval methodology"
Assert-NotContains $readme "score-plan.ps1" "README runtime scorer reference"
Assert-NotContains $readme "revision-request" "README revision loop reference"
Assert-NotContains $readme "snapshot-context.ps1" "README snapshot command"

# --- sensitivity guidance: make a decision, prove the regression, report limits ---
# The behavioral baseline omitted a required assessment and old-defect control;
# these assertions keep every skill entry linked to the shared evidence recipe.
Assert-Contains $entry 'test sensitivity' 'entry surfaces test sensitivity'
Assert-Contains $plan 'mutation_assessment' 'QA plan requires sensitivity decision'
Assert-Contains $plan 'references/evidence.md#test-sensitivity' 'planner links sensitivity recipe'
Assert-Contains $verify 'old defect' 'preflight requires regression negative control'
Assert-Contains $verify 'references/evidence.md#test-sensitivity' 'verifier links sensitivity recipe'
Assert-Contains $review 'old defect' 'review inspects regression negative control'
Assert-Contains $review 'references/evidence.md#test-sensitivity' 'review links sensitivity recipe'
foreach ($field in @('payload.mutation_assessment', 'decision', 'method', 'rationale',
    'scope', 'criterion_refs', 'check_refs', 'budget', 'acceptance')) {
    Assert-Contains $evidence $field "assessment field guidance: $field"
}
foreach ($choice in @('run', 'skip', 'unsupported', 'stryker', 'controlled', 'none',
    'old defect', 'isolated copy', 'expected failing test', 'actual result',
    'recurring bugs', 'financial', 'comparisons', 'human-only', 'light docs',
    'historic', 'minimum_score > 0', 'measurement', 'semantic quality')) {
    Assert-Contains $evidence $choice "sensitivity decision/limit: $choice"
}
Assert-Contains $runtime '"mutation_assessment"' 'runtime contains usable QA assessment example'
Assert-Contains $runtime '"quality_profiles"' 'runtime contains linked profile example'
Assert-Contains $runtime 'projectRoot' 'Stryker source root binding documented'
Assert-Contains $runtime 'UTF-8' 'Stryker source encoding binding documented'
Assert-Contains $runtime 'BOM' 'Stryker BOM normalization documented'
foreach ($status in @('ERROR', 'FAIL', 'TIMEOUT', 'STALE', 'NOT_RUN', 'PASS',
    'UNSUPPORTED', 'NOT_APPLICABLE')) {
    Assert-Contains $runtime $status "quality profile status semantics: $status"
}
Assert-Contains $readme 'mutation_assessment' 'README introduces explicit sensitivity decision'
Assert-Contains $readme 'old defect' 'README states regression negative control'

# --- applicable operating rules, live acceptance, and bounded repair ---
Assert-Contains $plan 'policy_refs' 'record source references for applicable domain and repository rules'
Assert-Contains $verify 'unresolved material conflict' 'reject preflight when applicable rules still conflict'
Assert-Contains $execution 'normal entry point' 'test changed user-facing behavior through the real entry point'
Assert-Contains $execution 'NOT_RUN' 'report unavailable startup or user-path evidence as unexecuted'
Assert-Contains $review 'observed outcome' 'distinguish evidence from outstanding user acceptance'
Assert-Contains $execution 'three repair rounds' 'bound retries for the same unresolved cause during execution'
Assert-Contains $execution 'required flaky check' 'preserve required checks even when intermittently failing'
Assert-Contains $evidence 'independently inspect changed assertions' 'review consequential test changes against the original expectation'
Assert-Contains $evidence 'independent negative control' 'use evidence outside the changed assertions'

# --- stronger evidence uses bounded scenarios and a stable acceptance source ---
Assert-Contains $plan 'version or revision' 'record the identity of externally governed rules when known'
Assert-Contains $verify 'before reusing an approval' 'review the current governing rules before relying on a past approval'
Assert-Contains $execution 'bounded readiness' 'plan a bounded observable startup check'
Assert-Contains $execution 'disallowed side effect' 'verify rejection and its effect where that is the risk'
Assert-Contains $execution 'clean up only' 'verification cleans up its own disposable resources'
Assert-Contains $execution 'repair_attempt' 'link the optional persisted repair budget'
Assert-Contains $evidence 'baseline_inputs' 'link fixed repository baseline verifier inputs'
Assert-Contains $evidence 'approved differences' 'differential checks preserve intentionally unchanged behavior'
Assert-Contains $evidence 'held-out inputs' 'independent verifiers can use private fixtures'
Assert-Contains $evidence 'verifier revision' 'record an independently reproducible acceptance source'
Assert-Contains $reviewReference 'before sharing the writer' 'obtain initial independent findings before the writer verdict'
Assert-Contains $reviewReference 'prior findings' 'focus subsequent review using findings from previous rounds'

Write-Output "VALID skill behavior contract"

