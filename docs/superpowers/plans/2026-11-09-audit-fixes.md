# Approved Audit Fixes Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; root is the only production writer. Readers inspect independent boundaries and the final diff.

**Goal:** Implement approved F1–F8 and demonstrate negative regressions, compatibility and bounded capture behavior.
**Architecture:** Keep the existing Core modules and CLI adapters. Add narrow helpers for ordinal sets, terminal V4 identity, trusted Git resolution and bounded binary capture; preserve public contracts and legacy paths.
**Tech Stack:** PowerShell7.4+/.NET; local verification PowerShell7.6.9 Windows; Pester5.9.1.
**Spec:** ../specs/2026-11-09-audit-fixes-design.md (approved2026-11-09).

## Global Constraints
- One production writer; at most2 concurrent read-only readers.
- No commit/push/release/installed-plugin update requested.
- V4 capture: 33554432 bytes separately for stdout and stderr; exact limit succeeds, +1 fails with OUTPUT_LIMIT_EXCEEDED metadata and status FAIL.
- Legacy V3 check/process behavior and ordinary Git output defaults remain unchanged.
- Existing report32MiB acceptance limit remains; parse/archive one immutable bounded byte snapshot.
- XML encoding/DTD prohibition, Stryker UTF8/scope/threshold behavior and historical receipt reads stay compatible.
- No new status enum, runtime schema or dependency.
- Optional CONTROLFLOW_TEST_PROGRESS_PATH mirrors existing suite progress to an operator log while captured stdout is held until completion; defaults unchanged.
- The Pester5 wrapper disables its unused TestRegistry fixture so execution needs no registry write permission; all actual suites remain enabled.
- Whitespace validation respects the repository's tracked CRLF/mixed files with Git core.whitespace=cr-at-eol; real trailing spaces/tabs remain errors.
- Preserve initial user index/worktree ownership; initially clean at a8088d70305f365b4973cd261da700fa1c6ca5a0.
- Native trusted callbacks unavailable: ManualFallback. Existing source baseline46 suites passed; no need rerun unchanged baseline.

## Review Focus
- Git selected from parent repository PATH when callback cwd is nested; canonical link targets must be checked before first Git invocation (Task2).
- Interrupt before final completion check rejects completion; after durable terminal publication does not reopen V4, including closed BLOCKED (Task1).
- Case-distinct QA/check/human target IDs and Unix paths must stay distinct through promotion/resume (Task1).
- Ledger update during direct gate final observation invalidates PASS without nested writer lock (Task3).
- Fast overflow, both streams, child cleanup, exact byte boundaries, report swapping and UTF16 XML must preserve bounded truth (Task4).

## Task1: terminal and ordinal identity (F1/F2)
Files: scripts/lib/Ledger.ps1, Interrupts.ps1, Git.ps1; new tests/audit-runtime.tests.ps1 -Case Terminal|Identity.
Interfaces: Test-CFV4TerminalState($State) bool; Get-CFUniqueSorted($Values) ordinal unique string array.
- [ ] Add assertions for completed/cancelled + late interrupt, manually present late mailbox, closed BLOCKED session replacement, retained V3 resume behavior.
- [ ] Add check-1/Check-1 and C1/c1 QA binding freshness, pending human targets; Unix case-sensitive carried paths.
- [ ] Run selected regressions and observe pre-fix failures.
- [ ] Gate terminal policy on schema4; check writer, reader, active pointer replacement; use ordinal unique helper at QA/wait/replan sites.
- [ ] Run selected regressions + existing interrupt, promotion, decision and legacy suites.

## Task2: trusted Git selection (F3)
Files: scripts/lib/Git.ps1; tests/audit-runtime.tests.ps1 -Case Git.
Interfaces: Resolve-CFGitExecutable([string]$Root) absolute executable; canonical ancestor path helper resolves intermediate reparse targets before containment.
- [ ] Add harmless Windows cwd sentinel; PATH inside root, nested cwd ../git.exe, executable symlink/reparse target inside root, legitimate installed Git.
- [ ] Observe old bare-name behavior fail the safety assertions.
- [ ] Resolve application command and physical executable outside pre-Git filesystem ancestor .git boundary; fail explicitly before invoking any untrusted binary; use absolute path in Invoke-CFGit.
- [ ] Verify ordinary fixture Git operations, nested/linked worktree behavior and relative/provider path suites.

## Task3: direct gate ledger snapshot (F4)
Files: scripts/lib/Gates.ps1; tests/audit-runtime.tests.ps1 -Case Gate, existing completion-race tests.
Interfaces: completion result includes observed revision/evidence ref; final header re-read mismatch => LEDGER_CHANGED_DURING_GATE.
- [ ] Add deterministic public blocker and phase-review updates during final source observation; observe old PASS.
- [ ] Recheck raw state revision/evidence before PASS without taking another writer lock.
- [ ] Verify stable PASS, rejection after update, commit/complete paths remain functional.

## Task4: bounded V4 streams and report snapshot (F5)
Files: scripts/lib/Git.ps1, Ledger.ps1; tests/capture-limits-v4.tests.ps1.
Interfaces: Invoke-CFProcess optional OutputLimitBytes default0 (legacy); bounded capture helper returns prefix/counts/limit flag; Read-ControlFlowQualityReport retains -Path with optional exact byte snapshot input.
- [ ] Test exact33554432 and +1, stdout/stderr simultaneous and fast exit, descendants terminated, V3 defaults unchanged.
- [ ] Test report exact limit/+1, error no oversized raw receipt, UTF16 NUnit XML, XML DTD rejection and same-byte parsing/archive under path replacement.
- [ ] Run high-signal pre-fix cases and observe failure.
- [ ] Implement bounded async binary drains and explicit final limit flag checks, reuse process-tree cleanup; only V4 capture supplies33554432.
- [ ] Snapshot report with bounded file read; parse and raw receipt share bytes; capture oversized failure without full read.
- [ ] Verify process-timeout, quality, mutation and QA-capture suites plus new boundary tests.

## Task5: portable runner and single Pester route (F6/F7)
Files: tests/e2e-v4-cli.tests.ps1, run-contract-tests.ps1; new tests/portable-runner.tests.ps1.
- [ ] Assert package CLI suite runs absent workflow; repository workflow assertion retained.
- [ ] Use small isolated runner fixture with stubs and an actual Pester wrapper to count each suite exactly once, and prove missing/failing Pester/plain suites propagate failure.
- [ ] Observe current portability/double route failure.
- [ ] Guard only missing workflow assertion; move Pester route before suite execution with immediate return; preserve original wrapper interface and versions.
- [ ] Test Universal + NativeLegacy affected suite, source runner and actual Pester routes.

## Task6: documentation and sensitivity (F8)
Files: docs/v4-runtime.md, skills/controlflow/references/evidence.md, docs/superpowers/plans/2026-11-09-audit-fixes.md, CHANGELOG.md; tests/audit-sensitivity.tests.ps1; runner includes new suites.
- [ ] Describe terminal/ordinal freshness, trusted executable boundary, ledger snapshot race and32MiB V4 output/report behavior; remove stale candidate caption without version bump.
- [ ] Controlled temp-copy mutations: disable terminal guard, restore insensitive QA dedup, bare Git selection, skip revision recheck, remove V4 output cap. Each relevant regression must fail; originals unchanged.
- [ ] Capture source full suite once through -UsePester; corpus Pilot/Release/Diagnostics validation.
- [ ] Run full plain suite from Universal portable copy once; affected NativeLegacy checks; no model trials/network.
- [ ] Fresh read-only whole-diff security/regression review, confirm findings and repair with regressions. Preserve approved QA expectations.
- [ ] Capture final checks, QA recheck, review packet and agent criteria judgments; present concrete result for required final human review.
