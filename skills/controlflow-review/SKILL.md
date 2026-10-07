---
name: controlflow-review
description: "Use when the user explicitly invokes $controlflow-review for conformance of a repository implementation to its saved contract."
---

# ControlFlow Review

Add the ControlFlow-specific layer after implementation. Native `/review` is the
general code-review pass; consume its results rather than repeating them. Invoke
explicitly with `$controlflow-review`.

After review/repair milestones, synchronize available native `update_plan`
under [progress](../controlflow/references/progress.md). Reopen work when checks
or review invalidate completion. If unavailable, use honest textual progress;
TODO completion does not satisfy the delivery gate.

## V3 evidence

For schema 3.0.0 read the active run, current `plan.meta.json`, and immutable
captures. SMALL needs a direct delivery gate; MEDIUM/LARGE also require this
final conformance approval after native generic review and repairs. Use
`completion-gate.ps1 -RepoRoot <repo> -RunPath <run>` for current scope,
ownership, provenance/freshness, coverage, and blockers. A required commit adds
candidate and actual SHA/tree checks; commit only on explicit user request.
Before final approval, REVIEW_MISSING is expected; record the actual review
after the other conformance checks, then require a fresh PASS.

Assess whether each executable check really proves its criterion. The ledger
cannot establish semantic truth of an LLM's PROVEN claim. Missing independent
review required by the contract remains a blocker. Write concise rationale
inside the run, then record `{"type":"review","status":"APPROVED"}` through
`update-run.ps1`. Runtime binds it to the current contract and source; later
code edits require checks and final review again. Resolve blockers only with
actual repair evidence. Run completion-gate again before final claims.

Do not modify immutable state/captures or reuse an old prose verdict to satisfy
a gate. A v2 contract does not become an active v3 run. A structured clarification, denial, cancel,
interruption, Plan Mode, or BLOCKED ends the turn without DONE.

## Input

- Read the approved `plans/artifacts/<task-slug>/plan.meta.json` and its active
  run. MEDIUM/LARGE also have a brief rationale inside the run directory.
- Read the aggregate diff. If native `/review` results are available, consume
  them.

## Five checks

1. **Actual scope vs approved scope** — inspect the current completion gate's
   scope and ownership observations. Initial dirty files are not exemptions;
   new edits in them and out-of-scope implementation require resolution.
2. **Success criteria vs evidence** — did the runnable `checks` pass, and do
   they prove the `criteria`?
3. **Unplanned externally visible behavior** — any change to APIs, endpoints, or
   persisted schema not in the approved scope?
4. **Promised rollback / operability** — if the plan promised rollback, dual-read,
   or an operability guarantee, is it actually in place?
5. **Implementation proportionality** — did the change add material layers,
   indirection, dependencies, file/class fragmentation, speculative extensibility,
   compatibility machinery, or unrelated refactoring beyond accepted requirements
   or repository conventions? Apply the
   [implementation policy](../controlflow/references/execution.md#proportional-implementation).

Report proportionality with concrete evidence connecting unjustified complexity
to accepted scope, repository conventions, maintenance burden, or unnecessary
behavioral surface. Current requirements, demonstrated duplication, meaningful
boundaries, testability, side-effect isolation, and established conventions can
justify structure. Do not report minor naming/style preferences, subjective
clean-code opinions, raw line counts, or arbitrary file/class size thresholds.

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
