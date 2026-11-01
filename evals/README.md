# ControlFlow V4 evaluation

This development harness validates repository-task fixtures, hidden graders,
quality measurements and the V4 evidence adapter. The catalog contains a
12-case pilot, 55 release cases and three separate critical-risk diagnostics.
Synthetic repairs validate the graders; they establish neither comparative
benefit nor production quality.

The current treatment is V4. `run-e2e.ps1` defaults to `v4` and `stdout-jsonl`;
`native` is the baseline identity. V3 generation, rollout/session collectors
and native-cache provisioning were retired. Existing result JSON, cache data
and receipts are not modified, deleted or relabeled by this change.

Model-free checks:

```powershell
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Pilot -ValidateOnly
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Release -ValidateOnly
pwsh -NoProfile -File evals/run-risk-diagnostics.ps1 -RepoRoot . -ValidateOnly
pwsh -NoProfile -File tests/e2e-evals.tests.ps1
```

Real V4 fixtures and bound treatment requests can be prepared without invoking
Codex, installing a plugin, changing trust, reading history or calling a model:

```powershell
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -PrepareOnly `
  -CaseIds readme-title -OutDir <new-absolute-evidence-directory>
```

Both native/V4 execution arms are currently **BLOCKED**. Supported stdout
observations do not establish actual injected context, native policy provenance,
a closed child tree with complete usage, ambient-plugin isolation or an
in-flight token budget. Local capability flags, hashes and model statements
cannot replace these missing verifiers. `-Execute` and `-DiscoverOnly` stop
before any CLI, model, profile, history or cache access. The optional CI job
checks that boundary before any installation/authentication; there is no paid
trial fallback. See [E2E protocol](E2E.md) and [V4 adapter](V4-ADAPTER.md).

Schema-2 comparison records remain `BLOCKED`, metrics incomplete and deltas
null even if callers supply `complete=true`. Historical V3/schema-1 records are
rejected by the V4 comparison rather than silently converted. Plugin functional
validation and installation readiness are separate from these unmeasured
comparative outcomes.

Optional `New-E2EReviewMetrics` / `Measure-E2EReviewMetrics` track active human
review, decision wait, re-entry, packet size, rework and lead time. They label
manual/instrumented/missing sources, report sample counts and never impute zero.
They do not collect or invent measurements automatically. Synthetic outcomes
are not production CFR/recovery data.

[Risk diagnostics](RISK-DIAGNOSTICS.md) retain collection/source preservation,
manual annotations and semantic coverage separately. Complete comparative
recall still requires native provenance; annotations alone cannot supply it.
Evaluation tooling is a development dependency, not another plugin orchestrator.