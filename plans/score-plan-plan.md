# Plan: Deterministic Score Plan

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** MEDIUM
**Confidence:** 0.90
**Abstain:** false
**Summary:** Add a dependency-free PowerShell scorer that reads a ControlFlow Markdown plan, its structured sidecar, and verifier verdict to calculate six deterministic quality metrics, an aggregate score, a verdict, and machine-readable JSON evidence.

## Context & Analysis

Goal Statement: Give ControlFlow a deterministic score-plan command that turns the existing plan, sidecar, and verdict contracts into reproducible aggregate metrics. The scorer supplements, rather than replaces, the verifier's adversarial rubric and native Codex execution decisions.

Verified facts:

- `scripts/validate-plan.ps1` already establishes the plan, sidecar, risk, dependency, and verdict contracts in PowerShell without external dependencies.
- Every golden example has a Markdown plan, `plan.meta.json`, and a verifier verdict; `bugfix` is a valid, minimal positive scoring fixture.
- `tests/fixtures/plan-metadata` contains a structurally valid plan and an invalid plan with an unknown phase dependency, suitable for a negative scoring fixture.
- `tests/run-contract-tests.ps1` is the portable suite entry point and is already covered by Pester.
- The plugin boundary forbids adding a runtime router, approval engine, or subagent lifecycle.

## Design Decisions

- Add `scripts/score-plan.ps1` rather than extend `validate-plan.ps1`; validation stays pass/fail while scoring supplies diagnostics and aggregate evidence.
- Require `-RepoRoot` and `-PlanPath`, write one JSON result to standard output, and add optional `-OutputPath` only if it can write the same result without changing stdout.
- Score six dimensions from observable artifacts: `completeness`, `executability`, `criteria_coverage`, `dependency_sanity`, `risk_coverage`, and `evidence_readiness`.
- Calculate `aggregate_score` as the rounded arithmetic mean of the six 0–100 metric scores.
- Return `APPROVED` only when every metric is at least 80; return `NEEDS_REVISION` when aggregate score is at least 50 but the approval gate fails; otherwise return `REJECTED`.
- Do not execute plan commands. Executability is scored from declared command coverage and the existence ratio of declared repository files.

## Implementation Phases

### Phase 1 - Scoring Contract Test

Objective: Define the public JSON output and prove the scorer is initially absent.

Executor role: Contract Test Editor

Wave: 1

Dependencies: none

Concrete files and actions:

- Create `tests/score-plan.tests.ps1` with positive assertions for `plans/examples/bugfix-plan.md` and negative assertions for `tests/fixtures/plan-metadata/plans/invalid-metadata-plan.md`.
- Modify `tests/run-contract-tests.ps1` to execute the new standalone score test.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\score-plan.tests.ps1`

Measurable acceptance criteria:

- The initial test fails because `scripts/score-plan.ps1` does not exist.
- The positive assertion requires six named metrics, an integer aggregate score, and `APPROVED` verdict.
- The invalid dependency assertion requires `dependency_sanity` below 100 and a non-approved verdict.

Quality gates:

- tests_pass: false during RED, then true after Phase 2.
- lint_clean: PowerShell parser errors fail the test.
- schema_valid: JSON output must parse with `ConvertFrom-Json`.
- safety_clear: true; scorer reads artifacts and never executes plan commands.
- human_approved_if_required: satisfied by the user's explicit score-plan request.

Failure expectations:

- fixable: output fields or score thresholds disagree with the contract.
- needs_replan: a metric requires executing arbitrary plan commands.
- transient: PowerShell unavailable.
- escalate: worktree write access unavailable.

Numbered steps:

1. Add the focused test before production scorer code.
2. Run it and record the missing scorer failure.
3. Keep test fixtures isolated from the user-facing golden plans.

### Phase 2 - Deterministic Scorer

Objective: Implement the six metrics, aggregate score, diagnostic issues, and deterministic verdict.

Executor role: PowerShell Scorer Editor

Wave: 2

Dependencies: Phase 1

Concrete files and actions:

- Create `scripts/score-plan.ps1`.
- Parse Markdown plan headings, the matching `plans/artifacts/<slug>/plan.meta.json`, and optional matching verifier verdict.
- Emit one JSON object with `plan_path`, `task_slug`, `aggregate_score`, `verdict`, `metrics`, and `issues`.

Metric definitions:

- `completeness`: every required Markdown header, goal statement, at least one phase heading, and top-level success criterion are present; score is the fulfilled-check percentage.
- `executability`: average of declared-file existence percentage and non-empty phase-command coverage percentage; no command is run.
- `criteria_coverage`: percentage of metadata phases with at least one non-empty phase criterion, combined with non-empty top-level criteria.
- `dependency_sanity`: 100 only when every dependency names another phase, no phase depends on itself, and the directed graph has no cycle; otherwise 0.
- `risk_coverage`: percentage of the seven required categories appearing exactly once in metadata; an unsupported category or malformed applicability or impact yields zero.
- `evidence_readiness`: 100 only when a verifier verdict exists with `APPROVED` status plus Findings, Score Breakdown, Evidence, and Recommendation headings; otherwise 0.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\score-plan.tests.ps1`
- `pwsh -NoProfile -File tests\score-plan.tests.ps1`

Measurable acceptance criteria:

- The bugfix golden plan scores 100 and returns `APPROVED`.
- The invalid-dependency fixture returns a non-approved verdict and zero `dependency_sanity`.
- Output is valid JSON in Windows PowerShell and PowerShell 7.

Quality gates:

- tests_pass: true.
- lint_clean: PowerShell parser accepts the script.
- schema_valid: emitted JSON parses with `ConvertFrom-Json`.
- safety_clear: true; no plan command execution.
- human_approved_if_required: satisfied.

Failure expectations:

- fixable: PowerShell JSON arrays are scalarized or a percentage divisor is zero.
- needs_replan: a metric cannot be derived from the current artifact contract.
- transient: shell execution failure unrelated to repository files.
- escalate: output path cannot be written when explicitly requested.

Numbered steps:

1. Implement read-only helpers for path resolution, JSON properties, score clamping, and issue collection.
2. Compute each metric from the specified artifacts without sourcing `validate-plan.ps1` or executing declared commands.
3. Apply aggregate and verdict thresholds, serialize a single JSON result, and rerun both test shells.

### Phase 3 - Public Scoring Contract

Objective: Make scoring discoverable in the planner, verifier, README, and contract suite.

Executor role: Skill Contract Editor

Wave: 3

Dependencies: Phase 2

Concrete files and actions:

- Modify `skills/controlflow-plan/SKILL.md` to name deterministic scoring after metadata validation.
- Modify `skills/controlflow-verify/SKILL.md` to treat `score-plan` JSON as evidence, not as a replacement for adversarial analysis.
- Modify `README.md` and `CHANGELOG.md` to document score inputs, six metrics, JSON output, and no-command-execution boundary.
- Modify `tests/controlflow-skill-contract.tests.ps1` with stable scorer wording assertions.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\controlflow-skill-contract.tests.ps1`

Measurable acceptance criteria:

- Documentation names `scripts/score-plan.ps1`, all six metrics, and the fact that scorer output is deterministic evidence rather than runtime orchestration.
- The verifier instructions preserve the distinction between score and adversarial verdict.

Quality gates:

- tests_pass: true.
- lint_clean: Markdown contract assertions pass.
- schema_valid: documented score output parses in the scorer test.
- safety_clear: true.
- human_approved_if_required: satisfied.

Failure expectations:

- fixable: phrase assertions are too brittle.
- needs_replan: public documentation requires unsupported automatic scoring behavior.
- transient: PowerShell unavailable.
- escalate: writes blocked.

Numbered steps:

1. Add failing stable contract assertions for scorer location, metrics, and boundary.
2. Add minimum skill and README wording after the scorer passes.
3. Run the skill contract test and avoid unrelated documentation cleanup.

### Phase 4 - Full Verification and Review

Objective: Prove the score-plan contract is portable, scoped, and consistent with the approved goal.

Executor role: Verification Runner

Wave: 4

Dependencies: Phases 1 through 3

Concrete files and actions:

- Run the full standalone/Pester suite in Windows PowerShell and the portable suite in PowerShell 7.
- Inspect aggregate changed paths against this plan.
- Update this plan's lifecycle sections and `plans/artifacts/score-plan/verify-verdict.md` with final evidence.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\run-contract-tests.ps1 -UsePester`
- `pwsh -NoProfile -File tests\run-contract-tests.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts\score-plan.ps1 -RepoRoot . -PlanPath plans\examples\bugfix-plan.md`
- `git diff --check`

Measurable acceptance criteria:

- All tests pass with `VALID ControlFlow contract suite`.
- Golden bugfix JSON reports `APPROVED` and an aggregate score of 100.
- Final review finds no unplanned runtime, dependency, or command-execution behavior.

Quality gates:

- tests_pass: true.
- lint_clean: `git diff --check` exits 0.
- schema_valid: scorer output and sidecars parse as JSON.
- safety_clear: true.
- human_approved_if_required: satisfied.

Failure expectations:

- fixable: contract test or scorer output disagrees with the declared threshold.
- needs_replan: required metric needs data unavailable in current artifacts.
- transient: external shell failure.
- escalate: sandbox permissions block verification.

Numbered steps:

1. Run every specified command after the final change.
2. Review changed paths against the four phases.
3. Record evidence and residual limitations for future score metric changes.

Dependency DAG:

flowchart TD
    P1["Phase 1 RED score test"] --> P2["Phase 2 deterministic scorer"]
    P2 --> P3["Phase 3 skill and README contract"]
    P3 --> P4["Phase 4 verification and review"]

## Inter-Phase Contracts

- Phase 1 defines the JSON fields and expected positive/negative scoring behavior that Phase 2 implements.
- Phase 2 exposes a dependency-free read-only command consumed by Phase 3 documentation.
- Phase 3 cannot imply that aggregate scoring owns native Codex decisions.
- Phase 4 verifies the golden positive case, invalid dependency case, portable tests, and changed-path scope.

## Open Questions

- None blocking. `-OutputPath` remains optional and must not alter standard-output JSON if included during implementation.

## Risks

- Scores can look authoritative despite being artifact-derived; documentation must retain verifier and human judgment boundaries.
- Metadata may list future files that do not exist yet; executability intentionally reports that evidence rather than failing the command.
- A scorer that executes plan commands would violate safety and determinism; the command never executes them.
- Adding a second validation implementation can drift from the existing validator; metric definitions stay deliberately read-only and limited.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | Plan, sidecar, and verdict are compact text artifacts. | Read in memory; no storage service. |
| performance | applicable | LOW | Scorer reads one plan, sidecar, and verdict. | Use linear scans and no external process per declared command. |
| concurrency | not_applicable | LOW | Script has no shared runtime state. | Emit one independent JSON result. |
| access_control | not_applicable | LOW | Scorer reads only repository paths supplied by caller. | Preserve native host sandbox and approvals. |
| migration_rollback | not_applicable | LOW | No migration or persisted user-data change. | Remove scorer script to roll back. |
| dependency | not_applicable | LOW | Use PowerShell standard JSON and filesystem APIs only. | Add no module or package. |
| operability | applicable | MEDIUM | Score output becomes CI and review evidence. | Cover positive and invalid fixtures in both PowerShell shells. |

## Success Criteria

- `scripts/score-plan.ps1` emits one parseable JSON object with six named metrics, aggregate score, deterministic verdict, and diagnostic issues.
- A valid golden plan scores 100 and `APPROVED`; an unknown dependency scores zero on `dependency_sanity` and is not approved.
- The scorer never executes declared plan commands and adds no dependencies or plugin runtime.
- Planner, verifier, README, changelog, runner, and contract tests explain and enforce the scoring boundary.
- Windows PowerShell/Pester and PowerShell 7 full suites pass.

## Handoff

Saved plan path: `plans/score-plan-plan.md`

## Notes for Execution

- Write the scorer test first and observe the missing-command failure.
- Keep all score output deterministic from repository artifacts; do not invoke AI or external services.
- Treat missing sidecar or verdict as metric evidence and a non-approved verdict, not a script crash.

## Progress

- Phase 1 completed: RED test recorded the absent score-plan script, then joined
  the portable contract runner.
- Phase 2 completed: the scorer emits exactly one JSON object and passes in
  Windows PowerShell and PowerShell 7.
- Phase 3 completed: planner, verifier, README, changelog, and stable wording
  contract describe scoring as evidence rather than orchestration.
- Phase 4 completed: full Pester and portable suites, artifact validation,
  golden scoring, and whitespace checks passed.

## Discoveries

- The bugfix golden plan has existing files, one phase, complete risk coverage, and an approved structured verdict, so it is the positive score fixture.
- The invalid metadata fixture provides an unknown dependency without requiring a destructive or synthetic project change.
- PowerShell returns a one-element JSON array as a scalar from a normal function
  return; JSON-property helpers must preserve arrays with NoEnumerate.
- PowerShell 7 leaves LASTEXITCODE unset after a PowerShell script invocation,
  so the focused test initializes it before every scorer invocation and checks
  the resulting code.
- Final adversarial review showed that aggregate approval must reject unsupported
  risk rows and incomplete lifecycle Markdown sections, not merely score their
  required siblings.
- Dependency fields must remain arrays through scoring: treating a malformed
  scalar as an empty list would incorrectly allow approval.

## Decision Log

- Use an independent scorer script instead of overloading the pass/fail validator.
- Use an equal-weight aggregate of six observable metrics rather than lexical similarity baselines.
- Gate `APPROVED` on every metric, so a high average cannot hide a missing dependency or evidence score.
- Keep plan-command coverage declarative: command strings are counted but never
  invoked.

## Outcomes

- Added the dependency-free score-plan command, focused positive and negative
  contract coverage, and runner integration.
- Added public scoring guidance with the six metrics, threshold rule, and
  adversarial-verification boundary.
- Verified the score-plan plan artifact and the bugfix golden result at 100 and
  APPROVED.
- Added regression coverage for unsupported and malformed risk rows, cyclic and
  self dependencies, incomplete Markdown, and the stable JSON error shape.
- Added regression coverage for scalar dependencies so malformed sidecars cannot
  silently become dependency-free plans.

## Idempotence & Recovery

- Scoring and all test commands are read-only.
- If thresholds prove unsuitable, revise the documented metric definition and its focused test together.
