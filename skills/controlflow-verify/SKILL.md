---
name: controlflow-verify
description: "Use when the user explicitly invokes $controlflow-verify for preflight of a saved repository contract."
---

# ControlFlow Verify

Verify a saved plan before implementation. The checks run inline with zero
shipped subagents. Invoke explicitly with `$controlflow-verify`.

Reflect the preflight result in available native `update_plan`, following
[progress](../controlflow/references/progress.md). Rejected, waiting, or
unverified work stays incomplete. If unavailable, report textual progress;
native TODO status is not approval or evidence.

## V4 binding

Read the canonical `plan.meta.json`; compact artifacts need no duplicate Markdown.
For schema 4.0.0 use `scripts/validate-contract.ps1 -Path <contract>`, then the
six questions below. Full profiles require final contract/artifacts and APPROVED
preflight before owned code or test edits, including SMALL features.
Write the review rationale inside the active run directory and record
`{"type":"preflight","status":"APPROVED"}` through `scripts/update-run.ps1`
with explicit RepoRoot, RunPath, and EventPath. Runtime binds the approval to
the current contract. An unbound verdict is a draft, not gate evidence.

Reject invented criterion coverage, unsafe adoption of initial user hunks,
unresolved product-critical choices, and missing required independent review.
Repair/replan before approval. Optional native readers follow the entry's tier
limits, have precise questions, and their usage counts; no plugin agent runtime.
Old verdicts do not become V4 evidence. Existing V3 runs retain their original,
visibly legacy rules; new V3 creation is rejected. See
[execution](../controlflow/references/execution.md).

## Input

- Read the active run's external `state.contract_path` and its evidence from disk;
  do not verify a chat copy. The JSON contract is canonical.
- Validate new contracts against `schemas/plan-meta-v4.schema.json`; the schema
  under `schemas/compat/` is only for existing legacy runs/read-only migration.

## Adversarial stance

Try to break the plan, not defend it. Steelman the strongest rejection before
accepting. Default to `uncertain` when evidence is insufficient; for each claim
ask what would make it false, then check that condition. Every blocker cites a
file, line, command output, or precise reasoning path. Planner confidence never
substitutes for verifier confidence.

## Six questions

1. Can execution start from repository evidence?
2. Are APIs/files/dependencies/schema assumptions verified against the repo?
3. Are failure, migration, and rollback paths sufficient?
4. Does the plan define meaningful executable checks for code targets and the
   required artifact-bound review/decision paths for agent/human targets? Mixed
   targets are all-required; no judge substitutes for another.
5. Is planned scope coherent with the requested outcome?
6. Is the proposed implementation the smallest coherent change consistent with
   repository conventions, or does it introduce material speculative architecture
   beyond the accepted task?

Proportionality findings identify the concrete unnecessary structure and why
current requirements or repository evidence do not justify it. Legitimate
abstractions and boundaries remain allowed; file counts or line counts alone
are not evidence.

Apply auth, concurrency, data-integrity, and operability scrutiny only when the
task touches them — not as a fixed checklist for every plan.

## Verdict

Write a compact review rationale inside the active run directory:

```
Status: APPROVED | NEEDS_REVISION | REPLAN

## Findings
- location/evidence
- problem
- required correction

## Residual uncertainty
...

## Next action
...
```

- `APPROVED` - the semantic preflight assessment accepts the proposed plan;
  actual implementation still requires the saved final preflight gate.
- `NEEDS_REVISION` — viable but specific defects must be fixed; revise the plan.
- `REPLAN` — scope or architecture is not safely deliverable as written; route
  through the native host's replan path.

Do not start implementation until the required current approvals and preflight
gate pass. An agent's assessment is not a human decision. Do not rewrite the plan or
metadata as a side effect of producing a verdict; the planner and native host
own any explicitly authorized revision.

## Boundary

Do not spawn plugin verifier agents. For an isolated second opinion use native
`/review` or an explicitly requested native subagent. The host owns approvals,
sandboxing, retries, and subagent lifecycle.



## V4 preflight

For v4, first validate schema, IDs, exact inputs, epoch and bindings, then review
meaning. Require final declarations, context/design/QA/implementation artifacts
and the exact human design decision when required by review_policy before
preflight. Local human receipts are manual
provenance; verified assurance blocks without a tested trusted source. Neither
human=true, hashes, serverRequest/resolved nor timeout proves human approval.
HUMAN_WAIT is a lawful incomplete stop, with no automatic continuation. Missing
or unknown required judges block: all-required means every listed judge.
Read [v4 workflow](../../docs/v4-runtime.md) and its architecture policy.
