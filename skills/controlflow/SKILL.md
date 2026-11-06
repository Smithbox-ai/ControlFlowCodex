---
name: controlflow
description: "Use when the user explicitly invokes $controlflow for a repository task."
---

# ControlFlow

Carry authorized work through fresh evidence and truthful status. Native Codex
owns execution, permissions, sandbox, review and agent lifecycle.
Native invocation: `$controlflow-codex:<skill-name>`; aliases require host support.

Maintain native `update_plan` for multi-step work when available. Restore accepted
progress after resume; otherwise report textual progress. Read
[progress](references/progress.md).

Classify scope, behavior, boundaries, product uncertainty and risk with
`classify-task.ps1`. Unresolved HIGH risk forces LARGE.
One writer owns production edits.

- **SMALL:** compact V4 profile; safe docs use light, other work keeps phase gates.
- **MEDIUM:** preflight/final review; zero or one optional native reader.
- **LARGE:** MEDIUM plus relevant risks/ordering; at most two concurrent readers.

Read [execution](references/execution.md) for non-trivial tasks,
[evidence](references/evidence.md) for checks/dirty content, and
[review](references/review.md) when the profile/policy requires it. Preserve original user index,
worktree and untracked ownership. Overlap requires isolation or an explicit
ownership decision. Commit only when explicitly requested.

Assess code-target test sensitivity in QA using
[the evidence recipe](references/evidence.md#test-sensitivity). Green tests alone
do not prove fault detection.

New runs use `4.0.0` via [v4](../../docs/v4-runtime.md): fixed artifacts,
domain/risk review, manual decisions and compact packets. Classify work type and
domain; tiny core/unknown changes retain human gates. Existing V3 runs keep
marked legacy semantics; new legacy runs are rejected. Do not copy approvals.

Use native session identity. Missing/untrusted hooks require `-ManualFallback`,
direct completion-gate and disclosure. Clarification, denial, cancellation,
interrupt, Plan Mode, HUMAN_WAIT or BLOCKED end incomplete. Resume requires
explicit user input; DONE requires current gate PASS.
