---
name: controlflow-review
description: "Review an implementation against its approved ControlFlow plan for conformance and evidence. Invoke explicitly with $controlflow-review."
---

# ControlFlow Review

Add the ControlFlow-specific layer after implementation. Native `/review` is the
general code-review pass; consume its results rather than repeating them. Invoke
explicitly with `$controlflow-review`.

## Input

- Read the approved `plans/<task-slug>-plan.md` and
  `plans/artifacts/<task-slug>/plan.meta.json` (the canonical contract).
- Read the aggregate diff. If native `/review` results are available, consume
  them.

## Four checks

1. **Actual scope vs approved scope** — run
   `scripts/detect-drift.ps1 -RepoRoot . -PlanPath plans/<task-slug>-plan.md`
   to classify changed paths as `planned` or `unplanned`; then decide
   semantically whether each unplanned change is justified.
2. **Success criteria vs evidence** — did the runnable `checks` pass, and do
   they prove the `criteria`?
3. **Unplanned externally visible behavior** — any change to APIs, endpoints, or
   persisted schema not in the approved scope?
4. **Promised rollback / operability** — if the plan promised rollback, dual-read,
   or an operability guarantee, is it actually in place?

That is the entire ControlFlow review. General correctness, security, style,
documentation, and change-size signals belong to native `/review`.

## Findings

Order findings by severity with file/line evidence and confidence. Distinguish
validated blockers from hypotheses and state validation gaps.

Halt for: security, authorization, secret-handling, destructive-action, or
data-integrity defects; failed core behavior or acceptance criteria;
migration/schema/contract changes without rollback or compatibility evidence;
or scope drift that prevents comparison to the approved plan.

Separate what you observed (file/line, command output, tests) from what you
inferred. Mark inference as inference; do not present it as verified fact.

## Boundary

- Do not duplicate native `/review`'s mechanical, style, or security findings.
- Do not skip plan comparison when an approved plan exists.
