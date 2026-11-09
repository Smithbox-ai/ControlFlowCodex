# Approved audit fixes design

Approved by the user on2026-11-09, including32MiB per stream for V4 checks.
Source baseline:a8088d70305f365b4973cd261da700fa1c6ca5a0.

## Decisions
- F1: preserve terminal V4 identity at interrupt publication/read and active-run replacement; legacy V3 semantics remain.
- F2: ordinal unique sets for QA/check IDs, human waits and carried paths; old incomplete QA becomes stale. Recover unresolved case-distinct waits from immutable current-epoch review events.
- F3: select absolute physical application path before any Git invocation; logical/physical ancestor .git boundaries reject repository-controlled selected paths and link targets. Keep native argv and legitimate installed Git.
- F4: completion rechecks ledger revision/evidence without nested writer locks; concurrent publication rejects PASS. No guarantee after return.
- F5: V4 checks cap stdout and stderr separately at33554432 bytes; exact limit passes, +1 records FAIL/OUTPUT_LIMIT_EXCEEDED, bounded prefixes and observed counts, then cleans owned descendants. No global Git/V3 cap. Report parsing and archival consume the same bounded snapshot; preserve XML encoding/DTD rules, JSON BOM handling, source scope and thresholds.
- F6: skip only repository workflow assertion when absent from package. Universal and NativeLegacy CLI scenarios remain executable; full portable runner is verified on Universal. NativeLegacy preparation reads its existing compatibility manifest when root manifest is intentionally absent.
- F7: route through original Pester wrapper before executing suites, so each suite runs once; missing/failing Pester and plain failures propagate.
- F8: document runtime/schema4 separately from package candidate version without a version bump.

## Verification
Negative public-API regressions must fail on the old defects and pass on the fix. Five focused controlled mutations in temporary copies must each be detected; this is not a Stryker score.
Verify existing and new suites through actual Pester once, full Universal portable runner, targeted NativeLegacy CLI, Pilot/Release/Diagnostics corpus validation and independent diff review.
Native host callbacks/cwd, Linux/macOS and minimum PowerShell7.4 execution remain outside local Windows evidence.

## Delivery
One production writer; preserve initial index/worktree ownership. No commit, push, release or installed-plugin update requested. Human final acceptance is separate from approved design.
