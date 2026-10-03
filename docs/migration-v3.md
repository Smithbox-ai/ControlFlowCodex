# V3 migration and rollback

V3 is a clean distribution: retired v2 runtime, validators, templates, examples
and artifact-scoring harness are not shipped. V3 runtime gates never activate
from v2 metadata or prose verdicts. Use a separately archived v2 distribution
if you need its old commands; do not overlay v2 files onto v3.

`migrate-contract.ps1` produces a separate v3 contract. V3 assigns unique IDs to
criteria and checks, declares each command's working directory and criterion
references, and records `commit.mode` (`none` or `required`). Inspect generated
coverage references and clarify real product uncertainties; migration cannot
infer whether an old command proves a criterion. Reuse of a v2 baseline does not
authorize ownership of initial user changes.

Validate the migrated contract, start a new session-bound run, then record
approved preflight for MEDIUM/LARGE before edits. Capture checks again. Old verdicts, check outputs, or a
different run's state are not evidence for the new run. Contract or source edits
invalidate the corresponding approvals and captures.

To roll back a candidate installed by `scripts/install.ps1`, uninstall it with
that v3 script using `-Uninstall -Force` and the same `HomeRoot`. Then install a
separately verified v2 release using that release's documented procedure. The v3
installer rejects obsolete v2 files instead of overlaying them. Retain v3 artifacts for
audit, but do not present them to v2 as valid contracts. Reinstallation updates
the plugin registration while preserving sibling marketplace entries. Hook
trust is managed by native Codex and may need review after either upgrade or
rollback. No rollback operation changes project source, stages user files,
amends a commit, or rewrites an existing contract.
