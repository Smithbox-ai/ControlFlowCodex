# Native cache preparation for development E2E

`prepare-e2e-cache.ps1` copies a frozen evaluation runtime into Codex's native
`plugins/cache/MARKETPLACE/controlflow-codex/VERSION` layout. This is a development
filesystem helper, outside the shipped runtime. It never invokes Codex, a model,
`plugin add`, authentication, a config setter or a trust API. Installation metadata
alone does not establish a valid v3 trial: native discovery and the actual exec
rollout must still prove activation, skill catalog isolation and usage collection.

Use a unique lowercase `controlflow-eval-...` namespace, at most 96 characters.
The native cache base and external receipt directory must already exist. A host
operator must explicitly authorize this one cache namespace. An existing namespace,
receipt, link/reparse ancestor or working-state payload is refused. The helper does
not replace another installation or create an authentication home.

After the native arm has written its immutable snapshot and SHA256 inventory,
prepare only those frozen runtime bytes. Pass the same marketplace name to both
arms, and pass that native snapshot as v3's `PluginRoot`:

```powershell
$marketplace = 'controlflow-eval-' + [guid]::NewGuid().ToString('N')
$nativeOut = '/absolute/path/to/native-arm-evidence'
$v3Out = '/absolute/path/to/new-v3-arm-evidence'
$cacheArgs = @{
  NativeCacheRoot = '/absolute/path/to/existing/native/plugins/cache'
  MarketplaceName = $marketplace
  ConfigPath = '/absolute/path/to/native/config.toml'
  ReceiptPath = '/absolute/path/to/evidence/native-cache-receipt.json'
}
# The native arm used -MarketplaceName $marketplace before preparation.
./evals/prepare-e2e-cache.ps1 @cacheArgs `
  -SourceRoot (Join-Path $nativeOut 'marketplace/plugins/controlflow-codex') `
  -ExpectedInventoryPath (Join-Path $nativeOut 'plugin-inventory.json')
# Run the already-authorized, explicitly budgeted v3 arm using that frozen
# PluginRoot and MarketplaceName. This preparation command makes no model call.
```

The source must contain only `plugin.json`, `.codex-plugin`, `skills`, `schemas`,
`scripts`, `hooks`, `assets`, and `plans/templates`. File names and SHA256 values
must exactly match the declared inventory, including hidden files. Portable and
compatibility plugin identities must agree. Staging has a unique ownership marker;
the full staged tree is checked before its atomic rename into the namespace.
An external JSON receipt and `.sha256` sidecar bind the exact files/directories,
marker, source inventory, namespace and protected config state. A missing config
stays missing. Global config bytes, trust and authentication are never written.

Cleanup requires explicit `-ProcessesStopped` after the owned trial processes
have exited. CI also supplies the v3 evidence root, so the helper requires fresh
matching namespace metadata, both policy preflight receipts, discovery/debug
process receipts, each trial's version receipt, and every declared turn receipt.
Each native adapter receipt must report complete streams and verified owned
process cleanup. Evidence hashes are retained in the cleanup receipt.

```powershell
./evals/prepare-e2e-cache.ps1 @cacheArgs -Cleanup -ProcessesStopped `
  -ProcessEvidenceRoot $v3Out
```

Missing, stale or incomplete process evidence keeps the namespace intact and fails
cleanup readiness. A changed config, cache byte, directory, ownership marker or
receipt also refuses recursive deletion. Do not restore global config to force
cleanup; preserve the evidence and resolve unrelated drift with its owner. The
manual assertion without `ProcessEvidenceRoot` is intended only for an operator
who has independently verified process exit. It never kills unrelated processes.
SHA256 binding detects changed observations; it is not cryptographic authentication
of a hostile receipt writer.

The opt-in `paired-e2e` CI job uses its disposable runner's existing native
authentication setup, a new namespace per job, and the native arm snapshot for
v3. Cleanup runs in `finally` and requires the owned adapter evidence above.
Incomplete collection fails the job; preserved artifacts include receipts and
comparison data. The scheduled deterministic job runs the isolated fake-cache
smoke tests without CLI, authentication, model calls or host cache writes. Actual
paid v3 activation is still subject to native exec catalog verification.
