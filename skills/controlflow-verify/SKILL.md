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

## V3 binding

Read the canonical `plan.meta.json`; SMALL may have no Markdown rationale.
For schema 3.0.0 use `scripts/validate-contract.ps1 -Path <contract>`, then the
six questions below. MEDIUM/LARGE require APPROVED preflight before edits.
Write the review rationale inside the active run directory and record
`{"type":"preflight","status":"APPROVED"}` through `scripts/update-run.ps1`
with explicit RepoRoot, RunPath, and EventPath. Runtime binds the approval to
the current contract. An unbound verdict is a draft, not gate evidence.

Reject invented criterion coverage, unsafe adoption of initial user hunks,
unresolved product-critical choices, and missing required independent review.
Repair/replan before approval. Optional native readers follow the entry's tier
limits, have precise questions, and their usage counts; no plugin agent runtime.
Old v2 verdicts never activate v3 gates. See
[execution](../controlflow/references/execution.md).

## Input

- Read `plans/artifacts/<task-slug>/plan.meta.json` and the active run from disk;
  do not verify a chat copy. The JSON contract is canonical.
- Validate against the bundled `schemas/plan-meta-v3.schema.json`.

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
4. Can success be proven by runnable checks?
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

- `APPROVED` — implementation may start.
- `NEEDS_REVISION` — viable but specific defects must be fixed; revise the plan.
- `REPLAN` — scope or architecture is not safely deliverable as written; route
  through the native host's replan path.

Do not start implementation until `APPROVED`. Do not rewrite the plan or
metadata as a side effect of producing a verdict; the planner and native host
own any explicitly authorized revision.

## Boundary

Do not spawn plugin verifier agents. For an isolated second opinion use native
`/review` or an explicitly requested native subagent. The host owns approvals,
sandboxing, retries, and subagent lifecycle.


