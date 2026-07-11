# Plan Template Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five paired Markdown and JSON plan templates, document safe manual selection in `$controlflow-plan`, and enforce the library with the existing PowerShell contract suite.

**Architecture:** Templates in `plans/templates/` are authoring aids, not executable plans. A standalone template contract test validates the required Markdown sections, task-specific invariant, JSON parsing, and mandatory sidecar fields; the existing runner and Pester wrapper execute it without a dependency change.

**Tech Stack:** Markdown, JSON, Windows PowerShell 5.1, PowerShell 7, Pester, GitHub Actions.

## Global Constraints

- Keep the plugin skill-only: no router, runtime, task classifier, app, package dependency, or custom agent.
- Use exactly `bugfix`, `refactor`, `migration`, `feature`, and `docs-test-only`.
- Templates are not validated execution plans; copied plans must be grounded in repository evidence and create their normal artifacts.
- Do not change `validate-plan.ps1`; templates are checked only by the new template contract test.
- Every test must pass in Windows PowerShell and PowerShell 7.

## File Structure

| Path | Responsibility |
| --- | --- |
| `plans/templates/<kind>-plan-template.md` | Full ControlFlow Markdown skeleton for one task kind. |
| `plans/templates/<kind>-plan-template.meta.json` | Parseable structured skeleton aligned with its Markdown template. |
| `tests/template-contract.tests.ps1` | Checks all template pairs, headings, invariants, JSON, and required fields. |
| `tests/run-contract-tests.ps1` | Adds the new standalone test to the portable suite. |
| `tests/controlflow-skill-contract.tests.ps1` | Guards template mapping and documentation language. |
| `skills/controlflow-plan/SKILL.md` | Documents manual type selection and ambiguity behavior. |
| `README.md` and `CHANGELOG.md` | Public template-library documentation. |

### Task 1: Template Contract Test

**Files:**

- Create: `tests/template-contract.tests.ps1`
- Modify: `tests/run-contract-tests.ps1`

**Interfaces:**

- Consumes: the ten template files under `plans/templates/`.
- Produces: `VALID template library contract` or a terminating error naming the failing kind and artifact.

- [x] **Step 1: Write the failing test**

Create `tests/template-contract.tests.ps1` with this exact contract:

```powershell
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$templateRoot = Join-Path $repoRoot "plans/templates"
$headings = @("# Plan:", "## Context & Analysis", "## Design Decisions", "## Implementation Phases", "## Inter-Phase Contracts", "## Open Questions", "## Risks", "## Semantic Risk Review", "## Success Criteria", "## Handoff", "## Notes for Execution", "## Progress", "## Discoveries", "## Decision Log", "## Outcomes", "## Idempotence & Recovery")
$fields = @("schema_version", "plan_path", "goal", "complexity_tier", "phases", "semantic_risks", "success_criteria")
$invariants = @{
    "bugfix" = "Reproduce the observed regression before implementation."
    "refactor" = "Characterize and preserve behavior before structural change."
    "migration" = "State compatibility, backup or rollback, and safety gates."
    "feature" = "Connect requested behavior to a measurable acceptance criterion."
    "docs-test-only" = "Limit scope to documentation or tests; runtime behavior must not change."
}
foreach ($kind in $invariants.Keys) {
    $markdownPath = Join-Path $templateRoot "$kind-plan-template.md"
    $metadataPath = Join-Path $templateRoot "$kind-plan-template.meta.json"
    if (-not (Test-Path -LiteralPath $markdownPath -PathType Leaf)) { throw "Missing Markdown template: $markdownPath" }
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw "Missing metadata template: $metadataPath" }
    $markdown = Get-Content -LiteralPath $markdownPath -Raw
    foreach ($heading in $headings) {
        if ($markdown -notmatch [regex]::Escape($heading)) { throw "Template '$kind' is missing heading '$heading'" }
    }
    if ($markdown -notmatch [regex]::Escape("Task-Type Invariant: $($invariants[$kind])")) { throw "Template '$kind' is missing its task-type invariant" }
    try { $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json } catch { throw "Metadata template '$kind' is not valid JSON: $($_.Exception.Message)" }
    foreach ($field in $fields) {
        if ($null -eq $metadata.PSObject.Properties[$field]) { throw "Metadata template '$kind' is missing '$field'" }
    }
}
Write-Output "VALID template library contract"
```

- [x] **Step 2: Register and observe RED**

Add this immediately after the existing metadata test invocation in `tests/run-contract-tests.ps1`:

```powershell
Invoke-ContractScript "template-contract.tests.ps1"
```

Run `powershell -ExecutionPolicy Bypass -File tests\template-contract.tests.ps1`.

Expected: FAIL with `Missing Markdown template` because the library does not exist.

### Task 2: Five Markdown Template Skeletons

**Files:**

- Create: `plans/templates/bugfix-plan-template.md`
- Create: `plans/templates/refactor-plan-template.md`
- Create: `plans/templates/migration-plan-template.md`
- Create: `plans/templates/feature-plan-template.md`
- Create: `plans/templates/docs-test-only-plan-template.md`
- Test: `tests/template-contract.tests.ps1`

**Interfaces:**

- Consumes: kind-to-invariant mapping in Task 1.
- Produces: five complete ControlFlow heading skeletons with one exact `Task-Type Invariant` line.

- [x] **Step 1: Create the skeletons**

Each template has the full heading set asserted in Task 1, one `### Phase 1 - <TYPE-SPECIFIC PHASE>` heading, a seven-row semantic-risk table, the normal lifecycle headings, and authoring markers `<USER-FACING GOAL>`, `<VERIFIED FILE>`, and `<EXACT COMMAND>`. Use this matrix exactly:

| Kind | Header title | Tier | Invariant | Phase objective | Top-level criterion |
| --- | --- | --- | --- | --- | --- |
| bugfix | Bugfix Template | SMALL | Reproduce the observed regression before implementation. | Demonstrate the regression, then implement the smallest correction. | A focused regression test fails before and passes after the correction. |
| refactor | Refactor Template | SMALL | Characterize and preserve behavior before structural change. | Capture current behavior, then simplify one selected structure. | Characterization and full contract tests preserve behavior. |
| migration | Migration Template | MEDIUM | State compatibility, backup or rollback, and safety gates. | Define compatibility and recovery before the migration. | Validation proves the compatible path and rollback or recovery. |
| feature | Feature Template | MEDIUM | Connect requested behavior to a measurable acceptance criterion. | Add requested behavior from one failing acceptance test. | A focused test and full contract suite prove the behavior. |
| docs-test-only | Docs/Test-Only Template | SMALL | Limit scope to documentation or tests; runtime behavior must not change. | Update public contract or tests without runtime change. | Documentation or test assertions pass with no runtime file change. |

The migration risk disposition explicitly mentions rollback. The docs/test-only disposition explicitly says runtime behavior is unchanged.

- [x] **Step 2: Verify the intermediate failure**

Run `powershell -ExecutionPolicy Bypass -File tests\template-contract.tests.ps1`.

Expected: FAIL with `Missing metadata template` after Markdown headings and invariants pass.

### Task 3: Five JSON Metadata Skeletons

**Files:**

- Create: `plans/templates/bugfix-plan-template.meta.json`
- Create: `plans/templates/refactor-plan-template.meta.json`
- Create: `plans/templates/migration-plan-template.meta.json`
- Create: `plans/templates/feature-plan-template.meta.json`
- Create: `plans/templates/docs-test-only-plan-template.meta.json`
- Test: `tests/template-contract.tests.ps1`

**Interfaces:**

- Consumes: title, tier, objective, and criterion matrix from Task 2.
- Produces: five valid JSON objects with the seven sidecar fields asserted in Task 1.

- [x] **Step 1: Create JSON files**

Every file has this exact field shape, populated with its Task 2 tier, objective, and criterion:

```json
{
  "schema_version": "1.0.0",
  "plan_path": "plans/<task>-plan.md",
  "goal": "<USER-FACING GOAL>",
  "complexity_tier": "<TASK 2 TIER>",
  "phases": [{"id": "1", "objective": "<TASK 2 OBJECTIVE>", "dependencies": [], "files": ["<VERIFIED FILE>"], "commands": ["<EXACT COMMAND>"], "success_criteria": ["<TASK 2 CRITERION>"]}],
  "semantic_risks": [{"category": "data_volume", "applicability": "not_applicable", "impact": "LOW"}, {"category": "performance", "applicability": "not_applicable", "impact": "LOW"}, {"category": "concurrency", "applicability": "not_applicable", "impact": "LOW"}, {"category": "access_control", "applicability": "not_applicable", "impact": "LOW"}, {"category": "migration_rollback", "applicability": "not_applicable", "impact": "LOW"}, {"category": "dependency", "applicability": "not_applicable", "impact": "LOW"}, {"category": "operability", "applicability": "applicable", "impact": "LOW"}],
  "success_criteria": ["<TASK 2 CRITERION>"]
}
```

For migration, use `migration_rollback: applicable` with `MEDIUM` and
`operability: applicable` with `HIGH` to preserve its safety gate; for feature
and refactor use `operability: applicable` with `MEDIUM`; docs-test-only repeats
its no-runtime-change criterion.

- [x] **Step 2: Verify GREEN in both shells**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests\template-contract.tests.ps1
pwsh -NoProfile -File tests\template-contract.tests.ps1
```

Expected: both print `VALID template library contract` and exit 0.

### Task 4: Planner and Public Documentation

**Files:**

- Modify: `skills/controlflow-plan/SKILL.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `tests/controlflow-skill-contract.tests.ps1`
- Test: `tests/controlflow-skill-contract.tests.ps1`

**Interfaces:**

- Consumes: exact filenames from Tasks 2 and 3.
- Produces: stable documentation that maps only unambiguous work to a template and asks before guessing.

- [x] **Step 1: Write failing skill/documentation assertions**

Append these assertions before the final output statement:

```powershell
Assert-Contains $plan "Template Library" "plan template library section"
Assert-Contains $plan "bugfix-plan-template.md" "plan bugfix template mapping"
Assert-Contains $plan "refactor-plan-template.md" "plan refactor template mapping"
Assert-Contains $plan "migration-plan-template.md" "plan migration template mapping"
Assert-Contains $plan "feature-plan-template.md" "plan feature template mapping"
Assert-Contains $plan "docs-test-only-plan-template.md" "plan docs template mapping"
Assert-Contains $plan "do not select a template speculatively" "plan template ambiguity rule"
Assert-Contains $readme "Plan templates" "README template section"
Assert-Contains $readme "not validated execution plans" "README template boundary"
```

Run `powershell -ExecutionPolicy Bypass -File tests\controlflow-skill-contract.tests.ps1`.

Expected: FAIL with `Missing 'plan template library section'`.

- [x] **Step 2: Implement minimum wording**

Add `## Template Library` after `## Artifact-First Output` in `skills/controlflow-plan/SKILL.md`. Map every kind to its exact Markdown filename, require copying the paired JSON template and replacing all authoring markers with repository evidence, and state `do not select a template speculatively` when the task type is ambiguous.

Add `## Plan templates` after `## Structured plan metadata` in `README.md`. List the five kinds and say templates are `not validated execution plans`; copied plans must be grounded and create normal artifacts. Add one Unreleased changelog bullet for the paired templates and template contract test.

- [x] **Step 3: Verify GREEN**

Run `powershell -ExecutionPolicy Bypass -File tests\controlflow-skill-contract.tests.ps1`.

Expected: `VALID skill behavior contract` and exit 0.

### Task 5: Full Verification

**Files:**

- Modify: `docs/superpowers/plans/2026-07-11-plan-template-library.md` only to mark completed tasks during execution.
- Test: `tests/run-contract-tests.ps1` and `tests/controlflow-contract.Tests.ps1`

**Interfaces:**

- Consumes: artifacts and tests from Tasks 1 through 4.
- Produces: fresh Windows PowerShell, PowerShell 7, Pester, and whitespace evidence.

- [x] **Step 1: Run the Windows PowerShell suite**

Run `powershell -ExecutionPolicy Bypass -File tests\run-contract-tests.ps1 -UsePester`.

Expected: `Passed: 1 Failed: 0`, `VALID template library contract`, and `VALID ControlFlow contract suite`.

- [x] **Step 2: Run the PowerShell 7 suite**

Run `pwsh -NoProfile -File tests\run-contract-tests.ps1`.

Expected: `VALID template library contract` and `VALID ControlFlow contract suite`.

- [x] **Step 3: Check changed scope and whitespace**

Run:

```powershell
git diff --check
git diff --name-only
```

Expected: no whitespace errors; paths are limited to templates, their tests, planner skill, README, changelog, and this plan.

- [x] **Step 4: Commit**

```powershell
git add plans/templates tests/template-contract.tests.ps1 tests/run-contract-tests.ps1 tests/controlflow-skill-contract.tests.ps1 skills/controlflow-plan/SKILL.md README.md CHANGELOG.md docs/superpowers/plans/2026-07-11-plan-template-library.md
git commit -m "feat: add plan template library"
```

## Self-Review

- Spec coverage: Tasks 1 through 3 implement all ten artifacts; Task 4 implements safe selection and documentation; Task 5 supplies all stated evidence.
- Scope: release packaging, automatic selection, runtime behavior, drift detection, and multi-candidate planning are excluded.
- Naming: every task uses the same `<kind>-plan-template.md` and `<kind>-plan-template.meta.json` convention.
