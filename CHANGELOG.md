# Changelog

## Unreleased

- Preserve literal Unix backslashes in Git source fingerprints and test fixtures.
  macOS CI uses the runner's temporary directory while retaining installer
  rejection of linked/reparse paths.

- Favor the smallest coherent implementation with evidence for new structure.
  Existing MEDIUM/LARGE preflight and conformance review check material complexity
  beyond accepted scope; TRIVIAL/SMALL retain their existing workflow stages.

## 3.0.0-rc.1 — native reliability candidate

- File-to-file LARGE CLI probes and a separate critical-risk diagnostic protocol
  bind source/result/criteria evidence, independent semantic annotations and
  explicit missing-coverage reporting.
- Explicit `$controlflow` entry with TRIVIAL/SMALL/MEDIUM/LARGE progression;
  three manual skills remain available with v3 evidence binding.
- Remove retired v2 validators, drift/scoring runners, schema, templates,
  example verdicts and old fixtures. Shared packaging rejects those paths;
  migration accepts an external old contract and creates a separate v3 copy.
- Native `update_plan` progress for multi-step work: restore verified milestones,
  update after substantial changes, keep waiting work incomplete, and use honest
  textual fallback when unavailable. TODO never substitutes for evidence/gates.
- Native text invocation uses qualified `controlflow-codex:<skill-name>` names.
  Explicit-only skills are selected through the native SDK rather than presumed
  present in the implicit catalogue; defaults and entry instructions agree.
- Strict v3 contracts, separate-copy migration, immutable real check captures,
  atomic state revisions, contract/source-bound approvals and coverage.
- Separate initial user index/worktree/untracked evidence; effective source
  identity survives staging and commit; incomplete Git fails closed.
- Direct completion and prospective selective-commit gates, including actual
  required commit SHA/tree/parent verification. Commits require explicit request.
- Local Stop/resume/Interrupt adapters with lawful incomplete turn endings,
  persistent 3-identical/6-total bounds, session isolation and manual fallback.
- Portable root manifest and compatibility overlay; shared package inventory,
  transactional installation/registration, bounded Windows path handling, and
  smoke installation from the extracted release ZIP.
- Dev-only real CLI E2E adapter, 12 pilot/55 release fixtures, hidden repository
  graders, parent+child usage and strict incomplete metrics; Windows/Linux CI
  and explicit budgeted behavioral runs.

Release candidate status does not establish real A/B targets or trusted Desktop
callback support. Those require separate observed evidence; see evals and docs.

## 2.0.0 — Compact vNext

Evidence-first planning layer, no duplicated agent runtime.

### Changed
- All three skills are now **explicit-only** (`allow_implicit_invocation: false`), including `$controlflow-plan`, so they never fire on trivial work.
- `controlflow-plan/SKILL.md` compressed ~76% (15,438 → ~3,640 bytes): one durable contract, no 10 required sections, no forced seven-row risk table, no multi-candidate default.
- `controlflow-verify/SKILL.md` compressed ~70%: five adversarial questions + a compact `APPROVED | NEEDS_REVISION | REPLAN` verdict; mirage catalog and score breakdown removed.
- `controlflow-review/SKILL.md` compressed ~67%: four plan-conformance checks; generic correctness/security/style/docs delegated to native `/review`.
- New compact `plan-meta.schema.json` v2.0.0: `goal`, `tier`, `baseline` (`commit` + `dirty_paths`), `scope` (globs), `criteria`, `checks`, sparse `risks` object, optional `phases`. No `not_applicable` placeholders; no `plan_path` duplication.
- `detect-drift.ps1` rewritten: classifies changed paths as `planned` / `unplanned` against `scope`, reads `baseline` from metadata, and combines committed + staged + unstaged + untracked changes.
- `validate-plan.ps1` simplified to schema-driven v2 validation + minimal verdict shape.
- Templates collapsed from 5 pairs to 1 (`plans/templates/plan.md` + `plan.meta.json`).
- README rewritten around the ControlFlow-vs-native-Codex boundary and a three-command workflow.

### Removed
- Runtime `score-plan.ps1` (moved to `evals/legacy/` for optional offline correlation only).
- `revision-request.json` loop, `validate-revision.ps1`, and `revision-request.schema.json`.
- `snapshot-context.ps1` and full-tree `context-snapshot.json` (replaced by `baseline`).
- The v1 whole-repo custom installer (replaced by the clean-reinstall `scripts/install.ps1` above plus the native marketplace flow for published distribution).
- `release.ps1` (moved to GitHub Actions `release.yml`).
- 4 of 5 template pairs, old v1 examples/artifacts, and their contract tests.

### Added
- `scripts/install.ps1` — local clean-reinstall installer: removes any previously installed plugin files at the target, then copies the current shipped files from the project checkout (no orphans). Plus an `installer-smoke.tests.ps1` contract test.
- `evals/` behavioral regression corpus (7 cases) + `run-evals.ps1` runner (`-ValidateOnly` for PR CI, full scoring for nightly A/B).
- `evals/baseline/static-metrics.json` v1 baseline.
- `.github/workflows/eval.yml` (nightly/manual) and `release.yml` (packaging + tag).

### Targets (measured by evals, not promises)
- Agent-facing `SKILL.md` footprint: ~-73% (29,989 → ~8,140 bytes).
- Runtime workflow scripts: 7 → 2 (`validate-plan.ps1`, `detect-drift.ps1`). `install.ps1` is a local dev installer, not a runtime workflow script. Template files: 10 → 2.
- Goal: ≥25% median token reduction with no measurable critical-quality regression.

All notable changes to the ControlFlow for Codex plugin are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.x — prior to Compact vNext (historical)

### Added

- Contract test covering coding-behavior guardrails for abstraction,
  documentation, and business-logic comments.
- `schemas/plan-meta.schema.json`, metadata validation, five golden plan
  examples, and verifier verdict examples for artifact-first planning.
- Pester-compatible contract-test entry points and cross-platform CI coverage.
- Paired Markdown and JSON templates for bugfix, refactor, migration, feature,
  and docs/test-only work, plus a deterministic template contract test.
- `scripts/score-plan.ps1`, a dependency-free JSON scorer with aggregate plan
  metrics, deterministic verdicts, and contract coverage.
- `scripts/snapshot-context.ps1`, a dependency-free context snapshot command that
  captures git branch, HEAD commit, dirty flag, sorted tracked file tree, and a
  SHA-256 file-tree digest before planning.
- scripts/detect-drift.ps1, a scope drift detector that compares actual
  changed paths against planned files in plan.meta.json and classifies each
  as approved, justified, or blocking.
- scripts/release.ps1, a release workflow that updates the plugin version,
  runs contract tests, packages a zip, creates a semver tag, and smoke-installs
  the package in a clean temp directory.
- Revision-loop handoff guidance, a strict revision-request schema, and a
  dependency-free validator for validating non-approved verdicts without
  automatically applying plan changes.

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




