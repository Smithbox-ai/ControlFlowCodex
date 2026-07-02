# Plan: Feedback Loop Contract

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** SMALL
**Confidence:** 0.87
**Abstain:** false
**Summary:** Strengthen the ControlFlow-for-Codex plugin contract so it explicitly preserves a feedback loop: clarify insufficient context, state the user-facing goal, define measurable success criteria, verify those plan fields before implementation, and review final evidence against them.

## Context & Analysis

Verified repository facts:

- The repository exposes three skills under `skills/`: `controlflow-plan`, `controlflow-verify`, and `controlflow-review`.
- `README.md` documents the intended loop as clarify, plan, verify, execute, review, done.
- `skills/controlflow-plan/SKILL.md` already requires `## Open Questions`, `## Success Criteria`, phase objectives, measurable acceptance criteria, and non-ready outcomes.
- `skills/controlflow-verify/SKILL.md` already checks clear objectives and measurable acceptance criteria.
- `skills/controlflow-review/SKILL.md` already compares the aggregate diff to the approved plan and evidence.
- `tests/controlflow-skill-contract.tests.ps1` currently covers abstraction and documentation guardrails, but not an explicit feedback-loop contract.
- `scripts/validate-plan.ps1` validates plan shape and optional verify-verdict shape.

Assumption:

- The requested project behavior should be enforced through skill text and contract tests because this plugin has no runtime beyond PowerShell validators and skill instructions.

## Design Decisions

- Use the existing single-file skill contract pattern instead of adding runtime orchestration.
- Add explicit feedback-loop language to the skills where it affects behavior: plan owns goal and criteria, verify checks them, review closes implementation evidence against them.
- Add contract-test assertions for stable phrases rather than building a parser for natural-language skill behavior.
- Keep README changes descriptive and aligned with the existing "native Codex owns clarification/execution" boundary.

## Implementation Phases

### Phase 1 - Contract Test

Objective: Add a failing test that proves the repository lacks an enforced feedback-loop contract.

Executor role: Contract Test Editor

Wave: 1

Dependencies: none

Concrete files and actions:

- Update `tests/controlflow-skill-contract.tests.ps1` with assertions for goal statement, clarifying questions, success criteria, verification gates, and review evidence closure.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\controlflow-skill-contract.tests.ps1`

Measurable acceptance criteria:

- The test fails before skill text is updated because at least one required feedback-loop phrase is absent.
- The failure identifies a missing feedback-loop label.

Quality gates:

- tests_pass: false is expected during RED, then true after Phase 2.
- lint_clean: not applicable; PowerShell parser errors are treated as test failures.
- schema_valid: not applicable in this phase.
- safety_clear: true; no destructive action.
- human_approved_if_required: not required.

Failure expectations:

- fixable: assertion wording is too brittle or misses the intended files.
- needs_replan: the behavior must be implemented by code rather than skills.
- transient: shell execution environment temporarily unavailable.
- escalate: workspace write access unavailable.

Numbered steps:

1. Add focused `Assert-Contains` calls for the feedback-loop contract.
2. Run the contract test and confirm it fails for missing behavior, not syntax.

### Phase 2 - Skill and README Contract

Objective: Update the plugin contract so plans explicitly state the goal, success criteria, and clarification loop, and downstream verification/review must check them.

Executor role: Skill Contract Editor

Wave: 2

Dependencies: Phase 1

Concrete files and actions:

- Update `skills/controlflow-plan/SKILL.md` to require a `Goal Statement`, use open questions to ask clarifying questions or abstain/replan, and tie success criteria to the goal.
- Update `skills/controlflow-verify/SKILL.md` to reject plans missing the user-facing goal, unresolved clarifying questions, or measurable success criteria.
- Update `skills/controlflow-review/SKILL.md` to compare implementation and test evidence against the goal and success criteria.
- Update `README.md` to name the feedback loop in the public project description.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File tests\controlflow-skill-contract.tests.ps1`

Measurable acceptance criteria:

- Skill text includes stable feedback-loop contract phrases asserted by the test.
- README describes the loop without implying the plugin owns Codex runtime state or user interaction mechanisms.

Quality gates:

- tests_pass: true after Phase 2.
- lint_clean: not applicable; markdown-only edits plus PowerShell test.
- schema_valid: not applicable in this phase.
- safety_clear: true; no destructive action.
- human_approved_if_required: not required.

Failure expectations:

- fixable: test phrases need to be aligned with concise skill wording.
- needs_replan: adding explicit goal criteria conflicts with existing plan schema.
- transient: command execution temporarily unavailable.
- escalate: workspace write access unavailable.

Numbered steps:

1. Make the minimum text edits in each skill.
2. Keep the native host boundary intact.
3. Run the contract test and adjust wording only if the intent remains the same.

### Phase 3 - Verification and Handoff

Objective: Validate the saved plan and final contract changes with repository commands.

Executor role: Verification Runner

Wave: 3

Dependencies: Phase 2

Concrete files and actions:

- Write `plans/artifacts/feedback-loop-contract/verify-verdict.md` after inline plan verification.
- Run `scripts/validate-plan.ps1` on the saved plan with `-RequireVerifyVerdict`.
- Run the full existing contract test.
- Inspect `git diff --stat` and summarize changed files.

Tests and exact commands:

- `powershell -ExecutionPolicy Bypass -File scripts\validate-plan.ps1 -RepoRoot . -PlanPath plans\feedback-loop-contract-plan.md -RequireVerifyVerdict`
- `powershell -ExecutionPolicy Bypass -File tests\controlflow-skill-contract.tests.ps1`
- `git diff --stat`

Measurable acceptance criteria:

- Plan validation exits 0.
- Contract test exits 0.
- Final summary states the exact commands run and any residual risk.

Quality gates:

- tests_pass: true.
- lint_clean: not applicable; no project linter exists.
- schema_valid: true via `validate-plan.ps1`.
- safety_clear: true.
- human_approved_if_required: not required.

Failure expectations:

- fixable: validator flags missing plan shape fields.
- needs_replan: verification finds the plan omits a requested outcome.
- transient: PowerShell execution unavailable.
- escalate: workspace permissions block artifact writes.

Numbered steps:

1. Complete inline ControlFlow verification and save the verdict.
2. Run validator and contract test.
3. Review final diff and prepare the handoff.

Dependency DAG:

flowchart TD
    P1["Phase 1 Contract Test"] --> P2["Phase 2 Skill and README Contract"]
    P2 --> P3["Phase 3 Verification and Handoff"]

## Inter-Phase Contracts

- Phase 1 produces a RED test failure that Phase 2 must satisfy without deleting the assertion intent.
- Phase 2 must not add plugin-owned runtime controls; it only updates skill and documentation contracts.
- Phase 3 validates the plan artifact and the repository contract test before reporting completion.

## Open Questions

- None blocking. If the desired "feedback loop" means a runtime conversation manager rather than skill-level behavior, this plan would need re-scope, but repository evidence shows the plugin intentionally avoids runtime orchestration.

## Risks

- Wording-only enforcement can drift if future edits bypass tests.
- Tests based on exact phrases can become brittle, so assertions should use durable contract phrases rather than full paragraphs.
- Overstating plugin ownership could conflict with the native Codex boundary.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | README and scripts show no data-processing runtime. | No additional gate needed. |
| performance | not_applicable | LOW | Changes are markdown and one small PowerShell test. | No additional gate needed. |
| concurrency | not_applicable | LOW | Plugin has no concurrent runtime or scheduler. | No additional gate needed. |
| access_control | not_applicable | LOW | README and skills defer approvals and sandboxing to Codex. | Preserve native host boundary wording. |
| migration_rollback | not_applicable | LOW | No schema migration or persisted application data. | Git diff is sufficient rollback path. |
| dependency | not_applicable | LOW | No new dependencies planned; PowerShell scripts already exist. | Use existing test command only. |
| operability | applicable | MEDIUM | Skill contracts are the plugin's operational behavior surface. | Add contract tests and README wording. |

## Success Criteria

- The project explicitly names a feedback loop from clarification to goal, measurable success criteria, verification, and review.
- `controlflow-plan` requires a user-facing goal statement, clarifying questions or abstain/replan when context is insufficient, and success criteria tied to the goal.
- `controlflow-verify` checks that the goal, questions, and criteria are execution-ready.
- `controlflow-review` checks final implementation and evidence against the goal and success criteria.
- Repository tests enforce these behavior contracts.
- Plan validation and contract tests pass.

## Handoff

Saved plan path: `plans/feedback-loop-contract-plan.md`

## Notes for Execution

- Keep edits surgical and in the existing markdown style.
- Use the existing PowerShell contract-test approach.
- Do not add runtime agents, routers, or state machines.

## Progress

- Phase 1 complete: contract test assertions were added and failed on the missing
  `Feedback Loop Contract` phrase.
- Phase 2 complete: `README.md` and the three ControlFlow skill files were
  updated with the feedback-loop contract.
- Phase 3 complete: final validation commands passed.

## Discoveries

- The active repository does not contain `schemas/planner.plan.schema.json` or `plans/templates/plan-document-template.md`, so the bundled standalone format applies.
- The existing contract test passed before this task, but it only covered
  abstraction and documentation guardrails, not the feedback-loop behavior.

## Decision Log

- Decided to enforce the requested behavior through skills and tests rather than runtime code because the repository intentionally ships no runtime orchestration layer.
- Confirmed the RED test failure before updating skill text, then kept the
  implementation to stable markdown contract phrases asserted by the test.

## Outcomes

- `controlflow-plan` now requires a `Goal Statement`, clarifying questions or a
  non-ready status for ambiguity, and measurable success criteria tied to the
  goal.
- `controlflow-verify` now checks the user-facing goal statement, unresolved
  clarifying questions, and measurable criteria before implementation.
- `controlflow-review` now closes the feedback loop by comparing implementation,
  tests, and evidence with the approved goal and success criteria.
- `README.md` now describes the project feedback loop explicitly.
- `powershell -ExecutionPolicy Bypass -File scripts\validate-plan.ps1 -RepoRoot . -PlanPath plans\feedback-loop-contract-plan.md -RequireVerifyVerdict` passed.
- `powershell -ExecutionPolicy Bypass -File tests\controlflow-skill-contract.tests.ps1` passed.
- `git diff --check` exited 0; Git emitted line-ending normalization warnings for
  tracked files.

## Idempotence & Recovery

- Re-running the contract test and plan validator is safe.
- If text edits produce an unintended contract, revert only the lines changed for this task and rerun the same commands.
