---
name: controlflow
description: "Use when the user explicitly invokes $controlflow for a repository task."
---

# ControlFlow v3

Carry the authorized task through fresh evidence and a truthful final status.
Native Codex owns execution, sandbox, permissions, review, and agent lifecycle.

Native plugin text: `$controlflow-codex:<skill-name>`; aliases require host support.

For multi-step work, maintain native `update_plan` when available; restore existing
progress after resume. Read [progress](references/progress.md). If unavailable,
report textual progress honestly.

Observe scope, behavior changes, system boundaries, product uncertainty, and
risks. Use `scripts/classify-task.ps1` with these signals. Unresolved HIGH risk
forces LARGE. Ask only questions whose answer changes the product or authority.

- **TRIVIAL:** native work and appropriate verification; no artifacts or agents.
- **SMALL:** JSON contract, one writer, captured checks, direct completion gate.
- **MEDIUM:** JSON plus brief rationale, preflight and final review; optional
  zero or one native reader for a concrete uncertainty.
- **LARGE:** MEDIUM with relevant risks/ordering; at most two concurrent readers.

Read [execution](references/execution.md) for non-trivial work. Read
[evidence](references/evidence.md) when preparing checks or handling dirty
content, and [review](references/review.md) for MEDIUM/LARGE.

Preserve initial user index, worktree, and untracked content. Overlap blocks this
MVP; use a native isolated worktree or request a concrete ownership decision.
Require a commit only on explicit user request.

Use native session identity. If hooks are missing/untrusted, start with
`-ManualFallback`, call completion-gate directly, and disclose the weaker
automatic guarantee. End clarification, denied permission, cancellation,
interruption, Plan Mode, or BLOCKED lawfully; never call that DONE. Resume only
on an explicit user decision. Completion requires fresh gate PASS.
