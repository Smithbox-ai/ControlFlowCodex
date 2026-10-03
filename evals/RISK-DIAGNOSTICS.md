# Release diagnostic protocol

The three separate diagnostic cases audit access control, traversal, and loss of
persisted data. Their HIGH-risk criteria are declared in `release-grading.ps1`
before trials. They do not alter the frozen Pilot or 55 implementation inputs.

Validate without model calls:

```powershell
pwsh -NoProfile -File evals/run-risk-diagnostics.ps1 -RepoRoot . -ValidateOnly
```

Future paid runs use `run-risk-diagnostics.ps1 -Execute` with the same explicit
model, effort, CLI version, native approvals/sandbox, session root, output,
per-run/batch budgets and trial parameters as `run-e2e.ps1`. The wrapper uses
that adapter and its root/child telemetry; it has no separate model runtime.

The model writes `diagnostics.json`. Collection proves artifact shape, actual
source preservation and hashes. It does not establish semantic correctness.
Nonempty findings remain **not measured** until a human independently reviews
each predeclared criterion, including explicit misses for empty reports. Missing
artifacts, source changes, invalid findings or incomplete telemetry do not
become successful diagnostic observations.

Place offline annotations outside both model repositories, at
`<reviews>/<native|v3>/<case-id>/<trial>.json`. Each annotation must contain:

```json
{
  "schema_version": "1.0.0",
  "case_id": "diagnostic-auth",
  "reviewer_kind": "human",
  "reviewer": "independent-reviewer-id",
  "reviewed_at": "2026-10-03T00:00:00Z",
  "artifact_sha256": "SHA256 of actual diagnostics.json",
  "result_sha256": "SHA256 of immutable trial result.json",
  "criteria_sha256": "criteria_sha256 collected in immutable trial result",
  "sources": {"src/authorize.ps1": "SHA256 of actual unchanged source"},
  "criteria": [{
    "id": "AUTH-1",
    "identified": true,
    "finding_index": 0,
    "rationale": "Explain whether the cited finding identifies the actual cause, impact and relevant remedy."
  }]
}
```

Use `identified: false` for a miss. Reviewer identity is recorded provenance,
not cryptographic proof of independence; the benchmark operator must arrange a
real independent reviewer. Category/location matching only validates the cited
evidence. It never substitutes for reviewing mechanism, impact and mitigation.
Reviewers should be blinded to the arm when assessing findings.
Use lowercase SHA-256 values. The catalogue, source and diagnostic hashes are
captured under `risk_diagnostics` in the immutable result. Compute the result
hash with `(Get-FileHash <result.json>).Hash.ToLowerInvariant()`. Comparisons
reject edited post-run artifacts or sources even if a new annotation supplies
their replacement hashes; annotations cannot redefine captured observations.

```powershell
pwsh -NoProfile -File evals/compare-risk-diagnostics.ps1 `
  -NativeDirectory <native-cohort> -V3Directory <v3-cohort> `
  -ReviewsDirectory <offline-reviews> -OutputPath <new-comparison.json>
```

Comparison reports collection and semantic coverage separately from recall and
task success. Complete recall requires all requested cases/trials, compatible
paired provenance, completed native telemetry and valid bound annotations.
Each native result must also match its cohort manifest's model, effort, host,
CLI version, native permission settings and budgets; absent provenance fails
closed. Keep both cohort manifests and native results unchanged.
Subset recall is explicitly labelled; missing observations remain in coverage
denominators. Diagnostic production readiness is always false here: the full
release assessment must also combine implementation and safety evidence.
