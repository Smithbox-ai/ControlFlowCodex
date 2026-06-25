# ControlFlow for Codex

**Version:** 1.0.0

A slim planning-quality plugin for native Codex: **3 skills, 0 subagents**. It keeps
the ControlFlow plan format and adversarial evidence discipline without duplicating
native Codex execution features.

This repository is the standalone home of the ControlFlow-for-Codex plugin,
extracted from the ControlFlow governance/eval repo.

## Skills

| Skill | Purpose |
| --- | --- |
| `$controlflow-plan` | Save a durable, tiered, semantic-risk-reviewed plan under `plans/` |
| `$controlflow-verify` | Verify the saved plan inline: structure, mirages, and cold-start executability |
| `$controlflow-review` | Compare implementation and test evidence with the approved plan |

Each skill is a single self-contained `SKILL.md` (references inlined), plus an
optional `agents/openai.yaml` for host UI metadata. There are no reference files
and no subagents.

## What Remains Native Codex

| Concern | Owner |
| --- | --- |
| Conversational planning and clarification | Native `/plan` and direct questions |
| Live task state and execution | Native Codex |
| Sandbox and approvals | Native Codex security controls |
| Subagent spawning and lifecycle | Native Codex, only when explicitly requested |
| General mechanical code review | Native `/review` |
| Memories and context continuity | Native Codex memories and threads |

The plugin does not install a router, spec workflow, orchestration engine, retry
policy, approval layer, memory layer, or custom runtime subagents.

## Why the Three Skills Still Matter

- Native Plan mode does not impose this durable plan artifact and semantic-risk
  contract.
- `$controlflow-verify` adversarially checks a saved plan before code changes start.
- `$controlflow-review` checks scope drift and acceptance evidence that generic
  diff review cannot infer without the approved plan.
- The bundled plan-format fallback keeps the plugin usable outside a host repo.

When the active repository contains `schemas/planner.plan.schema.json` and
`plans/templates/plan-document-template.md`, those files override the bundled
fallback.

## Recommended Flow

1. Use native `/plan` when the task needs clarification.
2. Invoke `$controlflow-plan` to save the durable artifact.
3. Invoke `$controlflow-verify`; do not implement until it returns `APPROVED`.
4. Let native Codex execute the plan with its normal tools, sandbox, approvals,
   and optional subagents.
5. Run native `/review` for the general code-review pass.
6. Invoke `$controlflow-review` for plan conformance and residual evidence gaps.

For trivial work, use native Codex directly.

## Installation

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
```

Use `-Force` to replace an existing local installation. To remove:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1 -Uninstall -Force
```

This installs into `$HOME/plugins/controlflow-codex` and registers a local
marketplace entry at `$HOME/.agents/plugins/marketplace.json`.

## Deterministic Validator

The package keeps a slim validator for plan structure and the combined verify
verdict. It is the only executable logic in the plugin.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate-plan.ps1 `
  -RepoRoot . `
  -PlanPath plans/my-task-plan.md `
  -RequireVerifyVerdict
```

It checks the plan header, required sections, lifecycle heading order, the seven
semantic-risk rows (each exactly once), and (with `-RequireVerifyVerdict`) the
`verify-verdict.md` shape and status.

## Использование (кратко)

1. Для неясной задачи сначала нативный `/plan`.
2. `$controlflow-plan` — сохранить строгий план.
3. `$controlflow-verify` — проверить план до реализации.
4. После `APPROVED` пусть Codex выполнит план нативно.
5. Нативный `/review` для общего code review.
6. `$controlflow-review` — соответствие плану.

Для очевидной правки в одном-двух файлах используйте обычный Codex без
дополнительных артефактов.

## License

MIT — see [LICENSE](LICENSE).