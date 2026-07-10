# Plan: Plan Contract Foundation

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** MEDIUM
**Confidence:** 0.88
**Abstain:** false
**Summary:** Add a machine-readable sidecar contract for ControlFlow plans, deterministic validation, representative golden examples, an actionable verifier rubric, and cross-platform continuous integration while preserving the plugin as a thin quality layer over native Codex.

## Context & Analysis

Goal Statement: Turn the existing Markdown-only plan contract into an artifact-first, deterministically verifiable workflow. A plan remains readable Markdown, but it gains a validated JSON sidecar and reliable test/CI evidence without introducing an orchestration runtime, subagents, or mandatory runtime dependencies.

Verified repository facts:

- The repository is a skill-only plugin with three skills and a PowerShell validator.
- `scripts/validate-plan.ps1` validates Markdown headings, risk rows, and an optional verify verdict, but it has no sidecar metadata support.
- `tests/controlflow-skill-contract.tests.ps1` is a portable standalone PowerShell contract check.
- Pester 3.4.0 is available locally; the baseline standalone contract test and existing plan validation both pass.
- The root `README.md` establishes the boundary that native Codex owns execution, sandboxing, approvals, and subagent lifecycle.
- The approved research report recommends a sidecar schema, golden examples, verifier score breakdown and revision instructions, Pester-compatible tests, CI matrix, and installer smoke testing.

Assumptions:

- The first delivery implements the formalization, verifier-contract, test, and CI foundations; context extraction, automatic drift detection, release publishing, and multi-candidate planning remain later roadmap items.
- JSON Schema is the portable public contract; the existing PowerShell validator will enforce the supported invariant subset without adding a schema-engine dependency.

## Design Decisions

- Keep Markdown as the author-facing plan artifact and use `plans/artifacts/<task>/plan.meta.json` as its structured sidecar.
- Publish the sidecar shape under `schemas/plan-meta.schema.json` and retain the current bundled Markdown format as the fallback human contract.
- Extend the existing PowerShell validator rather than add a second executable runtime or third-party schema validator.
- Use five compact, real Markdown-plus-sidecar examples for bugfix, refactor, migration, feature, and docs/test-only planning patterns.
- Retain the standalone PowerShell checks as the dependency-free baseline, then add a Pester entry point and run both in CI.
- Make `$controlflow-verify` require an actionable score breakdown and revision patch instructions; update `$controlflow-review` to consume sidecar metadata for later scope reconciliation.

## Implementation Phases

### Phase 1 - Contract Tests and Metadata Schema

Objective: Define the sidecar's public JSON contract and create failing validation checks before changing production validation.

Executor role: Contract Test Editor

Wave: 1

Dependencies: none

Concrete files and actions:

- Create `schemas/plan-meta.schema.json` with schema version, plan path, goal, tier, phase, command, file, risk, and criterion requirements.
- Create `tests/validate-plan.tests.ps1` to exercise valid and invalid sidecar cases through the public validator command.
- Create `tests/fixtures/invalid-metadata/plans/invalid-metadata-plan.md` and its malformed `plans/artifacts/invalid-metadata/plan.meta.json` fixture.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\validate-plan.tests.ps1`

Measurable acceptance criteria:

- The new test fails against the current validator because it does not recognize the metadata requirement switch.
- The schema is valid JSON and declares all mandatory top-level fields.

Quality gates:

- tests_pass: false is expected during RED and true after Phase 2.
- lint_clean: PowerShell parse errors are test failures; JSON parsing must succeed.
- schema_valid: the schema parses with `ConvertFrom-Json`.
- safety_clear: true; fixtures do not access external state.
- human_approved_if_required: satisfied by the user's approved first-delivery scope.

Failure expectations:

- fixable: a schema field or test invocation disagrees with the intended public contract.
- needs_replan: enforcing the schema requires an external runtime dependency.
- transient: PowerShell is unavailable.
- escalate: worktree write access is unavailable.

Numbered steps:

1. Add only the validation test and schema shape first.
2. Run the standalone validation test and confirm the failure is the missing metadata capability.
3. Record the observed RED result before editing `validate-plan.ps1`.

### Phase 2 - Deterministic Sidecar Validation

Objective: Extend the existing validator to require and cross-check a valid sidecar when requested.

Executor role: PowerShell Validator Editor

Wave: 2

Dependencies: Phase 1

Concrete files and actions:

- Modify `scripts/validate-plan.ps1` to add `-RequirePlanMetadata` and validate JSON parsing, required fields, allowed tier/risk values, non-empty arrays, unique phase IDs, dependency references, and Markdown-to-sidecar goal/tier alignment.
- Modify `tests/validate-plan.tests.ps1` only if a test assertion needs the public error wording clarified.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\validate-plan.tests.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts\validate-plan.ps1 -RepoRoot . -PlanPath plans\feedback-loop-contract-plan.md`

Measurable acceptance criteria:

- A valid metadata sidecar passes with `-RequirePlanMetadata`.
- Missing goals, malformed JSON, unknown dependencies, or a tier mismatch fail with an explanatory error.
- Existing validation without `-RequirePlanMetadata` remains backward-compatible.

Quality gates:

- tests_pass: true.
- lint_clean: PowerShell parser accepts the modified script.
- schema_valid: schema and valid fixture parse as JSON.
- safety_clear: true; no destructive commands.
- human_approved_if_required: satisfied.

Failure expectations:

- fixable: a PowerShell object-property check mishandles a valid fixture.
- needs_replan: required data cannot be represented without weakening Markdown compatibility.
- transient: a shell execution failure unrelated to the script.
- escalate: scripts cannot write their temporary test directory.

Numbered steps:

1. Implement the smallest validator helpers needed for the schema invariant subset.
2. Run the RED test until it fails only for missing behavior, then rerun it after the implementation.
3. Re-run legacy validation without the new switch to prove compatibility.

### Phase 3 - Golden Plans and Sidecars

Objective: Add representative human-readable plans with matching structured metadata and approved verifier artifacts.

Executor role: Example Contract Editor

Wave: 3

Dependencies: Phase 2

Concrete files and actions:

- Create `plans/examples/bugfix-plan.md`, `plans/examples/refactor-plan.md`, `plans/examples/migration-plan.md`, `plans/examples/feature-plan.md`, and `plans/examples/docs-test-only-plan.md`.
- Create matching `plan.meta.json` and `verify-verdict.md` files under `plans/artifacts/`.
- Create `plans/artifacts/plan-contract-foundation/plan.meta.json` for this implementation plan once the contract exists.
- Extend `tests/validate-plan.tests.ps1` so every golden plan is validated with metadata and a verify verdict.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\validate-plan.tests.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts\validate-plan.ps1 -RepoRoot . -PlanPath plans\examples\bugfix-plan.md -RequirePlanMetadata -RequireVerifyVerdict`

Measurable acceptance criteria:

- Each of the five plan types has Markdown, a sidecar, and an approved verifier verdict.
- Every example passes the same public validator invocation.
- Golden examples cover a dependency-free change, a behavior change, a migration/rollback risk, a feature, and docs/test-only work.

Quality gates:

- tests_pass: true.
- lint_clean: Markdown and JSON do not contain malformed structural syntax.
- schema_valid: all five sidecars pass deterministic invariant validation.
- safety_clear: migration example is documentation-only and includes rollback evidence.
- human_approved_if_required: satisfied.

Failure expectations:

- fixable: a compact example omits a required Markdown or metadata field.
- needs_replan: one example cannot represent a supported planning pattern.
- transient: none expected.
- escalate: repository writes are blocked.

Numbered steps:

1. Start each example from the same required Markdown headings and keep each to one phase.
2. Write matching JSON sidecars with exact goal, tier, phase ID, paths, commands, risks, and criteria.
3. Add approved verdicts and validate all examples in one standalone test run.

### Phase 4 - Skill and Documentation Contract

Objective: Teach the planner, verifier, reviewer, and public documentation to use the artifact-first contract.

Executor role: Skill Contract Editor

Wave: 4

Dependencies: Phase 3

Concrete files and actions:

- Modify `skills/controlflow-plan/SKILL.md` to require Markdown plus sidecar artifacts and to point at the schema and examples.
- Modify `skills/controlflow-verify/SKILL.md` to require a score breakdown and revision patch instructions in every saved verdict.
- Modify `skills/controlflow-review/SKILL.md` to consume metadata for path and criterion comparison when it is present.
- Modify `README.md` and `CHANGELOG.md` to document the sidecar, validator option, test/CI surface, and native-host boundary.
- Extend `tests/controlflow-skill-contract.tests.ps1` with stable assertions for the new contracts.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\controlflow-skill-contract.tests.ps1`

Measurable acceptance criteria:

- The three skills describe a compatible `plan → metadata → verify → review` lifecycle.
- Verify verdict instructions require the five named score dimensions and actionable revision directions.
- Documentation states that sidecars and deterministic validation add quality checks, not execution orchestration.

Quality gates:

- tests_pass: true.
- lint_clean: Markdown contract tests pass.
- schema_valid: documented schema paths exist.
- safety_clear: true.
- human_approved_if_required: satisfied.

Failure expectations:

- fixable: assertions are too brittle or wording does not reflect the contract.
- needs_replan: skills require behavior not supported by the deterministic validator.
- transient: PowerShell command execution fails.
- escalate: writes cannot be persisted.

Numbered steps:

1. Add stable failing phrase assertions before skill wording changes.
2. Update only the affected skill sections while preserving native Codex ownership.
3. Update README and changelog after the contract test passes.

### Phase 5 - Pester Entry Point and CI Smoke Coverage

Objective: Make the portable checks observable through Pester and run the complete contract across supported GitHub-hosted operating systems.

Executor role: CI Test Editor

Wave: 5

Dependencies: Phases 2, 3, and 4

Concrete files and actions:

- Create `tests/controlflow-contract.Tests.ps1` with Pester test cases that invoke the standalone contract and metadata tests.
- Create `tests/run-contract-tests.ps1` as the documented entry point, with a switch that requires and invokes Pester.
- Create `.github/workflows/ci.yml` with push and pull-request triggers and an Ubuntu, Windows, macOS matrix.
- Extend the runner to smoke-test install and uninstall using a temporary `HomeRoot`.
- Modify `scripts/install.ps1` only if the smoke test exposes platform-specific path handling.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\run-contract-tests.ps1 -UsePester`
- `powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -HomeRoot $env:TEMP\controlflow-install-smoke -Force`
- `powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -HomeRoot $env:TEMP\controlflow-install-smoke -Uninstall -Force`

Measurable acceptance criteria:

- The Pester entry point passes locally with the available Pester 3.4.0.
- CI installs a current Pester release and passes the same tests on all three runner OSs.
- Installer smoke coverage asserts that install creates and uninstall removes the plugin and marketplace entry in a temporary home directory.

Quality gates:

- tests_pass: true.
- lint_clean: workflow YAML parses according to GitHub Actions conventions.
- schema_valid: CI validates every golden sidecar.
- safety_clear: installer smoke tests write only a temporary home directory.
- human_approved_if_required: satisfied.

Failure expectations:

- fixable: Pester syntax differs across supported versions or a path separator is not portable.
- needs_replan: CI requires a new package manager or runtime outside PowerShell Core.
- transient: GitHub marketplace installation is temporarily unavailable.
- escalate: local temporary-home cleanup is blocked.

Numbered steps:

1. Add the Pester test and runner first, then observe the expected RED failure for missing runner behavior.
2. Add only the runner and CI needed to run the existing dependency-free checks plus Pester.
3. Run local Pester and installer smoke checks before final validation.

### Phase 6 - Verification, Review, and Handoff

Objective: Produce evidence that the implementation meets the approved goal and update this living plan.

Executor role: Verification Runner

Wave: 6

Dependencies: Phases 1 through 5

Concrete files and actions:

- Update `plans/artifacts/plan-contract-foundation/verify-verdict.md` with the adversarial verification result and score breakdown.
- Update this plan's lifecycle sections with observed progress, decisions, outcomes, and recovery guidance.
- Inspect the aggregate diff for scope drift against the listed files.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\run-contract-tests.ps1 -UsePester`
- `powershell -ExecutionPolicy Bypass -File scripts\validate-plan.ps1 -RepoRoot . -PlanPath plans\plan-contract-foundation-plan.md -RequirePlanMetadata -RequireVerifyVerdict`
- `git diff --check`
- `git diff --stat`

Measurable acceptance criteria:

- All portable, Pester, validator, golden-example, and installer smoke tests pass.
- This plan, its sidecar, and its verifier verdict pass the public validator.
- Final review classifies each changed file as planned follow-through or an explained deviation.

Quality gates:

- tests_pass: true.
- lint_clean: `git diff --check` exits 0.
- schema_valid: this plan and every golden sidecar validate.
- safety_clear: true.
- human_approved_if_required: satisfied.

Failure expectations:

- fixable: an artifact or test command has a contract mismatch.
- needs_replan: verification requires material scope outside the approved foundation.
- transient: a tool execution failure without a repository cause.
- escalate: sandbox or worktree permissions block verification.

Numbered steps:

1. Execute all documented verification commands.
2. Reconcile changed paths with the approved phases.
3. Record residual limitations and a resumable recovery point.

Dependency DAG:

flowchart TD
    P1["Phase 1 Schema and RED tests"] --> P2["Phase 2 Sidecar validation"]
    P2 --> P3["Phase 3 Golden plans"]
    P3 --> P4["Phase 4 Skill contract"]
    P3 --> P5["Phase 5 Pester and CI"]
    P4 --> P6["Phase 6 Verification"]
    P5 --> P6

## Inter-Phase Contracts

- Phase 1 supplies an unambiguous public metadata shape and a failing behavioral test.
- Phase 2 keeps legacy Markdown validation operational when metadata is not required and exposes a stable `-RequirePlanMetadata` option for later phases.
- Phase 3 supplies valid sidecars and approved verdicts that Phase 4 documents and Phase 5 validates cross-platform.
- Phase 4 cannot introduce plugin-owned execution, approvals, subagents, or a router.
- Phase 5 executes only documented PowerShell, Pester, validator, and installer entry points.
- Phase 6 validates the plan created here with the contract added by Phase 2.

## Open Questions

- None blocking. The report's optional multi-candidate planning is intentionally deferred because it changes planning behavior rather than formalizing and validating the existing contract.

## Risks

- Markdown-to-JSON synchronization can become brittle if equality checks require prose beyond structured goal, tier, phases, and criteria.
- JSON Schema cannot be evaluated natively by the existing PowerShell runtime without a dependency, so the validator must state which invariant subset it enforces.
- Pester versions differ across local and hosted environments; tests must use broadly compatible constructs.
- Installer smoke tests must isolate writes to a temporary home root and never modify the developer's real marketplace.
- Five documented examples add maintenance surface, so each must be validated by a single shared test command.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | Plans, JSON sidecars, and examples are compact repository files. | No volume-specific mechanism required. |
| performance | applicable | LOW | Validator reads a plan, one sidecar, and a bounded set of examples. | Use linear parsing and avoid external schema engines. |
| concurrency | not_applicable | LOW | Plugin has no concurrent runtime; CI jobs are independently read/write isolated. | Preserve no-runtime boundary. |
| access_control | applicable | MEDIUM | Installer and smoke coverage touch plugin and marketplace paths. | Use a caller-supplied temporary `HomeRoot`; retain native Codex ownership of approvals. |
| migration_rollback | applicable | MEDIUM | A new metadata contract changes plan artifacts but not user data. | Keep metadata optional by default and retain Markdown-only validation compatibility. |
| dependency | applicable | MEDIUM | Pester is available in CI and locally but is not a plugin runtime dependency. | Preserve standalone tests and install Pester only in CI. |
| operability | applicable | HIGH | Skills and validator define the plugin's public quality workflow. | Cover schema, examples, verdict, installer, and CI paths with automated checks. |

## Success Criteria

- A Markdown plan can have a matching `plans/artifacts/<task>/plan.meta.json` sidecar that records goal, tier, phases, dependencies, files, commands, risks, and criteria.
- `schemas/plan-meta.schema.json` and `scripts/validate-plan.ps1 -RequirePlanMetadata` enforce the published metadata contract without external runtime dependencies.
- Five representative Markdown-plus-sidecar examples and their verifier verdicts pass the public validator.
- `$controlflow-plan`, `$controlflow-verify`, and `$controlflow-review` describe the same artifact-first lifecycle; verify instructions include score breakdown and revision patch directions.
- The repository provides both a standalone PowerShell test entry point and Pester coverage, and CI runs them plus installer smoke testing on Ubuntu, Windows, and macOS.
- Native Codex remains the owner of execution, approval, sandbox, routing, memory, and subagent lifecycle.

## Handoff

Saved plan path: `plans/plan-contract-foundation-plan.md`

## Notes for Execution

- Start every behavior change with its narrow standalone PowerShell test and observe a meaningful failure before modifying production logic.
- Prefer existing PowerShell and JSON facilities over a new validation dependency.
- Keep examples descriptive rather than executable migrations or project changes.
- Preserve the existing `-RequireVerifyVerdict` option and default behavior for legacy plans.

## Progress

- Phase 1 complete: `tests/validate-plan.tests.ps1` first failed because
  `-RequirePlanMetadata` did not exist; the metadata schema and fixture
  contract were then added.
- Phase 2 complete: `scripts/validate-plan.ps1` now validates an opt-in
  sidecar without changing the legacy command path. The valid fixture passes and
  the unknown dependency fixture fails as intended.
- Phase 3 complete: five Markdown-plus-metadata golden examples and their
  approved verifier verdicts pass one shared validation test.
- Phase 4 complete: planner, verifier, reviewer, README, changelog, and text
  contract tests now describe the artifact-first lifecycle.
- Phase 5 complete: the standalone runner, Pester entry point, temporary-home
  installer smoke test, and three-OS GitHub Actions workflow were added; the
  local Pester 3.4.0 run passes.
- Phase 6 complete: standalone and Pester suites, the plan's own sidecar/verdict
  validation, JSON schema parsing, and whitespace checks pass. Independent review
  found and verified fixes for PowerShell 7 scalar handling, Unix installer paths,
  structured verdict enforcement, and negative-case coverage.

## Discoveries

- The repository has no canonical repository-local schema/template override yet, so the current bundled Markdown format governs existing plans.
- The active PowerShell environment has Pester 3.4.0, so the Pester entry point must avoid version-specific assertions.
- The repository is a normal checkout on `main`; implementation is isolated in the linked `codex/plan-contract-foundation` worktree.
- PowerShell returns a one-element JSON array as a scalar when a helper uses
  plain `return`; `Write-Output -NoEnumerate` preserves the metadata array.
- In PowerShell strings, backslash is literal. Regex and character normalization
  must use one backslash, unlike C-style escaped string literals.
- PowerShell 7 wraps a scalar emitted with `Write-Output -NoEnumerate` in a list,
  so the helper applies no-enumeration only to JSON arrays.
- A cross-platform installer must build `.agents` and `plugins` with separate
  `Join-Path` calls; a literal backslash is a filename character on Unix.

## Decision Log

- Chose a JSON Schema plus deterministic PowerShell subset validation instead of a new schema-validation dependency to keep the plugin lightweight and portable.
- Chose five compact golden examples over a template library in this delivery because examples immediately support regression tests while templates need additional selection behavior.
- Deferred multi-candidate planning, automatic context snapshots, and automatic scope-drift detection because they exceed the approved first-delivery foundation.
- Kept `-RequirePlanMetadata` opt-in so existing Markdown-only plans retain
  their current validation behavior and have a clear rollback path.
- Used the existing standalone PowerShell checks as the CI foundation and made
  Pester an optional test-runner layer rather than a plugin dependency.
- Extended deterministic verdict validation beyond headings: every rubric row now
  needs a bounded numeric score or a confidence band, and revision instructions
  must contain guidance.

## Outcomes

- Phases 1 through 5 are complete. The repository now includes a JSON Schema,
  opt-in deterministic metadata validation, six validated sidecars (this plan
  plus five golden examples), aligned skill/documentation contracts, a Pester
  runner, installer smoke coverage, and cross-platform CI configuration.
- Phase 6 completed with full PowerShell and PowerShell 7 test runs, plan
  validation, whitespace validation, and independent plan-aware review. All
  changed paths are approved phase follow-through: documentation/contracts,
  validator/schema, golden artifacts, test coverage, installer portability, and
  CI. No scope drift remains.

## Idempotence & Recovery

- Every test and validator command in this plan is safe to re-run.
- If Phase 2 cannot remain backward-compatible, revert only the new sidecar switch and schema/test additions, then replan the metadata migration.
- If CI cannot obtain Pester, standalone PowerShell validation remains a deterministic local recovery path; record the external dependency failure rather than weakening the tests.
- Installer smoke coverage creates and removes only a GUID-named temporary home
  directory, so it is safe to re-run without touching the real marketplace.
