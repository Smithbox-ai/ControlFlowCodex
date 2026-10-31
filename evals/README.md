# ControlFlow v3 evaluation

The development harness executes neutral Git repository tasks with the native
Codex CLI, grades actual file/test/index/commit outcomes, and collects root and
linked-child usage. It compares paired native and v3 trials only when required
fixture, model, budget, sandbox, approval and untrusted-project provenance is
complete. Missing evidence remains incomplete.

The executable catalog contains 55 release cases and a 12-case pilot. Separate
critical-risk diagnostics require independent offline annotations before
semantic recall can be measured. The synthetic repositories and reference
repairs validate the graders; they do not establish production quality.

Unpaid checks:

```powershell
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Pilot -ValidateOnly
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Release -ValidateOnly
pwsh -NoProfile -File evals/run-risk-diagnostics.ps1 -RepoRoot . -ValidateOnly
pwsh -NoProfile -File tests/e2e-evals.tests.ps1
```

Model execution requires explicit authorization, `-Execute`, a new evidence
directory, pinned native settings and positive budgets. Account usage limits
and native permission controls remain binding. Actual startup evidence must
prove plugin isolation and the v3 SDK entry injection; availability alone is
insufficient. The current host pilot remains on hold for unresolved ambient
plugin isolation and the rejected follow-up SDK startup probe.

See [E2E.md](E2E.md) for execution, usage and comparison requirements,
[E2E-CACHE.md](E2E-CACHE.md) for owned native cache preparation, and
[RISK-DIAGNOSTICS.md](RISK-DIAGNOSTICS.md) for independent risk review.

The old static artifact scorer, seven JSON scoring cases and static baseline
were removed. Prior captured observations stay preserved; they are not
silently converted into complete v3 evidence. Evaluation scripts are not
plugin runtime dependencies.

## V4 readiness boundary

The existing paid paired harness remains native/v3; it must not silently relabel
V4 as V3 or claim isolation. V4 model trials are BLOCKED pending a separately
authorized concrete budget, pinned inventories/settings and proven absence of
ambient treatment leakage. During this implementation session, session-path
reads are forbidden; the existing rollout collector must not be invoked.
Documented `exec --json` stdout can supply root turn usage without history reads,
but does not prove all child usage or actual injected skills/policies. A future
telemetry adapter must preserve those unknowns and pass strict provenance checks.

`New-E2EReviewMetrics` and `Measure-E2EReviewMetrics` add optional active human
review, decision wait, re-entries, packet size, rework and lead-time measurements.
They distinguish manual/instrumented/missing sources, show measured sample
counts and never impute missing values as zero. They do not collect or invent
measurements automatically. Existing success, false-completion and token metrics
remain. Synthetic outcomes are not production CFR/recovery metrics.
V4 offline treatment preparation, bound runtime receipts, stdout-only collection,
and schema-2 comparisons are described in [V4-ADAPTER.md](V4-ADAPTER.md).
Both stdout arms currently block model execution because native provenance and
ambient isolation remain unverified. Preparation and synthetic fixtures are not
paired-trial evidence. Legacy native/V3 collection remains separate.

