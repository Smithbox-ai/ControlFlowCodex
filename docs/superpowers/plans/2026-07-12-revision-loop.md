# Revision Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Add a deterministic, validated revision-request handoff for every non-approved ControlFlow verifier verdict.

**Architecture:** Keep plans and verifier verdicts as the existing human-facing
artifacts. Add a small JSON sidecar and a dependency-free PowerShell validator
that confirms it agrees with the plan, metadata, and verdict. The planner and
verifier consume and produce the artifact through guidance only; nothing patches
plans automatically.

**Tech Stack:** PowerShell 5.1+, PowerShell 7, JSON, existing Pester contract
runner.

## Global Constraints

- Preserve the thin, skill-only plugin boundary.
- Add no modules, external services, agents, routers, schedulers, or automatic
  patch application.
- Never execute plan or revision-request commands.
- Store the request at plans/artifacts/<task>/revision-request.json.
- Support only NEEDS_REVISION/fixable/revise,
  REJECTED/needs_replan/replan, and REJECTED/escalate/escalate.
- Preserve a prior valid revision request as historical evidence when a later
  verdict is APPROVED; do not treat it as the active action.
- Run focused tests in Windows PowerShell and PowerShell 7 before the full suite.

## File Structure

| Path | Responsibility |
| --- | --- |
| schemas/revision-request.schema.json | Portable JSON contract for the revision handoff. |
| scripts/validate-revision.ps1 | Validates one request against its plan, metadata, and verdict. |
| tests/fixtures/revision-request | Valid non-approved plan, metadata, verdict, and request fixture. |
| tests/revision-request.tests.ps1 | Focused valid, invalid, and approved-without-request contract cases. |
| tests/run-contract-tests.ps1 | Runs the new focused test in the portable suite. |
| tests/controlflow-skill-contract.tests.ps1 | Guards revision-loop wording. |
| skills/controlflow-plan/SKILL.md | Tells planners how to consume a revision request. |
| skills/controlflow-verify/SKILL.md | Tells verifiers how to create and validate a revision request. |
| README.md and CHANGELOG.md | Public artifact and command documentation. |
| .gitignore | Keeps local SDD progress and project worktrees out of the product diff. |

### Task 1: Schema and RED Contract Fixture

**Files:**

- Create: schemas/revision-request.schema.json
- Create: tests/fixtures/revision-request/plans/revision-loop-plan.md
- Create: tests/fixtures/revision-request/plans/artifacts/revision-loop/plan.meta.json
- Create: tests/fixtures/revision-request/plans/artifacts/revision-loop/verify-verdict.md
- Create: tests/fixtures/revision-request/plans/artifacts/revision-loop/revision-request.json
- Create: tests/revision-request.tests.ps1
- Modify: tests/run-contract-tests.ps1

**Interfaces:**

- Produces a fixture whose plan slug is revision-loop.
- Defines the request object consumed by validate-revision.ps1.
- Registers revision-request.tests.ps1 between metadata validation and scoring.

- [x] **Step 1: Add the schema before implementation**

Create a strict schema with this object shape:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/Smithbox-ai/ControlFlowCodex/schemas/revision-request.schema.json",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schema_version", "plan_path", "source_verdict_path",
    "source_verdict_status", "failure_classification",
    "next_action", "summary", "items"
  ],
  "properties": {
    "schema_version": { "const": "1.0.0" },
    "plan_path": { "type": "string", "pattern": "^plans/.+-plan\\.md$" },
    "source_verdict_path": { "type": "string", "pattern": "^plans/artifacts/.+/verify-verdict\\.md$" },
    "source_verdict_status": { "enum": ["NEEDS_REVISION", "REJECTED"] },
    "failure_classification": { "enum": ["fixable", "needs_replan", "escalate"] },
    "next_action": { "enum": ["revise", "replan", "escalate"] },
    "summary": { "type": "string", "minLength": 1 },
    "items": { "type": "array", "minItems": 1, "items": { "$ref": "#/$defs/item" } }
  },
  "$defs": {
    "item": {
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "location", "finding", "required_change", "acceptance_criteria"],
      "properties": {
        "id": { "type": "string", "minLength": 1 },
        "location": { "type": "string", "minLength": 1 },
        "finding": { "type": "string", "minLength": 1 },
        "required_change": { "type": "string", "minLength": 1 },
        "acceptance_criteria": { "type": "string", "minLength": 1 }
      }
    }
  }
}
```

- [x] **Step 2: Build the valid fixture**

Copy the required Markdown-plan sections and metadata shape from the valid
metadata fixture. Set the plan path to plans/revision-loop-plan.md, use one
phase with a real fixture file and a non-empty command, and create this
non-approved verdict:

```markdown
# ControlFlow Verify Verdict

**Status:** NEEDS_REVISION
**Failure Classification:** fixable

## Findings

- The test fixture requires one bounded revision.

## Score Breakdown

| Dimension | Score | Rationale |
| --- | --- | --- |
| completeness | 80/100 | Fixture is complete enough to revise. |
| executability | 80/100 | Command is declared. |
| dependency sanity | 80/100 | One phase has no dependency. |
| evidence readiness | 80/100 | Evidence is available. |
| risk handling | 80/100 | Risk rows are present. |

## Revision Patch Instructions

- Add the missing focused acceptance assertion in the stated test file.

## Evidence

- Fixture evidence.

## Recommendation

Revise the plan and verify it again.
```

Create the matching request with next_action equal to revise and one item that
targets the focused test path.

- [x] **Step 3: Write the failing focused test**

Create tests/revision-request.tests.ps1 with a helper that invokes the future
validator, captures output, and evaluates LASTEXITCODE after setting it to zero.
The initial missing-script assertion must fail:

```powershell
$validatorPath = Join-Path $repoRoot "scripts/validate-revision.ps1"
if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
    throw "Missing revision validator: $validatorPath"
}
```

After the validator exists, assert these cases:

```powershell
Assert-RevisionSucceeds "plans/revision-loop-plan.md" $fixtureRoot
Assert-RevisionSucceeds "plans/examples/bugfix-plan.md" $repoRoot
Assert-ApprovedWithRetainedRequestSucceeds $fixtureRoot
Assert-MutatedRequestFails "an action that conflicts with NEEDS_REVISION" {
    param($request)
    $request.next_action = "replan"
}
Assert-MutatedRequestFails "duplicate item ids" {
    param($request)
    $request.items += $request.items[0]
}
Assert-MutatedRequestFails "a mismatched plan path" {
    param($request)
    $request.plan_path = "plans/other-plan.md"
}
```

Register the new script in tests/run-contract-tests.ps1, run it, and record the
expected RED failure caused by the absent validator.

### Task 2: Implement the Deterministic Validator

**Files:**

- Create: scripts/validate-revision.ps1
- Test: tests/revision-request.tests.ps1

**Interfaces:**

- Consumes -RepoRoot and -PlanPath.
- Reads the matching plan.meta.json, verify-verdict.md, and optionally
  revision-request.json.
- Emits a valid-request line for non-approved verdicts or an
  approved-without-request line for an approved verdict.

- [x] **Step 1: Resolve the plan and validate existing artifacts**

Reuse the established PowerShell path shape:

```powershell
param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$PlanPath
)

$ErrorActionPreference = "Stop"
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
```

Invoke validate-plan.ps1 with RequirePlanMetadata and RequireVerifyVerdict;
throw when its exit code is non-zero. This keeps the existing
plan/metadata/verdict contract authoritative.

- [x] **Step 2: Parse and reconcile the request**

Implement helpers equivalent to Get-JsonProperty and Assert-NonEmptyString,
preserving arrays with Write-Output -NoEnumerate. Parse verdict values with
these patterns, using character class x60 so the script accepts optional
Markdown backticks:

```powershell
$statusMatch = [regex]::Match(
    $verdictContent,
    '(?mi)^\*\*Status:\*\*\s*[\x60]?(APPROVED|NEEDS_REVISION|REJECTED)[\x60]?\s*$'
)
$classificationMatch = [regex]::Match(
    $verdictContent,
    '(?mi)^\*\*Failure Classification:\*\*\s*[\x60]?(fixable|needs_replan|escalate)[\x60]?\s*$'
)
```

For APPROVED, return the approved-without-request line when no request exists.
When a request exists, validate it as retained historical evidence without
using its action as the current verdict. For non-approved verdicts, require the
request file, parse its JSON, and require each schema field plus unique
non-empty item IDs.

- [x] **Step 3: Enforce artifact alignment and action mapping**

Use one expected-path and mapping block:

```powershell
$expectedPlanPath = $planResolved.Substring($repoRootResolved.Length).
    TrimStart([char]'\', [char]'/').Replace('\', '/')
$expectedVerdictPath = "plans/artifacts/$taskSlug/verify-verdict.md"
$allowedActions = @{
    "NEEDS_REVISION/fixable" = "revise"
    "REJECTED/needs_replan" = "replan"
    "REJECTED/escalate" = "escalate"
}
$mappingKey = "$verdictStatus/$failureClassification"
```

Require request paths and status/classification to equal the verdict values.
Reject unmapped combinations and a next_action that differs from the mapped
value. Do not read or execute any value as a command.

- [x] **Step 4: Run GREEN in both shells**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/revision-request.tests.ps1
pwsh -NoProfile -File tests/revision-request.tests.ps1
```

Expected: both output VALID revision request contract.

### Task 3: Document the Loop and Protect Its Boundary

**Files:**

- Modify: skills/controlflow-plan/SKILL.md
- Modify: skills/controlflow-verify/SKILL.md
- Modify: README.md
- Modify: CHANGELOG.md
- Modify: tests/controlflow-skill-contract.tests.ps1
- Test: tests/controlflow-skill-contract.tests.ps1

**Interfaces:**

- Planner consumes revision-request.json only after a non-approved verdict.
- Verifier writes the request and runs the new validator.
- Neither skill automatically edits plan artifacts.

- [x] **Step 1: Add failing wording assertions**

Add stable contract checks:

```powershell
Assert-Contains $plan "revision-request.json" "plan revision request artifact"
Assert-Contains $plan "next_action" "plan revision action"
Assert-Contains $verify "validate-revision.ps1" "verify revision validator"
Assert-Contains $verify "does not apply plan changes automatically" "verify revision boundary"
Assert-Contains $readme "Revision loop" "README revision section"
```

Run the skill contract test and confirm RED before changing documentation.

- [x] **Step 2: Add minimum workflow wording**

In the verifier, require a request for non-approved verdicts and validate it.
In the planner, consume next_action: revise only for revise; replan or
escalate through the native host for the other actions; rerun validate, score,
and verify after any revision. In README, document this command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate-revision.ps1 -RepoRoot . -PlanPath plans/my-task-plan.md
```

State that the loop records and validates a handoff, but does not apply plan
changes automatically. Add the script to the repository layout and a concise
Unreleased changelog entry.

- [x] **Step 3: Verify GREEN**

Run the skill contract test again. Expected: VALID skill behavior contract.

### Task 4: Full Verification and Artifact Handoff

**Files:**

- Modify: docs/superpowers/specs/2026-07-12-revision-loop-design.md only if
  implementation reveals a necessary design correction.
- Test: all contract tests.

- [x] **Step 1: Run final verification**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/run-contract-tests.ps1 -UsePester
pwsh -NoProfile -File tests/run-contract-tests.ps1
git diff --check
```

Expected: both runners end in VALID ControlFlow contract suite; whitespace
check exits zero.

- [x] **Step 2: Check planned scope**

Confirm every changed path is listed in this plan. Re-run detect-drift.ps1 only
when a context snapshot exists for this feature; otherwise record that this
repository-maintenance task has no task snapshot.

- [x] **Step 3: Request independent review and commit**

Request a read-only review of the validator, fixtures, and skill wording. Fix
all Critical and Important findings, rerun Step 1, and commit the exact files
listed in the File Structure table with commit message feat: add revision loop.

## Plan Self-Review

- Spec coverage: Tasks 1-2 implement every artifact, mapping, and non-automation
  rule in the approved design; Task 3 exposes the workflow; Task 4 verifies it.
- Placeholder scan: no deferred work markers or unspecified validation behavior.
- Interface consistency: every artifact path derives from the same task slug;
  the schema enums, validator mapping, fixture, and skill wording use the same
  status, classification, and action names.
