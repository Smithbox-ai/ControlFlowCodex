# Changelog

All notable changes to the ControlFlow for Codex plugin are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Contract test covering coding-behavior guardrails for abstraction,
  documentation, and business-logic comments.
- `schemas/plan-meta.schema.json`, metadata validation, five golden plan
  examples, and verifier verdict examples for artifact-first planning.
- Pester-compatible contract-test entry points and cross-platform CI coverage.

### Changed

- Strengthened ControlFlow planning, verification, and review guidance to reject
  speculative abstractions and require XML documentation plus business-logic
  comments in the dominant local language unless the user specifies another
  language.
- Non-trivial plans can now pair Markdown with
  `plans/artifacts/<task>/plan.meta.json`; verifier verdicts include a score
  breakdown and revision patch instructions.

## [1.0.0] - 2026-06-25

### Added

- Standalone repository for the ControlFlow-for-Codex plugin, extracted from the
  ControlFlow governance/eval repo.
- Compact plugin surface: 3 skills (`controlflow-plan`, `controlflow-verify`,
  `controlflow-review`), each a single self-contained `SKILL.md` with references
  inlined, plus per-skill `agents/openai.yaml` UI metadata.
- `scripts/install.ps1` with install and `-Uninstall` modes.
- `scripts/validate-plan.ps1` deterministic plan-format and verify-verdict
  validator.
- Bundled plan-format fallback while preferring repository-local canonical schema
  and template files when present.
- Inline adversarial verification (structural audit, mirage detection, cold-start
  executability) and plan-aware evidence review layered over native Codex `/review`.

### Changed

- Folded all per-skill reference documents into their `SKILL.md` to minimize file
  count; removed the separate `references/` directories.
- Merged install and uninstall into a single `install.ps1` with an `-Uninstall`
  switch.
- Slimmed execution, review-checklist, and security-review guidance to the
  ControlFlow-specific deltas, deferring generic mechanics to native Codex.

### Removed

- Router, spec, strict-workflow, planning, plan-audit, assumption-verifier,
  executability-verifier, orchestration, and memory-hygiene skills.
- Plugin-level runtime policy, approval/retry orchestration, report templates, and
  the three-artifact review gate.
- Separate `references/`, `tests/`, and `USAGE.md` files (folded into the skills
  and README).

### Native Codex Boundary

Native Codex remains responsible for Plan mode, execution, sandboxing, approvals,
subagents, generic review, goals, hooks, and memories.
