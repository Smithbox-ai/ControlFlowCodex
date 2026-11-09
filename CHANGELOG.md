# Changelog

## Unreleased

- Preserve V4 terminal lifecycle across late interrupts, recover case-distinct
  human waits and bind all ordinal QA/check identities without collapsing case.
- Resolve trusted Git outside the worktree before execution and reject stale V4
  completion observations after concurrent ledger publication.
- Cap V4 stdout/stderr independently at 32 MiB and parse/archive the same bounded
  report snapshot; preserve legacy defaults and XML/JSON encoding behavior.
- Run portable CLI checks without repository-only workflows, prepare NativeLegacy
  candidates from their compatibility manifest, and run Pester suites once.

- Recheck source and contract before completion and state publication, reject
  reserved V4 design-review IDs, and automatically hash mutation scope inputs.
- Resolve relative filesystem paths against PowerShell location; preserve path
  protections. Make mutable JSON replacement reader-safe on Windows, with
  bounded sharing retries and optional interrupt turn IDs.
- Publish inventory sidecars with release archives and pin release actions and
  Pester to immutable versions and verified package bytes.

- Require an explicit run/skip/unsupported sensitivity assessment for newly saved
  code-judged QA plans, with scoped checks and bounded acceptance. Guide bugfix
  regressions through an old-defect negative control; preserve human-only/light
  routes and historical artifact readability. Existing tools remain a prerequisite.
- Require positive project-chosen thresholds for required available mutation
  profiles, bind Stryker source and exact file scope to captures, and report
  profile failures, timeouts, stale and missing evidence with per-check reasons.
  Optional unthresholded mutation reports are measurements, not accepted sensitivity.

- Read JUnit/NUnit root element names through the XML DOM, so standard `name`
  attributes cannot hide or spoof the element name in PowerShell.
- Reject unsupported JUnit nonexecution statuses and disabled counts instead of
  reporting skipped/disabled work as executed tests.
- Allow current build/diff command captures in QA bindings without a synthetic
  test report; checks with declared reports still require passing report evidence.

- Bind declared check input file hashes to captures and completion, including
  ignored files, and bound process output collection by the check deadline.
- Add a read-only readiness diagnostic and a human-readable completion-gate view,
  with explicit limits on what they can establish about host trust and callbacks.
- Add a first-run guide and prepare release archives with SHA-256 and versioned
  changelog notes. Release artifacts do not certify behavioral or callback evidence.

- Move contracts, evidence, locks and active markers outside Git projects into
  `CODEX_HOME/controlflow`, with an optional external `CONTROLFLOW_STATE_ROOT`.
  Preserve worktree/session binding and fail explicitly on unavailable storage;
  never fall back to project folders or add ignore rules. Old runs remain audit
  data and require a reviewed contract and fresh evidence for a new external run.

- Preserve literal Unix backslashes in Git source fingerprints and test fixtures.
  macOS CI uses the runner's temporary directory while retaining installer
  rejection of linked/reparse paths.
- Resolve the contract runner path during Pester test execution so Pester 5's
  separate discovery phase does not leave the path unset.
- Use native temporary paths in E2E marketplace discovery fixtures on every OS.
- Preserve the caller's native exit status across E2E process cleanup probes,
  while retaining the actual child exit code in its process receipt.

- Favor the smallest coherent implementation with evidence for new structure.
  Profile preflight and conformance review check material complexity beyond
  accepted scope; safe light docs retain a compact route without extra readers.

## 4.0.0-rc.3 - installer lifecycle candidate

- Preserve the installed flavor for ordinary `install.ps1 -Force` upgrades and
  report its selection; explicit cross-flavor changes still require both flags.
- Support strictly validated NativeLegacy staging from canonical Universal source,
  while keeping explicit fresh NativeLegacy selection and capability restrictions.
- Retain complete previous source and exact registration bytes for recoverable
  upgrade/uninstall, preserving unknown files and custom marketplace fields.
- Make missing uninstall a no-op, support exact self-uninstall, and reject foreign
  or duplicate registrations and flavor changes between inspection and lock.
- Document local-source versus native cache/trust removal and add lifecycle
  regressions. Native callback/trust acceptance remains separate from packaging.

## 4.0.0-rc.2 - V4 candidate, not yet published

- Make contract/runtime 4.0.0 the default and only new-run workflow. Keep
  existing V3 runs under visibly marked legacy semantics; relocate the strict
  V3 schema to compatibility-only use and remove new V3 templates/examples.
- Migrate an external V2 or V3 contract into a separate V4 draft with commit
  mode none. Existing state, decisions, captures and user files stay untouched;
  a new task collects new evidence rather than inheriting approvals.
- Add fixed context, design, QA-before-implementation, implementation plan,
  QA recheck and review packet snapshots with exact intent/policy/input bindings.
  Preserve the safe light docs path, one writer and native reader limits.
- Require all declared code/agent/human judges. Record manual human decision
  provenance without claiming authentication; verified-human mode fails closed
  without a trusted receipt source. Waiting/rejection/interrupt remain incomplete.
- Add explicit planning epochs and lawful resume while preserving original
  foreign ownership and previously authorized carried work. Contract/source
  changes conservatively stale dependent evidence.
- Capture narrow recognized test/mutation reports with raw hashes, declared tool
  metadata and visible unsupported/incomplete states. A controlled PowerShell
  gate/ledger mutation pilot is separate from downstream project reports and
  does not establish universal PowerShell mutation-tool support.
- Preserve native Stop, SessionStart and Interrupt integration and bounded
  continuation. Bound check process collection/cleanup, require observable
  absence before cleanup acceptance, and retain fail-closed Unix errno handling.
  This is not a guarantee to kill every native background command.
- Retain distinct Universal and explicit NativeLegacy archives for the documented
  native loader limitation, with transactional staged installation and rollback.
  Refresh README, skills, migration and installation instructions for V4.
- Keep native/V4 paired preparation separate from execution. Comparative model
  execution remains blocked without complete supported provenance, context,
  child accounting and isolation; no superiority, global hard token cap or
  stable production-readiness claim is made. Final platform/native acceptance
  must bind the exact candidate bytes.

This entry describes the prepared candidate; it does not certify publication,
complete platform acceptance or isolated paired outcomes.

## 3.0.0-rc.1 - native reliability candidate

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




