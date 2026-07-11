# ControlFlow for Codex

> A slim planning-quality plugin for native Codex: durable plans, adversarial
> verification, and plan-aware review — without duplicating what Codex already does.

**3 skills, 0 subagents.** The plugin keeps the ControlFlow plan format, tier-gated
semantic-risk review, and evidence discipline, then hands execution back to native
Codex. It installs no router, runtime policy, approval engine, retry scheduler, or
custom subagents.

This repository is the standalone home of the ControlFlow-for-Codex plugin.

The core feedback loop is: clarify uncertain context, state the user-facing goal,
define measurable success criteria, verify that the plan is executable, execute in
native Codex, and review the final evidence against the approved goal and criteria.

## How it fits with native Codex

```mermaid
flowchart TD
    A["Clarify the task<br/>native <code>/plan</code>"] --> B["$controlflow-plan<br/>goal + measurable criteria"]
    B --> C["$controlflow-verify<br/>inline adversarial check"]
    C --> D{"Verdict?"}
    D -->|"NEEDS_REVISION / REJECTED"| B
    D -->|"APPROVED"| E["Native Codex executes<br/>tools · sandbox · approvals · subagents"]
    E --> F["native <code>/review</code><br/>general code review"]
    F --> G["$controlflow-review<br/>plan conformance + evidence"]
    G --> H["Done"]
```

## What the plugin owns vs. what Codex owns

```mermaid
flowchart LR
    subgraph Plugin["ControlFlow plugin adds"]
        P1["Plan-format contract<br/>+ semantic-risk review"]
        P2["Inline adversarial verify<br/>structure · mirages · cold-start"]
        P3["Plan-conformance review<br/>scope drift · evidence"]
    end
    subgraph Codex["Native Codex keeps"]
        C1["Plan mode · clarification"]
        C2["Execution · sandbox · approvals"]
        C3["Subagents · lifecycle"]
        C4["Generic <code>/review</code> · memories"]
    end
    Plugin -. "layers over" .-> Codex
```

## Skills

| Skill | Purpose |
| --- | --- |
| `$controlflow-plan` | Save a durable, tiered, semantic-risk-reviewed plan under `plans/` |
| `$controlflow-verify` | Verify the saved plan inline: structure, mirages, and cold-start executability |
| `$controlflow-review` | Compare implementation and test evidence with the approved plan |

Each skill is a single self-contained `SKILL.md` (references inlined), plus an optional
`agents/openai.yaml` for host UI metadata. There are no reference files and no subagents.

When the active repository contains `schemas/planner.plan.schema.json` and
`plans/templates/plan-document-template.md`, those files override the bundled plan-format
fallback.

## Installation

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
```

Use `-Force` to replace an existing installation. To remove:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1 -Uninstall -Force
```

This copies the plugin into `$HOME/plugins/controlflow-codex` and registers a local
marketplace entry at `$HOME/.agents/plugins/marketplace.json`.

## Deterministic validator

`scripts/validate-plan.ps1` checks the plan header, required sections, lifecycle
heading order, the seven semantic-risk rows (each exactly once), and (with
`-RequireVerifyVerdict`) the `verify-verdict.md` shape.

## Structured plan metadata

Every new non-trivial ControlFlow plan can pair its Markdown artifact with
`plans/artifacts/<task>/plan.meta.json`. The bundled
`schemas/plan-meta.schema.json` defines the portable sidecar format: goal, tier,
phases, dependencies, planned files, commands, semantic risks, and success
criteria. Markdown remains the human-readable plan; metadata enables deterministic
validation and future plan-aware comparison without adding a runtime service.

Use `-RequirePlanMetadata` to validate the sidecar and its synchronization with
the Markdown goal, tier, and phase IDs. The option is intentionally opt-in so
existing Markdown-only plans remain supported.

## Deterministic plan scoring

`scripts/score-plan.ps1` reads a saved plan, its metadata sidecar, and its
verifier verdict, then emits one JSON object with `aggregate_score`, a
deterministic verdict, metrics, and diagnostic issues. It does not execute
declared plan commands or call external services.

The six 0-100 metrics are `completeness`, `executability`,
`criteria_coverage`, `dependency_sanity`, `risk_coverage`, and
`evidence_readiness`. `APPROVED` requires every metric to be at least 80;
otherwise an aggregate score of at least 50 is `NEEDS_REVISION`, and a lower
score is `REJECTED`. These are reproducible plan-quality signals, not a
replacement for `$controlflow-verify`'s adversarial review or native Codex
approval decisions.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-plan.ps1 -RepoRoot . -PlanPath plans/my-task-plan.md
```

## Plan templates

`plans/templates/` contains paired Markdown and JSON skeletons for `bugfix`,
`refactor`, `migration`, `feature`, and `docs-test-only` work. They are not
validated execution plans: copy the relevant pair, replace every authoring
marker with verified repository evidence and exact commands, then save the
grounded artifacts under the normal `plans/` and `plans/artifacts/` locations.

Choose a template only when the task type is clear. When the choice affects
scope, rollback, or safety, clarify first instead of treating a template as an
automatic planner or runtime mechanism.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate-plan.ps1 `
  -RepoRoot . `
  -PlanPath plans/my-task-plan.md `
  -RequirePlanMetadata `
  -RequireVerifyVerdict
```

## When you don't need it

For an obvious one- or two-file change, use native Codex directly — no plan artifact,
no verify, no review. The `TRIVIAL` tier exists exactly for this.

## Repository layout

```
.codex-plugin/plugin.json        plugin manifest
assets/controlflow-codex-logo.svg logo
skills/controlflow-plan/          $controlflow-plan  (SKILL.md + agents/openai.yaml)
skills/controlflow-verify/        $controlflow-verify
skills/controlflow-review/        $controlflow-review
scripts/install.ps1               install / -Uninstall
scripts/validate-plan.ps1         plan-format + metadata + verify-verdict validator
scripts/score-plan.ps1            deterministic plan artifact scorer (JSON)
schemas/plan-meta.schema.json     structured plan-sidecar contract
README.md · CHANGELOG.md · LICENSE
```

## License

MIT — see [LICENSE](LICENSE).
