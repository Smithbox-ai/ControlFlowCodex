---
name: controlflow-plan
description: "Use after native /plan when a non-trivial repository task needs a durable execution contract persisted to disk. Invoke explicitly with $controlflow-plan."
---

# ControlFlow Plan

Use after native `/plan` when the task needs a durable execution contract.
Native `/plan` gathers context and clarifies the task; this skill only persists
the durable contract to disk. Invoke explicitly with `$controlflow-plan`.

## Artifacts

Write two artifacts:

- `plans/<task-slug>-plan.md` — concise human rationale, decisions, and notes.
- `plans/artifacts/<task-slug>/plan.meta.json` — the canonical machine contract
  (`schemas/plan-meta.schema.json`, `schema_version: 2.0.0`).

The plan filename must end with `-plan.md`; the slug is everything before that
suffix and locates the artifact directory.

The machine contract holds the machine-critical data. Do not duplicate it in the
Markdown prose — prose carries only rationale, decisions, and notes the contract
cannot express.

## Contract contents

Persist in `plan.meta.json`:

- `goal` — the user-facing goal (and note non-goals in prose).
- `tier` — `TRIVIAL` | `SMALL` | `MEDIUM` | `LARGE`.
- `baseline` — `commit` (current HEAD) and `dirty_paths` (staged, unstaged, and
  untracked paths at planning time; empty array when clean).
- `scope` — glob patterns of intended files.
- `criteria` — measurable success criteria.
- `checks` — executable validation commands.
- `risks` — object keyed by category. Include only applicable categories from
  `data_volume`, `performance`, `concurrency`, `access_control`,
  `migration_rollback`, `dependency`, `operability`. No `not_applicable`
  placeholders; omit a category that does not apply. Each value has `impact`
  and, when relevant, `mitigation`.
- `phases` — optional, only when ordering materially matters. Omit when there is
  no real sequence (scope + checks are enough).

## Tiers

- `TRIVIAL` — usually 1-2 files, one concern, low blast radius. Use native Codex
  directly; no artifact unless explicitly requested.
- `SMALL` — one plan.
- `MEDIUM` — one plan.
- `LARGE` — one plan; consider alternative designs only when material
  architectural uncertainty remains after repository research. Do not generate
  multiple candidates as a default rule.

Any unresolved applicable `HIGH` risk forces `LARGE` regardless of file count.

## Baseline

Before authoring, record the repository baseline in `plan.meta.json`:

- `baseline.commit` — `git rev-parse HEAD`.
- `baseline.dirty_paths` — `git status --porcelain` paths at planning time.

This replaces full-tree snapshots: it is `O(1)` for the commit plus `O(D)` for
dirty paths, instead of `O(N)` over the whole tracked tree.

## Before READY

- Verify every repository claim (files, APIs, dependencies, schema) from current
  files. Keep verified facts separate from assumptions.
- Do not mark a plan ready without concrete runnable checks.
- Run the deterministic check when available:
  `scripts/validate-plan.ps1 -RepoRoot . -PlanPath plans/<task-slug>-plan.md -RequirePlanMetadata`.
- Hand every non-trivial ready plan to `$controlflow-verify` before
  implementation.

## Do not

- Do not duplicate native execution, approvals, retries, subagent management,
  generic review, or session state — Codex owns those.
- Do not invent requirements that change behavior, scope, architecture, or
  destructive risk.
- Do not add plugin-level runtime controls Codex already owns.
- Do not force persisted rows for every risk category; record only applicable
  risks.
- For `TRIVIAL` work, use native Codex directly.
