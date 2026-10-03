---
name: controlflow-plan
description: "Use when the user explicitly invokes $controlflow-plan to persist a repository task contract after native planning."
---

# ControlFlow Plan

Persist a durable execution contract after native `/plan` or the explicit
`$controlflow` entry. Native planning gathers context; this skill saves the
verified intent. Read the user request and current repository first.

Restore the accepted milestones and verified progress in available native
`update_plan`, following [progress](../controlflow/references/progress.md).
Keep waiting work incomplete. If unavailable, report textual progress honestly;
the TODO list does not replace the saved contract or evidence.

For new plans use `schema_version: 3.0.0`,
`schemas/plan-meta-v3.schema.json`, and `plans/templates/plan.meta.v3.json`.
Write `plans/artifacts/<task-slug>/plan.meta.json`; `task_id` is that slug.

Record the real baseline commit and observed `dirty_paths`, intended `scope`,
ID-bearing `criteria`, executable ID-bearing `checks` with working directories
and criterion references, and `commit.mode` (`none` unless explicitly requested).
Applicable `risks` have IDs, text, impact, resolved status and mitigation;
omit `not_applicable` placeholders. `assumptions` are explicit uncertain facts.
Add `phases` with dependencies only when ordering materially matters.

- TRIVIAL uses native work without artifacts or agents.
- SMALL needs only JSON and meaningful checks.
- MEDIUM/LARGE add brief rationale inside the run directory after start.
- Any unresolved HIGH risk forces LARGE, regardless of file count.

Verify every claim about repository files/APIs/dependencies from current
evidence. Clarify product-critical uncertainty; use judgment for routine choices.
Do not invent product behavior, scope, architecture, or destructive authority.
Do not duplicate machine-critical JSON in prose.

Run `scripts/validate-contract.ps1 -Path <contract>`. Start the session-bound run
before edits, following the [execution reference](../controlflow/references/execution.md).
MEDIUM/LARGE hand off to `$controlflow-verify` before implementation. Capture
initial user index, worktree, and untracked content separately; dirty paths are
not exemptions. Overlap requires an isolated worktree or concrete user decision.

For an existing v2 input, use the v3 migration command to create a separate
contract, inspect criterion coverage, and approve a fresh run. Old runtime,
templates and prose verdicts are not part of v3 and cannot activate its gates.

Do not duplicate native execution, sandbox, permission decisions, scheduling,
generic review, or subagent lifecycle. ControlFlow persists intent and evidence.
