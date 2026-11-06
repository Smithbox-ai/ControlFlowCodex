# Install ControlFlow V4

Package candidate `4.0.0-rc.3` starts new tasks with contract/runtime `4.0.0`.
It is an installable candidate, not a stable or comparative-quality claim.
Git and PowerShell 7.4 or newer are required; 7.6.9 is tested and recommended.
Start from the verified artifact and retain
its exact ZIP, `.zip.sha256` checksum and `.zip.inventory.json` inventory sidecars
together for upgrades, recovery and rollback.

## Select the host flavor

- `Universal` is the default package and retains canonical root `plugin.json`.
- Codex `0.166.0-alpha.5.1` requires explicit `NativeLegacy` for bundled hooks.
  It uses `.codex-plugin/plugin.json`, with the same shared runtime, four skills
  and assets; only the root manifest is omitted. It does not grant hook trust.

Fresh canonical/Universal source defaults to Universal. Select NativeLegacy
explicitly for the host above; a fresh NativeLegacy artifact also requires that
explicit selection. For an existing owned target, omitted `-Flavor` preserves
and reports its current format. No host autodetection or cross-flavor fallback
is performed. See [host compatibility](release.md#explicit-native-compatibility-flavor-candidate).

## Verify, extract and install

The NativeLegacy artifact is `controlflow-codex-4.0.0-rc.3-native-legacy.zip`;
Universal is `controlflow-codex-4.0.0-rc.3.zip`. Both extract a top-level
`controlflow-codex/` directory. Replace the example paths with your downloaded
artifact and a new extraction directory; compare the hash with the trusted
checksum before extraction:

```powershell
$archive = 'C:/Downloads/controlflow-codex-4.0.0-rc.3-native-legacy.zip'
Get-FileHash -LiteralPath $archive -Algorithm SHA256
Expand-Archive -LiteralPath $archive -DestinationPath 'C:/Temp/controlflow-rc3'
$source = 'C:/Temp/controlflow-rc3/controlflow-codex'
pwsh -NoProfile -File "$source/scripts/install.ps1" -Flavor NativeLegacy -Force -DryRun
pwsh -NoProfile -File "$source/scripts/install.ps1" -Flavor NativeLegacy -Force
```

For Universal use its archive and `-Flavor Universal` in both installer calls.
`-HomeRoot <path>` selects an isolated home for a test installation. Dry-run
validates paths, ownership, flavor and inventory without changing the target or
creating a lock. Actual installation stages and validates the selected content,
replaces only the owned plugin tree and preserves custom registration fields and
unrelated marketplace entries. Canonical Universal source can stage NativeLegacy
without its root manifest; the shared bytes and strict NativeLegacy constraints
are checked. A NativeLegacy artifact cannot manufacture a Universal manifest.
Conversion dry-run may use temporary validation staging, removed afterward; it
does not write target, marketplace or lock files. On Unix use a physical temporary
directory when the default temporary path traverses a symlink.
It does not install dependencies or alter native security settings.

Enable/select the local plugin with your Codex host's supported plugin flow.
Where that host requires cache refresh, use its supported `codex plugin add`
flow for the installed source; do not edit cache files manually. Review `/hooks`
and grant trust to the exact current ControlFlow definitions yourself. Install,
enablement, discovery and actual callback verification are separate steps.
Untrusted or unsupported callbacks require explicit manual fallback, not a claim
of automatic enforcement. See [hooks and fallback](hooks.md).

From the extracted source, `scripts/doctor.ps1 -RepoRoot <repo>` provides a
read-only storage/repository diagnostic. It does not prove native activation,
trust, callback delivery or write permission. Invoke a task with
`$controlflow-codex:controlflow <your task>`; no V4 toggle is needed.

## Upgrade and rollback

Before replacing an existing installation, retain its exact verified archive,
both `.zip.sha256` and `.zip.inventory.json` sidecars, flavor, registration and
necessary state. Existing owned targets
require `-Force`. For an ordinary upgrade, `scripts/install.ps1 -Force` preserves
the installed flavor; a real change also requires explicit `-Flavor`. The
installer replaces the active tree cleanly and retains its entire previous
contents under `plugins/.controlflow-codex-backup-<id>/source/`. Exact previous
registration bytes are kept alongside as `marketplace.json`. The output reports
the recovery directory; inspect it before manually cleaning old backups. Unknown
custom files are retained there, not silently deleted or copied into the active
executable package. Failure before registration publication restores the previous
active tree. Native cache and hook trust remain the host's responsibility.

For rollback, extract the preserved previous artifact to a fresh directory and
run **that artifact's** installer with its matching `-Flavor` and `-Force`.
Refresh through the supported native plugin flow and verify the restored bytes.
There is no `-Rollback` parameter. Keep new V4 runs stopped when returning to an
older runtime; never rewrite a V4 pointer to make that runtime adopt it. This
procedure does not revert user source changes or delete historical run data.
## Uninstall and reinstall

```powershell
pwsh -NoProfile -File scripts/install.ps1 -Uninstall -Force -DryRun
pwsh -NoProfile -File scripts/install.ps1 -Uninstall -Force
```

The mode removes only the owned active source and matching local marketplace
entry, retaining the recovery directory above. It preserves siblings, custom
marketplace metadata, configuration and external run data. Foreign/duplicate
matching-name registrations and unowned/corrupt targets fail before mutation.
Missing source and registration is a no-op. Exact self-uninstall is supported;
parent/child, link and namespace aliases remain rejected.

This local installer does not remove native cache or grant/revoke hook trust.
For the inspected Codex CLI, `codex plugin remove controlflow-codex@local-personal`
is the separate supported native uninstall/cache operation; inspect its current
help before use. Use it when deactivation of the native cached plugin is intended.
Do not delete `.codex` or reset trusted hashes. To reinstall from this checkout
for Codex0.166.0-alpha.5.1, explicitly use `-Flavor NativeLegacy -Force`, then use
the host's supported plugin-add flow and review any new exact hook trust request.

## Existing tasks and acceptance

Existing V3 runs retain explicit legacy semantics. New legacy runs/templates
are removed; [migration](migration-v4.md) creates a separate V4 draft and new
evidence, with no copied approvals or captures.

Installation success alone does not establish functional acceptance. Platform/package
validation and native smoke apply only to their recorded source/package/host.
Stable publication and comparative claims have separate evidence requirements.
Verified-human receipts and complete isolated paired model
telemetry are unavailable and fail closed. The current [runtime limits](v4-runtime.md#verification-and-release-limits)
and [evaluation guide](../evals/E2E.md) distinguish functional evidence from
comparative outcomes and production readiness.
