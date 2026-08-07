# ControlFlow for Codex

> **Compact vNext** — an evidence-first planning layer for native Codex.
> Durable execution contracts, adversarial preflight, and plan-conformance
> review — without duplicating what Codex already owns.

**3 focused skills, 0 subagents, 2 deterministic scripts, 1 template pair.**
ControlFlow persists intent and evidence; Codex runs execution. The plugin
installs no router, runtime policy, approval engine, retry scheduler, scorer,
revision state machine, or custom subagents.

## What ControlFlow adds vs. what native Codex owns

| Native Codex keeps | ControlFlow adds |
| --- | --- |
| `/plan` — context gathering & clarification | durable execution contract on disk |
| `/goal` — persistent objective | acceptance criteria + baseline + scope |
| execution · sandbox · approvals · retries | (nothing — delegated) |
| subagents · lifecycle | (nothing — delegated) |
| `/review` — generic code review | plan-conformance + scope-drift + evidence |
| `/memories` — ambient memory | (nothing — delegated) |

The architectural principle: **ControlFlow stores intent and evidence; Codex
manages execution.** Do not add capabilities until an eval shows a concrete gap.

## When to use it

- **Trivial** one- or two-file change → use native Codex directly. No ControlFlow.
- **Small / Medium** → `/plan`, then `$controlflow-plan`, `$controlflow-verify`, implement, `/review`, `$controlflow-review`.
- **Large / risky migration** → same flow; the contract carries rollback risk and validation commands.

## Three-command workflow

```text
/plan
Plan a non-trivial task in native plan mode.

$controlflow-plan
Persists plans/<task>-plan.md + plans/artifacts/<task>/plan.meta.json.

$controlflow-verify
Adversarially verifies the saved contract before implementation.

# Codex implements the approved plan with native tools.

/review
$controlflow-review
Compares the diff against the approved scope and criteria.
```

All three skills are **explicit-only** (`allow_implicit_invocation: false`), so
they never fire accidentally on trivial work.

## Compact artifact contract

Every non-trivial plan is two artifacts:

- `plans/<task-slug>-plan.md` — concise human rationale, decisions, notes.
- `plans/artifacts/<task-slug>/plan.meta.json` — the canonical machine contract
  (`schemas/plan-meta.schema.json`, `schema_version: 2.0.0`).

The machine contract holds the machine-critical data and is **not duplicated** in
prose:

```json
{
  "schema_version": "2.0.0",
  "goal": "...",
  "tier": "MEDIUM",
  "baseline": { "commit": "<sha>", "dirty_paths": [] },
  "scope": ["src/auth/**", "tests/auth/**"],
  "criteria": ["..."],
  "checks": ["dotnet test tests/auth"],
  "risks": { "migration_rollback": { "impact": "HIGH", "mitigation": "dual-read" } }
}
```

- `risks` is an object keyed by category — only applicable categories, no
  `not_applicable` placeholders.
- `phases` is optional; include it only when ordering materially matters.
- `baseline` replaces full-tree snapshots: `O(1)` commit + `O(D)` dirty paths
  instead of `O(N)` over the whole tracked tree.

Copy `plans/templates/plan.md` and `plans/templates/plan.meta.json` to start a
plan, then ground every field in verified repository evidence. See
`plans/examples/auth-migration-plan.md` for a worked example.

## Risk / tier policy

- Tiers: `TRIVIAL` · `SMALL` · `MEDIUM` · `LARGE`.
- Any unresolved applicable `HIGH` risk forces `LARGE`.
- Multi-candidate planning is **not** a default rule; consider alternative
  designs only when material architectural uncertainty remains.

## Deterministic scripts

Only two runtime scripts:

- `scripts/validate-plan.ps1` — validates `plan.meta.json` against the v2
  contract and (optionally) the compact `verify-verdict.md` shape.
  ```powershell
  pwsh -File scripts/validate-plan.ps1 -RepoRoot . -PlanPath plans/my-task-plan.md -RequirePlanMetadata
  ```
- `scripts/detect-drift.ps1` — classifies changed paths as `planned` or
  `unplanned` against `plan.meta.json` `scope`, using the metadata `baseline`
  and combining committed, staged, unstaged, and untracked changes.
  ```powershell
  pwsh -File scripts/detect-drift.ps1 -RepoRoot . -PlanPath plans/my-task-plan.md
  ```

The verifier rubric and these scripts are evidence, not replacements for native
Codex approval, execution, sandbox, or review decisions.

## Evidence and scope-drift behavior

`$controlflow-review` runs four checks: actual scope vs approved scope (via
`detect-drift.ps1`), success criteria vs evidence, unplanned externally visible
behavior, and promised rollback/operability. `detect-drift.ps1` reports
`planned` / `unplanned`; the review skill decides semantically whether an
unplanned change is justified. General correctness, security, style, and docs
belong to native `/review`.

## Behavioral eval methodology

Structural tests (`tests/`) prove artifact shape; they cannot prove model
behavior. `evals/` is a behavioral regression corpus: each case declares
`must_detect` / `must_not_do` / `max_artifact_bytes`, and `evals/run-evals.ps1`
scores produced artifacts and records token, byte, and tool-call medians.

```powershell
pwsh -File evals/run-evals.ps1 -RepoRoot . -ValidateOnly        # PR CI: case schema
pwsh -File evals/run-evals.ps1 -RepoRoot . -RunsDir <runs> -Variant compact-vnext
```

See [evals/README.md](evals/README.md) for the full methodology and acceptance
targets. The retired plan scorer lives under `evals/legacy/` for optional
offline correlation only — it is not in the runtime loop.

## Installation

### From a project checkout (local / development)

`scripts/install.ps1` is a clean reinstall: it first **removes any previously
installed plugin files** at the target, then **copies the current shipped files
from this project directory**. Removing first means files renamed or deleted
between versions never leave orphans behind.

```powershell
pwsh -File scripts/install.ps1 -Force
```

This copies the shipped surface (`.codex-plugin`, `assets`, `skills`, `schemas`,
`scripts`, `plans/templates`, `plans/examples`, `tests`, `evals`, `README.md`,
`CHANGELOG.md`, `LICENSE`) into `$HOME/plugins/controlflow-codex` and registers
a local marketplace entry at `$HOME/.agents/plugins/marketplace.json`. Working
state (`.git`, `.vs`, `dist`, …) is never copied.

Remove it again with:

```powershell
pwsh -File scripts/install.ps1 -Uninstall -Force
```

Without `-Force`, install refuses to overwrite an existing target and uninstall
prompts for confirmation. Use `-HomeRoot <path>` to install into a different
home (useful for isolated testing).

### Published distribution

For a published release, prefer Codex's native plugin marketplace flow once a
marketplace manifest is published:

```bash
codex plugin marketplace add Smithbox-ai/ControlFlowCodex
```

The `.codex-plugin/plugin.json` manifest is the plugin contract in both paths.

## Migration from v1 artifacts

v1 used `complexity_tier`, an array of seven `semantic_risks` (with
`not_applicable` placeholders), `phases[].files/commands`, `plan_path`, a
a structured revision-handoff loop, a runtime scorer, and full-tree
`context-snapshot.json`. To migrate a v1 plan:

1. Rename `complexity_tier` → `tier`; set `schema_version` → `2.0.0`.
2. Collapse `phases[].files` / `phases[].commands` into top-level `scope` /
   `checks`; keep `phases` only if ordering matters.
3. Convert the seven `semantic_risks` rows into a sparse `risks` object, dropping
   `not_applicable` entries.
4. Replace `context-snapshot.json` with `baseline: { commit, dirty_paths }`.
5. Drop `plan_path`, the revision-handoff JSON, and any score breakdown from the
   verdict. The new verdict is `Status` + `## Findings` + residual uncertainty +
   next action.

`git tag controlflow-v1-baseline` marks the pre-refactor state for rollback.

## Repository layout

```
.codex-plugin/plugin.json          plugin manifest
skills/controlflow-plan/           $controlflow-plan  (SKILL.md + agents/openai.yaml)
skills/controlflow-verify/         $controlflow-verify
skills/controlflow-review/         $controlflow-review
schemas/plan-meta.schema.json      v2 machine contract
scripts/install.ps1                local install/uninstall (remove + copy from project)
scripts/validate-plan.ps1          metadata + verdict validator
scripts/detect-drift.ps1           scope drift detector (planned/unplanned)
plans/templates/                   one compact template pair
plans/examples/                    worked compact example
tests/                             structural contract suite
evals/                             behavioral regression corpus + runner
.github/workflows/                 ci · eval · release
```

## License

MIT — see [LICENSE](LICENSE).






