# Opt-in v4 migration

V3 remains default and retains executable coverage and review semantics. Use a
new contract and a new run; historical state, approvals and captures are never
migrated. Unknown versions fail closed. Runtime and active pointer versions must
match exactly; replacing a run's contract with a different version is rejected.

```powershell
pwsh -NoProfile -File scripts/migrate-contract.ps1 -Path <v3-contract> -OutputPath <new-file> -TaskId <new-task> -TargetVersion 4.0.0
```

The result is draft with commit mode none. Inspect domain/risk, goal/scope,
criterion/check mappings, review policy and capabilities; collect new phase
artifacts and decisions. Move the reviewed contract to the new task's canonical
external storage path before starting. Default migration remains v2 to v3.

Do not edit old state.json or copy APPROVED. New source work must await final
preflight. Read [v4 interfaces](v4-runtime.md) for promotion and re-entry.

Rollback stops current work lawfully and disables v4 for new runs. Installing an
older package is a separately authorized action, and it must not adopt a v4
pointer. User source changes are never automatically reverted.
