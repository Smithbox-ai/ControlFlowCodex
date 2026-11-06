# Project Audit Fixes Implementation Plan

> **For agentic workers:** Apply TDD and independent review; preserve other writers' files.

**Goal:** Fix all validated defects and weaknesses from the project audit.

**Architecture:** Extend existing path, JSON publication, check-input and gate
helpers. Keep runtime/schema version and V3 behavior, with explicit V4 validation.

**Tech Stack:** PowerShell 7.4+, .NET filesystem APIs, JSON Schema, GitHub Actions.

**Spec:** ../specs/2026-11-06-audit-fixes-design.md

## Global Constraints

- Preserve previous uncommitted mutation work and existing CRLF file conventions.
- No global cwd changes in runtime, extra tools, real-home installation or release.
- Keep transient retry bounded; persistent IO failures must never become success.
- Source consistency checks do not imply authenticated or transactional filesystem access.

## Review Focus

- Completion rejects edits both inside the gate and between gate return/publication.
- Relative paths select the intended PowerShell location even with differing process cwd.
- Ignored mutation targets and missing old input receipts cannot retain PASS.
- Reader overlap, absent turn IDs and invalid review IDs fail in the intended way.
- Release assets and pinned dependencies match the declared recovery procedure.

## Tasks

- [x] Write failing completion and contract-race tests; fix gate/publication checks.
- [x] Write failing relative-path tests; fix core and package path helpers.
- [x] Write failing interrupt/reader tests; fix mutable IO and payload handling.
- [x] Write failing reserved-ID tests; validate V4 criterion/phase names.
- [x] Write failing ignored-scope freshness tests; integrate automatic scope inputs.
- [x] Write failing release contract tests; include inventory and pin dependencies.
- [x] Integrate helper calls, run independent review and complete contract validation.

## Progress

User-approved audit scope; root owns Gates/Ledger/Contract/schema and integration.
Path, interrupt and release agents have disjoint file ownership. No commits planned.

RED/GREEN observed for wrong-cwd paths, stale source/contract/input completion,
late interrupts, sharing conflicts, omitted turn_id, reserved IDs and release
sidecars/dependency pins. Completion-race tests pass all eight boundary/change
combinations (19 assertions). Mutation inputs (11), review targets (8), interrupt
safety (24), profile status (37), relative-path cases, release and existing
affected suites pass. Review found a late ignored-input gap and native absolute
Unix path regression; both were fixed and independently rechecked with no
remaining material findings. Unix-specific regressions are conditional and
remain unexecuted on this Windows host. Full 46-suite contract run started after
all source writers became stable.

Final verification: one complete runner invocation passed all 46 suites in
declared order, exit 0, ending VALID ControlFlow contract suite. An earlier run
exposed ambiguous name-only module selection in the new relative-path test;
the test now uses the exact Import-Module -PassThru result and a duplicate-name
probe passed before the clean full rerun. Runtime was unchanged by that fix.
Pilot/Release/Diagnostics corpora validated (12/55/3 cases; no model execution).
Independent follow-up review confirmed the ignored-input and absolute-path
corrections; no material findings remain. CRLF-aware whitespace checks pass.
All work remains uncommitted; no release or real-home plugin installation ran.
