# Mutation Evidence Implementation Plan

> **For agentic workers:** Use test-driven development and independent review.

**Goal:** Implement the approved mutation audit recommendations.

**Architecture:** Extend existing V4 QA/report/profile mechanisms. Keep one
writer per file and use existing capture freshness and QA scenario bindings.

**Tech Stack:** PowerShell 7.4+, JSON Schema, bundled contract tests.

**Spec:** ../specs/2026-11-06-mutation-evidence-design.md

## Global Constraints

- No universal mutation threshold and no automatic tool installation.
- Preserve historic immutable artifacts and V3 reading semantics.
- Literal repository-relative report scope; source matching is consistency,
  not authenticated proof of tool execution.
- No commits, pushes, installation or production effects.

## Review Focus

- Report-relative paths in nested working directories must resolve correctly.
- Unrelated files, traversal, missing scoped files and different source fail.
- Pending/invalid-only/zero-mutant reports do not become accepted evidence.
- Old failed/stale captures must not be summarized as successful or never run.
- Human-only/light docs and optional measurements remain proportionate.

## Tasks

- [x] Add failing parser/capture regressions, then bind Stryker scope and source
  during capture; explicitly expose configured acceptance vs measurement.
- [x] Add failing QA assessment/threshold tests, then schema and contract guards;
  integrate the new QA-save guard and keep saved historical reads unchanged.
- [x] Add failing profile-summary tests, implement precise aggregation, and
  replace review-packet summary generation with the tested helper.
- [x] Run skill behavioral baseline, improve entry/plan/verify/review guidance
  and documentation, then validate with the same scenarios and contract tests.
- [x] Register new suites, run targeted and complete contract suites, review the
  full diff independently and resolve material findings before delivery.

## Progress

Planning complete; approved scope comes from the user's implementation request.
Independent file ownership: root Ledger/report tests; policy agent Contract/
schemas/QA helper; summary agent Gates/summary tests; guidance agent skills/docs.

RED observed for unrelated report acceptance, historical unbound captures,
missing assessment/threshold, inaccurate summary states and absent skill policy.
Targeted suites and baseline/recheck scenarios exercise the implemented paths.
Verification complete: all 41 contract suites passed across two stages, including
116 assertions in four new suites. The first 16 suites passed before a new-test
module-name ambiguity stopped the run. The test helper now selects the exact
checkout module; a duplicate-name regression passed, followed by the remaining
25 suites in runner order with a foreign same-name module loaded. Runtime did not
change during that correction. The complete installer/package checks passed.
Pilot (12), Release (55) and Diagnostics (3) corpora validated without model runs.
Independent whole-diff and follow-up test-isolation reviews found no material
issues. CRLF-aware whitespace validation passed. No commit or installation into
the user's real plugin home was performed.
