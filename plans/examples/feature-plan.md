# Plan: Feature Example

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** MEDIUM
**Confidence:** 0.87
**Abstain:** false
**Summary:** Add structured planning metadata to the existing ControlFlow skill lifecycle.

## Context & Analysis

Goal Statement: Require a structured sidecar when ControlFlow creates a non-trivial durable plan.

## Design Decisions

- Extend the existing planning skill instead of adding a new skill or runtime service.

## Implementation Phases

### Phase 1 - Planner Contract

Objective: Describe Markdown and sidecar outputs in the planning skill and verify their paths.

## Inter-Phase Contracts

- The validator schema defines the sidecar contract consumed by the skill.

## Open Questions

- None.

## Risks

- New instructions could imply that the plugin owns execution.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | Compact text artifacts. | No action. |
| performance | not_applicable | LOW | Prompt-only behavior. | No action. |
| concurrency | not_applicable | LOW | Native host owns concurrency. | Preserve boundary. |
| access_control | not_applicable | LOW | Native host owns approvals. | Preserve boundary. |
| migration_rollback | applicable | LOW | Existing plans remain supported. | Keep validation opt-in. |
| dependency | not_applicable | LOW | No new runtime dependency. | No action. |
| operability | applicable | MEDIUM | Skill contract is public behavior. | Add contract test. |

## Success Criteria

- The planner skill documents both artifacts without owning native execution.

## Handoff

Saved plan path: `plans/examples/feature-plan.md`

## Notes for Execution

- Keep the native Codex boundary explicit.

## Progress

- Example prepared.

## Discoveries

- ControlFlow already separates planning from verification and review.

## Decision Log

- Extend the existing lifecycle rather than introduce a fourth skill.

## Outcomes

- Pending example execution.

## Idempotence & Recovery

- Skill text can be revalidated by the contract test.
