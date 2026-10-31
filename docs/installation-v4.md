# Install ControlFlow V4

Package candidate `4.0.0-rc.2` starts new tasks with contract/runtime `4.0.0`.
It is an installable candidate, not a stable or comparative-quality claim.
Git and PowerShell 7.4 or newer are required; 7.6.9 is tested and recommended.
Start from the verified artifact and retain
its ZIP, SHA-256 and `.inventory.json` sidecars.

## Select the host flavor

- `Universal` is the default package and retains canonical root `plugin.json`.
- Codex `0.166.0-alpha.5.1` requires explicit `NativeLegacy` for bundled hooks.
  It uses `.codex-plugin/plugin.json`, with the same shared runtime, four skills
  and assets; only the root manifest is omitted. It does not grant hook trust.

Choose the flavor before installation. There is no implicit fallback between
formats. See [host compatibility](release.md#explicit-native-compatibility-flavor-candidate).

## Verify, extract and install

The NativeLegacy artifact is `controlflow-codex-4.0.0-rc.2-native-legacy.zip`;
Universal is `controlflow-codex-4.0.0-rc.2.zip`. Both extract a top-level
`controlflow-codex/` directory. Replace the example paths with your downloaded
artifact and a new extraction directory; compare the hash with the trusted
checksum before extraction:

```powershell
$archive = 'C:/Downloads/controlflow-codex-4.0.0-rc.2-native-legacy.zip'
Get-FileHash -LiteralPath $archive -Algorithm SHA256
Expand-Archive -LiteralPath $archive -DestinationPath 'C:/Temp/controlflow-rc2'
$source = 'C:/Temp/controlflow-rc2/controlflow-codex'
pwsh -NoProfile -File "$source/scripts/install.ps1" -Flavor NativeLegacy -Force -DryRun
pwsh -NoProfile -File "$source/scripts/install.ps1" -Flavor NativeLegacy -Force
```

For Universal use its archive and `-Flavor Universal` in both installer calls.
`-HomeRoot <path>` selects an isolated home for a test installation. Dry-run
validates paths, ownership, flavor and inventory without changing the target or
creating a lock. Actual installation stages and validates the selected content,
replaces only the owned plugin tree and preserves unrelated marketplace entries.
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
inventory, flavor, registration and necessary state. Existing owned targets
require `-Force`; changing flavor also requires explicit `-Flavor`. The installer
replaces the entire owned tree, so obsolete files and a previous root manifest
cannot remain. Failure before registration publication restores the previous
installation. Native cache and hook trust remain the host's responsibility.

For rollback, extract the preserved previous artifact to a fresh directory and
run **that artifact's** installer with its matching `-Flavor` and `-Force`.
Refresh through the supported native plugin flow and verify the restored bytes.
There is no `-Rollback` parameter. Keep new V4 runs stopped when returning to an
older runtime; never rewrite a V4 pointer to make that runtime adopt it. This
procedure does not revert user source changes or delete historical run data.
To uninstall an owned installation, use its installer with `-Uninstall -Force`
and the matching flavor.

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
