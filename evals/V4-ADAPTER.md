# Paired V4 adapter: offline preparation and explicit limits

The V4 adapter is separate from the legacy native/V3 rollout collector. V3
commands, result schema 1.0.0, and comparison defaults retain their semantics.
V4 results/comparisons use schema 2.0.0 and explicit `v4` identities.

## Unpaid preparation

Run with PowerShell 7, replacing the paths with new local directories:

```powershell
pwsh -NoProfile -File ./evals/run-e2e.ps1 -RepoRoot $repo `
  -Variant v4 -Collector stdout-jsonl -PrepareOnly `
  -CaseIds readme-title -OutDir $newEvidenceDirectory
```

This creates an ordinary fixture repository, an external state root, a pinned
candidate inventory digest, and a treatment request bound to the fixture's
initial source/baseline and task ID. It performs no Codex CLI calls, model turns,
installation, hook trust changes, or session-history reads. Do not reuse the
output directory. Treat this output as preparation, not completed trials.

`New-E2EV4Treatment` returns the explicit V4 prompt and only the
`CONTROLFLOW_STATE_ROOT` environment override. It never overrides identity/auth
homes. The treatment requires the actual native thread ID; it does not create
manual fallback runs or supply human approvals. Keep the referenced candidate
bytes unchanged. Rebuild preparation if that candidate changes.

`Read-E2EV4RuntimeReceipt` uses the candidate's existing public runtime APIs to
validate active task/run/thread identity, initial source, exact contract,
intent/policy, immutable artifacts, freshness and completion gate. Its assurance
is **local runtime integrity**. Draft, rejection, human-wait, and missing evidence
remain visible. A local receipt, hash, or manual human record never authenticates
native context or human identity. The receipt does not grant external authority.

## Collectors and execution block

`Get-E2ECollectedUsage -Collector stdout-jsonl -Capture $capture` accepts captured
stdout and process status only. It never falls back to a session directory.
Recognized root events are validated for sequence, terminal usage, nonnegative
counts, unique item identity, completed items, and process collection/cleanup.
Missing or invalid root accounting is not zero. Observed root usage is reported
separately from total trial usage.

The currently implemented native protocol does not establish:

- Actual injected plugin/skill catalog and exact selected entry.
- Resolved native model, approval/reviewer/sandbox policies.
- A closed child execution tree with complete child usage.
- Isolation from all ambient plugin/managed sources.
- A hard in-flight token budget including children.

Consequently `Get-E2EProtocolReadiness` returns `UNSUPPORTED` and `may_launch=false`
for stdout-only collection. `Invoke-E2ETrial` and `run-e2e.ps1 -Execute` block
**before any CLI/model/session access** for both stdout arms. There is no local
boolean, capability JSON, model statement, or approval flag that bypasses this
check. Future support requires an implemented, independently validated native
source and new negative tests. Model-trial authorization alone does not supply
that technical capability. The legacy collector must not be used where session
history access is prohibited.

## Comparisons

```powershell
pwsh -NoProfile -File ./evals/compare-e2e.ps1 `
  -NativeDirectory $nativeEvidence -V4Directory $v4Evidence `
  -OutputPath $newComparisonPath
```

Native/V4 records must explicitly use schema 2.0.0. V3 records cannot be relabeled
as V4. Duplicate identities and mismatched paired settings/budgets/provenance
are rejected. Until native capability is implemented, V4 comparisons remain
`BLOCKED`, metrics incomplete, deltas null, and `production_ready=false`, even if
caller-authored fields claim `complete=true`. Missing measurements are not zero.

## Deterministic validation

```powershell
pwsh -NoProfile -File ./tests/e2e-v4-adapter.tests.ps1
pwsh -NoProfile -File ./tests/e2e-v4-cli.tests.ps1
pwsh -NoProfile -File ./tests/run-contract-tests.ps1
```

These tests use fixture events and real isolated runtime receipts, never model
trials or real native callbacks. They cannot demonstrate host hook trust,
effective context isolation, comparative benefit, or production readiness.
