# Plan: Bugfix Example

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** SMALL
**Confidence:** 0.90
**Abstain:** false
**Summary:** Add a regression check for a validator failure while preserving existing plan behavior.

## Context & Analysis

Goal Statement: Reject a validator input that references an unknown phase dependency.

## Design Decisions

- Add a focused negative test before changing the validator.

## Implementation Phases

### Phase 1 - Regression Test and Fix

Objective: Prove the validator rejects the unknown dependency and preserve valid inputs.

## Inter-Phase Contracts

- The test supplies the failing metadata fixture before the validator is changed.

## Open Questions

- None.

## Risks

- The failure assertion must distinguish an invalid dependency from a malformed plan.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | Fixture only. | No action. |
| performance | not_applicable | LOW | One validator call. | No action. |
| concurrency | not_applicable | LOW | No runtime. | No action. |
| access_control | not_applicable | LOW | No external access. | No action. |
| migration_rollback | not_applicable | LOW | No migration. | No action. |
| dependency | not_applicable | LOW | Existing PowerShell only. | No action. |
| operability | applicable | LOW | Validator contract changes. | Run regression test. |

## Success Criteria

- Unknown metadata phase dependencies fail deterministically.

## Handoff

Saved plan path: `plans/examples/bugfix-plan.md`

## Notes for Execution

- Run the focused PowerShell test before and after the fix.

## Progress

- Example prepared.

## Discoveries

- The validator already has a focused metadata test entry point.

## Decision Log

- Keep the example to one phase.

## Outcomes

- Pending example execution.

## Idempotence & Recovery

- Re-running the test is safe.
