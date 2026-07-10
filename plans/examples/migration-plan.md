# Plan: Migration Example

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** MEDIUM
**Confidence:** 0.86
**Abstain:** false
**Summary:** Introduce an optional plan metadata sidecar while retaining Markdown-only validation compatibility.

## Context & Analysis

Goal Statement: Add optional metadata validation without invalidating existing Markdown-only plans.

## Design Decisions

- Gate the new contract behind an explicit validator switch.

## Implementation Phases

### Phase 1 - Compatibility Gate

Objective: Validate the sidecar only when the caller requests it and retain the legacy command path.

## Inter-Phase Contracts

- Legacy validation must pass without the metadata switch.

## Open Questions

- None.

## Risks

- A mandatory migration could invalidate published plan artifacts.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | Small metadata files. | No action. |
| performance | not_applicable | LOW | One JSON read. | No action. |
| concurrency | not_applicable | LOW | No runtime. | No action. |
| access_control | not_applicable | LOW | No new credentials. | No action. |
| migration_rollback | applicable | MEDIUM | Existing plans lack sidecars. | Retain optional switch. |
| dependency | not_applicable | LOW | Native PowerShell JSON parser. | No action. |
| operability | applicable | MEDIUM | Public validation behavior changes. | Test both command paths. |

## Success Criteria

- Legacy validation succeeds while metadata validation is opt-in.

## Handoff

Saved plan path: `plans/examples/migration-plan.md`

## Notes for Execution

- Do not mutate existing user plans.

## Progress

- Example prepared.

## Discoveries

- The current validator already uses switches for optional verdict validation.

## Decision Log

- Reuse the switch pattern for rollback safety.

## Outcomes

- Pending example execution.

## Idempotence & Recovery

- Removing the new switch restores the legacy path.
