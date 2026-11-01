# Migrate an older contract to V4

All new runs use contract/runtime `4.0.0`. Existing V3 runs remain readable and
complete under their original rules, visibly marked `legacy_semantics`; they
are not silently promoted. Public run creation rejects a V3 contract before
initializing run storage. The compatibility schema under `schemas/compat/` is
for those existing runs, read-only validation and migration, not new V3 work.

The migration command accepts an external V2 or V3 contract and writes a new
V4 draft. Use a new output path and task ID:

```powershell
pwsh -NoProfile -File scripts/migrate-contract.ps1 -Path <older-contract> -OutputPath <new-v4-file> -TaskId <new-task>
```

The default and only target is `4.0.0`; an explicit `-TargetVersion 4.0.0` is
equivalent. `-BaselineCommit <sha>` can supply the reviewed baseline for the new
task. An existing output file is rejected rather than overwritten. Migration
never changes the input contract, an old `state.json`, active pointer, source
files, captures or decisions.

The result has `contract_status: draft` and `commit.mode: none`. Review its actual
goal, scope, domain/risk, criteria/check mapping, assumptions and capabilities.
V2 text-only checks do not establish criterion coverage automatically. Resolve
the new task's canonical external `contract_path` with `get-storage-paths.ps1`,
then place the reviewed draft there and start a new V4 run. Collect new context,
design decisions, QA baseline and implementation plan; finalize and pass
preflight before any new owned code or test edits. A schema-valid draft grants
no implementation or completion authority.

No approval, final review, baseline capture or successful check is reused.
Changing `schema_version` inside historical state is not migration. Pending
interrupt-notification and phase-artifact wire versions are independent formats;
their version numbers do not select an older product workflow.

To return to a previous package, stop current work lawfully, preserve its state
and reinstall the previously verified artifact using its actual flavor. There
is no `-Rollback` flag or automatic V4-to-V3 state conversion. An older runtime
must not adopt a V4 active pointer, and user source changes are never reverted
automatically. See [installation and rollback](installation-v4.md) and
[V4 interfaces](v4-runtime.md).
