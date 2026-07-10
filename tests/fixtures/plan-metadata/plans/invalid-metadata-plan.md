# Plan: Invalid Metadata

**Status:** READY_FOR_EXECUTION
**Agent:** Planner
**Schema Version:** 1.2.0
**Complexity Tier:** SMALL
**Confidence:** 0.90
**Abstain:** false
**Summary:** Keep the invalid fixture structurally valid except for metadata dependencies.

## Context & Analysis

Goal Statement: Keep the invalid fixture structurally valid except for metadata dependencies.

## Design Decisions

- Use an invalid sidecar dependency to exercise the validator.

## Implementation Phases

### Phase 1 - Fixture Validation

Objective: Validate a compact metadata fixture.

## Inter-Phase Contracts

- Phase 1 has no dependencies.

## Open Questions

- None.

## Risks

- The fixture must preserve the required Markdown headings.

## Semantic Risk Review

| Category | Applicability | Impact | Evidence Source | Disposition |
| --- | --- | --- | --- | --- |
| data_volume | not_applicable | LOW | Fixture is small. | No action. |
| performance | not_applicable | LOW | Fixture is small. | No action. |
| concurrency | not_applicable | LOW | No runtime. | No action. |
| access_control | not_applicable | LOW | No access boundary. | No action. |
| migration_rollback | not_applicable | LOW | No migration. | No action. |
| dependency | not_applicable | LOW | No package dependency. | No action. |
| operability | applicable | LOW | Validator reads the fixture. | Run validation. |

## Success Criteria

- Metadata validation rejects the invalid dependency.

## Handoff

Saved plan path: `plans/invalid-metadata-plan.md`

## Notes for Execution

- Run the validator with required metadata.

## Progress

- Fixture created.

## Discoveries

- None.

## Decision Log

- Use a dependency that does not exist in the sidecar phase list.

## Outcomes

- Pending validation.

## Idempotence & Recovery

- Validation can be rerun safely.
