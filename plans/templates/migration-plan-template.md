# Plan: Migration Template

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** MEDIUM
**Confidence:** 0.75
**Abstain:** false
**Summary:** Deliver a compatible migration with explicit backup, rollback, and verification gates.

## Context & Analysis

Goal Statement: <USER-FACING GOAL>

Task-Type Invariant: State compatibility, backup or rollback, and safety gates.

Verified evidence: <VERIFIED FILE>

## Design Decisions

- Preserve a compatible path and state the exact recovery action before migration.

## Implementation Phases

### Phase 1 - Compatibility and Recovery

Objective: Define compatibility and recovery before the migration.

## Inter-Phase Contracts

- Backup, rollback, and validation commands are known before data or schema changes.

## Open Questions

- <OPEN QUESTION OR NONE>

## Risks

- A migration without a verified rollback path can make recovery unsafe.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | applicable | MEDIUM | <VERIFIED FILE> | Measure affected data before execution. |
| performance | applicable | MEDIUM | <VERIFIED FILE> | Define a bounded migration window. |
| concurrency | applicable | MEDIUM | <VERIFIED FILE> | State write coordination or downtime gate. |
| access_control | applicable | MEDIUM | <VERIFIED FILE> | Verify migration authority and secrets handling. |
| migration_rollback | applicable | HIGH | <EXACT COMMAND> | Verify backup and rollback before migration. |
| dependency | applicable | LOW | <VERIFIED FILE> | Confirm migration tool versions. |
| operability | applicable | HIGH | <EXACT COMMAND> | Validate compatible path and recovery command. |

## Success Criteria

- Validation proves the compatible path and rollback or recovery.

## Handoff

Saved plan path: `plans/<task>-plan.md`

## Notes for Execution

- Do not run the migration until <EXACT COMMAND> verifies backup and rollback.

## Progress

- Template copied; replace all authoring markers with repository evidence.

## Discoveries

- <DISCOVERY>

## Decision Log

- Treat missing rollback evidence as a replan condition.

## Outcomes

- Pending execution.

## Idempotence & Recovery

- Re-run dry-run validation before any destructive migration action.
