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

## V4 evidence

Read the active V4 run, current `plan.meta.json`, immutable phase snapshots and
captures. Review the QA recheck and source-bound packet after native generic
review and repairs. The light docs route remains compact. Use
`completion-gate.ps1 -RepoRoot <repo> -RunPath <run>` for current scope,
ownership, provenance/freshness, coverage, and blockers. A required commit adds
candidate and actual SHA/tree checks; commit only on explicit user request.
Record the actual required agent/human phase decisions after deterministic
checks; missing or unknown required verdicts keep completion blocked.

Assess whether each executable check really proves its criterion. The ledger
cannot establish semantic truth of an LLM's PROVEN claim. Missing independent
review required by the contract remains a blocker. Write concise rationale
inside the run, then record the supported `phase_review` event against the
exact current packet/target through `update-run.ps1`. Do not supply a human
decision unless the user actually made it. Runtime binds decisions to the current
artifact/intent/policy/source; later
code edits require checks and final review again. Resolve blockers only with
actual repair evidence. Run completion-gate again before final claims.

Do not modify immutable state/captures or reuse an old prose verdict to satisfy
a gate. Existing V3 runs stay visibly legacy; do not create a new V3 run or
reuse legacy evidence for V4. A structured clarification, denial, cancel,
interruption, Plan Mode, or BLOCKED ends the turn without DONE.

## Input

- Read the approved external `state.contract_path` and its active
  run. MEDIUM/LARGE also have a brief rationale inside the run directory.
- Read the aggregate diff. If native `/review` results are available, consume
  them.

## Five checks

1. **Actual scope vs approved scope** — inspect the current completion gate's
   scope and ownership observations. Initial dirty files are not exemptions;
   new edits in them and out-of-scope implementation require resolution.
2. **Success criteria vs evidence** - do meaningful executable checks pass for
   code targets, and exact bound reviews/decisions satisfy agent/human targets?
   Follow the declared judge policy: mixed targets are all-required, without
   dummy checks for human-only criteria or substitution between judges.
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

## V4 QA and decision packet

Use qa-recheck to compare each original QA expected result with current diff
and captured evidence. Never change expected results to legalize a defect; fix
code or explicitly re-enter planning for a real requirement change. Missing,
zero-test, unsupported and incomplete reports remain visible gaps. Counts do
not prove semantic quality. Assemble the compact review-packet from saved
evidence: behavior/invariants, diff, results, limitations, rollback and open
decisions. Inspect its generated evidence_summary.

Satisfy all required code/agent/human judges. A contract's human_final requirement
applies even when the profile omits it. A different native model is optional and does not
prove independence. Findings cite rule, source, consequence and evidence.
Re-run the gate on current source. PASS grants no external-effect authority.
Read [v4 workflow](../../docs/v4-runtime.md).
