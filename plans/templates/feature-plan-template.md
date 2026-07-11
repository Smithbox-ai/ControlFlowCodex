# Plan: Feature Template

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** MEDIUM
**Confidence:** 0.80
**Abstain:** false
**Summary:** Deliver requested behavior through a measurable acceptance criterion and focused test.

## Context & Analysis

Goal Statement: <USER-FACING GOAL>

Task-Type Invariant: Connect requested behavior to a measurable acceptance criterion.

Verified evidence: <VERIFIED FILE>

## Design Decisions

- Start from one failing acceptance test and avoid speculative extension points.

## Implementation Phases

### Phase 1 - Acceptance Behavior

Objective: Add requested behavior from one failing acceptance test.

## Inter-Phase Contracts

- The acceptance test names the behavior later phases must preserve.

## Open Questions

- <OPEN QUESTION OR NONE>

## Risks

- An unmeasurable criterion can expand feature scope without evidence.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | <VERIFIED FILE> | No data change unless evidence says otherwise. |
| performance | applicable | LOW | <VERIFIED FILE> | Add a proportional performance gate. |
| concurrency | not_applicable | LOW | <VERIFIED FILE> | Verify if shared state is introduced. |
| access_control | not_applicable | LOW | <VERIFIED FILE> | Preserve existing authorization boundaries. |
| migration_rollback | not_applicable | LOW | <VERIFIED FILE> | Revert focused feature files if required. |
| dependency | not_applicable | LOW | <VERIFIED FILE> | Prefer installed or native capabilities. |
| operability | applicable | MEDIUM | <EXACT COMMAND> | Run focused and full acceptance evidence. |

## Success Criteria

- A focused test and full contract suite prove the behavior.

## Handoff

Saved plan path: `plans/<task>-plan.md`

## Notes for Execution

- Run <EXACT COMMAND> before and after the minimum implementation.

## Progress

- Template copied; replace all authoring markers with repository evidence.

## Discoveries

- <DISCOVERY>

## Decision Log

- Keep behavior inside the approved acceptance criterion.

## Outcomes

- Pending execution.

## Idempotence & Recovery

- Re-running focused acceptance tests is safe.
