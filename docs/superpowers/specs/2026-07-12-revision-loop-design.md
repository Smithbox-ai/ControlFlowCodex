# Revision Loop Design

## Purpose

Add a small, skill-only revision loop for a ControlFlow plan that did not pass
verification. The loop turns a non-approved verifier verdict into a structured,
machine-validated revision request, then sends the planner back through the
existing validation, scoring, and verification steps.

The feature records required changes; it never edits a plan, runs declared plan
commands, creates agents, or owns host approval and execution state.

## Scope

This delivery adds:

- `plans/artifacts/<task>/revision-request.json` as the deterministic handoff
  artifact for a non-approved verdict.
- `schemas/revision-request.schema.json` as the portable JSON shape.
- `scripts/validate-revision.ps1` to validate the request against the saved
  Markdown plan, metadata sidecar, and verifier verdict.
- Planner and verifier guidance for the `plan → verify → revise` cycle.
- Contract fixtures and tests for valid and invalid revision requests.

It does not add automatic patching, a prompt router, a retry scheduler, a new
skill, external services, or a general issue tracker.

## Artifact Contract

`revision-request.json` is created for a non-approved verifier verdict. It may
remain beside a later `APPROVED` verdict as retained evidence from the prior
cycle; the approved verdict does not create a new active request. It has these
fields:

| Field | Rule |
| --- | --- |
| `schema_version` | Exactly `1.0.0`. |
| `plan_path` | Matches the repository-relative Markdown plan path. |
| `source_verdict_path` | Matches `plans/artifacts/<task>/verify-verdict.md`. |
| `source_verdict_status` | Matches the verdict status and is `NEEDS_REVISION` or `REJECTED`. |
| `failure_classification` | Matches the verdict and is `fixable`, `needs_replan`, or `escalate`. |
| `next_action` | `revise`, `replan`, or `escalate`; constrained by the status/classification mapping below. |
| `summary` | Non-empty plain-language explanation of why the plan cannot proceed. |
| `items` | Non-empty array of concrete revision requirements. |

Each item contains a unique `id`, a non-empty `location`, `finding`,
`required_change`, and `acceptance_criteria`. The item is deliberately a
structured transcription of the verifier's evidence and revision instructions,
not an executable patch.

The allowed action mapping is deterministic:

| Verdict status | Failure classification | Required `next_action` |
| --- | --- | --- |
| `NEEDS_REVISION` | `fixable` | `revise` |
| `REJECTED` | `needs_replan` | `replan` |
| `REJECTED` | `escalate` | `escalate` |

All other combinations are invalid. In particular, a rejected plan cannot be
treated as a small revision.

## Workflow

1. The planner saves the Markdown plan and metadata sidecar, then runs the
   existing validator, deterministic scorer, and verifier.
2. If the verifier returns `APPROVED`, no new revision request is created.
   An existing request from a prior cycle is retained and validated as
   historical evidence; implementation may begin through the native host.
3. If the verifier returns a non-approved verdict, it writes
   `revision-request.json` beside the verdict and runs
   `validate-revision.ps1`.
4. For `next_action: revise`, the planner updates the plan and metadata only in
   response to the request items, preserves the lifecycle history, and repeats
   validation, scoring, and verification.
5. For `next_action: replan` or `escalate`, the planner does not patch the
   rejected plan. It performs the named recovery step through the native host
   and records the outcome.

The original verdict and revision request remain as evidence. A later approved
verdict closes the loop without deleting earlier artifacts.

## Validation Behavior

`scripts/validate-revision.ps1 -RepoRoot . -PlanPath plans/<task>-plan.md`
locates the matching metadata, verifier verdict, and optional revision request.
It checks file presence, JSON parsing, schema-shaped values, artifact-path
alignment, verdict status, failure classification, allowed action mapping, and
unique/non-empty request items. With `APPROVED`, an existing request must be a
valid retained non-approved request; it is not treated as the current action.

The script is dependency-free PowerShell compatible with Windows PowerShell 5.1
and PowerShell 7. It emits validation text, exits non-zero on invalid input, and
never executes a command named by the plan or revision request.

## Skill and Documentation Changes

`$controlflow-verify` instructs the verifier to create the revision request
after any non-approved verdict. `$controlflow-plan` instructs the planner to
read the artifact, honor `next_action`, and rerun the existing checks after a
revision. `README.md` documents the artifact, command, and non-automation
boundary. The existing review skill remains unchanged because its job begins
after implementation.

## Testing

Focused PowerShell tests cover:

- a valid `NEEDS_REVISION` + `fixable` request with `next_action: revise`;
- a valid `REJECTED` + `needs_replan` request;
- an `APPROVED` verdict retaining a valid prior request;
- a request whose action conflicts with its verdict;
- a request with mismatched plan path, duplicate item IDs, or missing item
  content;
- Windows PowerShell 5.1 and PowerShell 7 execution;
- integration in the portable and Pester-backed contract runner.

## Success Criteria

- A non-approved verdict has a deterministic, validated revision handoff.
- An approved verdict does not require or create a revision request.
- The action mapping prevents cosmetic edits of rejected plans.
- All existing and new contract tests pass in both supported PowerShell shells.
- The plugin remains a thin quality layer with no runtime orchestration.
