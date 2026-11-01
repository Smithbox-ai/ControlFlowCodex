# Native/V4 evaluation protocol

## Current capability boundary

V4 is the default treatment and `stdout-jsonl` is the only collector. Supported
modes are `ValidateOnly`, `PrepareOnly`, `Execute` and `DiscoverOnly`; choose
exactly one. The first two are model-free. The last two currently fail closed
before CLI/model/history/cache/authentication access for both `native` and `v4`.
No local flag, supplied receipt or account authorization can implement missing
native telemetry. Retired V3 rollout generation and cache-provisioning commands
are not fallback paths.

The missing native guarantees are actual injected context/selected entry,
resolved policies, complete child usage, ambient-plugin isolation and an
enforceable in-flight token budget. Root stdout may be well-formed while those
remain unknown. See [adapter interfaces](V4-ADAPTER.md).

## Deterministic preparation

```powershell
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Pilot -ValidateOnly
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Release -ValidateOnly
pwsh -NoProfile -File evals/run-risk-diagnostics.ps1 -RepoRoot . -ValidateOnly
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -PrepareOnly `
  -CaseIds readme-title -OutDir <new-absolute-evidence-directory>
```

`PrepareOnly` creates a real fixture repository, isolated external state root,
source/baseline bindings and immutable candidate inventory. It supplies no human
approval or native session identity. The model must use the actual native thread
identity if execution becomes supported. Preparation never counts as a trial.
Reject linked paths, reused evidence directories and changed candidate bytes.

Hidden oracles execute behavior assertions on actual files, preserve protected
foreign content and validate requested commit/index outcomes. Passing `echo`,
zero assertions, unexecuted graders or a model's plausible completion statement
cannot certify an outcome. Keep oracle expectations fixed when repairing code.

## Comparison and measurements

```powershell
pwsh -NoProfile -File evals/compare-e2e.ps1 `
  -NativeDirectory <native-evidence> -V4Directory <v4-evidence> `
  -OutputPath <new-comparison.json>
```

The comparison requires explicit schema-2 native/V4 records, unique case/trial
identities and matching fixture/model/settings/budget/policy/candidate
provenance. Unknown versions, V3 records, duplicates and mismatched fields are
rejected. The current unsupported native capability keeps every pair's metrics
incomplete, success deltas null and `production_ready=false`. Caller-authored
`complete=true` never authorizes measurement. Existing historical results remain
unchanged; this CLI does not upgrade their assurance or convert their identity.

A future supported trial must be separately authorized with pinned host/model/
effort/settings, demonstrated baseline/treatment isolation, positive per-run
and total budgets, complete child accounting, a predeclared fixture corpus,
repeated paired trials and hidden oracles. A model class is not proof of reviewer
independence. The 12 pilot cases are distinct from 55 release cases; comparative
release assessment requires the declared repeats and uncertainty/per-tier
reporting. Do not infer superiority from deterministic fixture tests or a single
successful pair. Such trials are not part of plugin functional installation
acceptance while the capability remains explicitly unsupported.

Native sandbox/approval/cancellation controls remain authoritative. The adapter
must not weaken them, grant project trust, invent a human receipt, override auth
homes, install tools automatically or claim a global hard token cap. Owned local
process guards and observed budget tests validate only their stated scope.

[Critical-risk diagnostics](RISK-DIAGNOSTICS.md) separately report collection,
manual annotation coverage and semantic judgments. Missing measurements remain
missing, never zero. Production CFR/recovery needs real authorized release and
incident data; synthetic graders cannot supply it.