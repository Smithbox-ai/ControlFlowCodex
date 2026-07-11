# Plan: Bugfix Template

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** SMALL
**Confidence:** 0.80
**Abstain:** false
**Summary:** Correct a verified regression with the smallest behavior-preserving change.

## Context & Analysis

Goal Statement: <USER-FACING GOAL>

Task-Type Invariant: Reproduce the observed regression before implementation.

Verified evidence: <VERIFIED FILE>

## Design Decisions

- Preserve existing behavior outside the reproduced regression.

## Implementation Phases

### Phase 1 - Reproduce and Correct

Objective: Demonstrate the regression, then implement the smallest correction.

## Inter-Phase Contracts

- The regression test proves the behavior before and after the correction.

## Open Questions

- <OPEN QUESTION OR NONE>

## Risks

- An incomplete regression test could prove the wrong behavior.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | <VERIFIED FILE> | No data change. |
| performance | not_applicable | LOW | <VERIFIED FILE> | No performance change expected. |
| concurrency | not_applicable | LOW | <VERIFIED FILE> | No concurrent behavior changed. |
| access_control | not_applicable | LOW | <VERIFIED FILE> | No access boundary changed. |
| migration_rollback | not_applicable | LOW | <VERIFIED FILE> | Revert the focused correction if required. |
| dependency | not_applicable | LOW | <VERIFIED FILE> | No dependency change. |
| operability | applicable | LOW | <EXACT COMMAND> | Run the regression and full suite. |

## Success Criteria

- A focused regression test fails before and passes after the correction.

## Handoff

Saved plan path: `plans/<task>-plan.md`

## Notes for Execution

- Run <EXACT COMMAND> before and after implementation.

## Progress

- Template copied; replace all authoring markers with repository evidence.

## Discoveries

- <DISCOVERY>

## Decision Log

- Use the smallest correction supported by the regression test.

## Outcomes

- Pending execution.

## Idempotence & Recovery

- Re-running the regression test is safe.
