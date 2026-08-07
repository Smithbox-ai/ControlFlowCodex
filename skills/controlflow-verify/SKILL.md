---
name: controlflow-verify
description: "Adversarially verify a saved ControlFlow plan before implementation. Invoke explicitly with $controlflow-verify."
---

# ControlFlow Verify

Verify a saved plan before implementation. The checks run inline with zero
shipped subagents. Invoke explicitly with `$controlflow-verify`.

## Input

- Read the plan and `plans/artifacts/<task-slug>/plan.meta.json` from disk; do
  not verify a chat copy. The sidecar is the canonical contract.
- Use the active repository's schema when present, otherwise the bundled
  `schemas/plan-meta.schema.json`.

## Adversarial stance

Try to break the plan, not defend it. Steelman the strongest rejection before
accepting. Default to `uncertain` when evidence is insufficient; for each claim
ask what would make it false, then check that condition. Every blocker cites a
file, line, command output, or precise reasoning path. Planner confidence never
substitutes for verifier confidence.

## Five questions

1. Can execution start from repository evidence?
2. Are APIs/files/dependencies/schema assumptions verified against the repo?
3. Are failure, migration, and rollback paths sufficient?
4. Can success be proven by runnable checks?
5. Is planned scope coherent with the requested outcome?

Apply auth, concurrency, data-integrity, and operability scrutiny only when the
task touches them — not as a fixed checklist for every plan.

## Verdict

Write a compact verdict to `plans/artifacts/<task-slug>/verify-verdict.md`:

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


