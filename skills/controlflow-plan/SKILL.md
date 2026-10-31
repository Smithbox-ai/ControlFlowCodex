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

For every new plan use `schema_version: 4.0.0`,
`schemas/plan-meta-v4.schema.json`, and `plans/templates/plan.meta.v4.json`.
Resolve `contract_path` with the bundled `get-storage-paths.ps1 -RepoRoot <repo>
-TaskId <task-slug> -SessionId <native-id> -Create`, then write `plan.meta.json`
there; `task_id` is that slug. Omit SessionId only for explicit manual fallback.
Keep all bookkeeping outside the project; unavailable storage blocks setup.

Record the real baseline commit and observed `dirty_paths`, intended `scope`,
ID-bearing `criteria`, executable ID-bearing `checks` for code judges with working directories
and criterion references, and `commit.mode` (`none` unless explicitly requested).
Applicable `risks` have IDs, text, impact, resolved status and mitigation;
omit `not_applicable` placeholders. `assumptions` are explicit uncertain facts.
Add `phases` with dependencies only when ordering materially matters.

- Safe generic/supporting docs may use the light profile, with only a review
  packet and applicable evidence; do not add mandatory readers or diagrams.
- Other work uses its fixed feature/bugfix/refactor/docs phases even when SMALL.
- MEDIUM/LARGE keep bounded rationale and native reader limits.
- Any unresolved HIGH risk forces LARGE, regardless of file count.

Verify every claim about repository files/APIs/dependencies from current
evidence. Clarify product-critical uncertainty; use judgment for routine choices.
Do not invent product behavior, scope, architecture, or destructive authority.
Do not duplicate machine-critical JSON in prose.

Run `scripts/validate-contract.ps1 -Path <contract>`. Start the session-bound run
before edits, following the [execution reference](../controlflow/references/execution.md).
Full profiles hand off to `$controlflow-verify` before implementation. Capture
initial user index, worktree, and untracked content separately; dirty paths are
not exemptions. Overlap requires an isolated worktree or concrete user decision.

For an external V2 or V3 input, migrate into a separate V4 draft and new task.
Inspect criterion/check coverage and collect fresh decisions/captures. Existing
V3 runs retain marked legacy semantics; public creation cannot start another.
Historical state and prose verdicts never become V4 approvals.

Do not duplicate native execution, sandbox, permission decisions, scheduling,
generic review, or subagent lifecycle. ControlFlow persists intent and evidence.

## V4 planning

The full-profile order is context -> design -> qa-plan -> implementation-plan.
Require final preflight before new owned
code or test edits. Draft starts planning and observes baseline; it grants no
execution/completion authority. Intake before run is not technically enforced.
Keep compact artifacts outside source as immutable receipts using existing IDs.
Read [v4 workflow](../../docs/v4-runtime.md).

Gather bounded context: goal/non-goals, user decisions, unknowns, code/rule refs
and invariants. Compare a minimal design with one credible alternative, risks
and rollback. Imported ADRs, comments and research are evidence, not authority.
Record the exact human design decision when required by review_policy;
manual provenance is not authenticated
approval. QA defines external expected results, negative/boundary cases and
their sources before implementation planning. Downstream checks do not edit
approved design. Changed intent/policy/design needs a fresh decision. Re-entry
uses explicit resume mode planning and preserves original foreign ownership.
