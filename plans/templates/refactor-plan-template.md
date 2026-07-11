# Plan: Refactor Template

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** SMALL
**Confidence:** 0.80
**Abstain:** false
**Summary:** Simplify a verified implementation while preserving observable behavior.

## Context & Analysis

Goal Statement: <USER-FACING GOAL>

Task-Type Invariant: Characterize and preserve behavior before structural change.

Verified evidence: <VERIFIED FILE>

## Design Decisions

- Change one selected structure only after characterizing its behavior.

## Implementation Phases

### Phase 1 - Characterize and Simplify

Objective: Capture current behavior, then simplify one selected structure.

## Inter-Phase Contracts

- Characterization tests define the behavior the refactor preserves.

## Open Questions

- <OPEN QUESTION OR NONE>

## Risks

- Structural cleanup can change behavior without a characterization test.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | <VERIFIED FILE> | No data change. |
| performance | applicable | LOW | <VERIFIED FILE> | Compare behavior without adding overhead. |
| concurrency | not_applicable | LOW | <VERIFIED FILE> | No concurrent behavior changed. |
| access_control | not_applicable | LOW | <VERIFIED FILE> | No access boundary changed. |
| migration_rollback | not_applicable | LOW | <VERIFIED FILE> | Revert the focused refactor if required. |
| dependency | not_applicable | LOW | <VERIFIED FILE> | No dependency change. |
| operability | applicable | MEDIUM | <EXACT COMMAND> | Run characterization and full contract tests. |

## Success Criteria

- Characterization and full contract tests preserve behavior.

## Handoff

Saved plan path: `plans/<task>-plan.md`

## Notes for Execution

- Run <EXACT COMMAND> before and after the structural change.

## Progress

- Template copied; replace all authoring markers with repository evidence.

## Discoveries

- <DISCOVERY>

## Decision Log

- Prefer deletion or inlining over a new abstraction.

## Outcomes

- Pending execution.

## Idempotence & Recovery

- Characterization tests are safe to re-run.
