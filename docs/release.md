# Release publication

Current candidate package is `4.0.0-rc.2`, with V4-only new-run creation and
read/continue compatibility for existing V3 runs. Contract/runtime version
`4.0.0` is separate from package and artifact-wire versions. This section
describes publication checks; a candidate build or changelog entry does not
mean that a tag or GitHub Release has been published. For local installation,
upgrade and rollback, use [the installation guide](installation-v4.md).

## Explicit native compatibility flavor (candidate)

The canonical repository and default `Universal` package retain the Agent
Plugins root `plugin.json`. Codex `0.166.0-alpha.5.1` selects that format before
the compatibility manifest, but its plugin loader explicitly returns no hook
sources for `PluginManifestFormat::AgentPlugin`. Valid JSON or the presence of
`extensions.com.openai.hooks` does not establish host support. See the
[version-matched loader](https://github.com/openai/codex/blob/rust-v0.166.0-alpha.5.1/codex-rs/core-plugins/src/loader.rs)
and [manifest selection](https://github.com/openai/codex/blob/rust-v0.166.0-alpha.5.1/codex-rs/utils/plugins/src/plugin_namespace.rs).

Explicitly build `-Flavor NativeLegacy` for this host. The separately named
`controlflow-codex-<version>-native-legacy.zip` contains the same common bytes
and package inventory, excluding only root `plugin.json`. It keeps
`.codex-plugin/plugin.json`. Its SHA-256 and `.inventory.json` sidecars identify
the flavor, all file hashes, host limitation and `callbacks=NOT_RUN`. Preserve
the previous Universal ZIP; other hosts remain unverified.

Legacy skill discovery is recursive and has different MCP handling. This flavor
is restricted to exactly four existing direct skill entries, no links/reparse
points, and no MCP/apps manifest declarations or config files. An unexpected
capability is an error, not an instruction to switch formats.

```powershell
pwsh -NoProfile -File ./scripts/package.ps1 -Flavor NativeLegacy -OutputDirectory <new-dist>
# After verifying the archive hash and extracting it:
pwsh -NoProfile -File <extracted>/scripts/install.ps1 -Flavor NativeLegacy -HomeRoot <home> -Force -DryRun
pwsh -NoProfile -File <extracted>/scripts/install.ps1 -Flavor NativeLegacy -HomeRoot <home> -Force
```

Installer default is `Universal`; missing root metadata never selects legacy
implicitly. An existing installation needs explicit `-Flavor` and `-Force` to
change format. Dry-run validates without writing a lock or home files. Install
validates staging and replaces the complete owned tree, so an old root manifest
cannot remain. Registration failure restores the previous installation.

Before real rollout preserve the owned source, marketplace and hashes. Refresh
native cache only with supported `codex plugin add`, then compare the full file
set/hashes against the selected artifact. Never edit cache or trusted hashes
manually. To roll back, extract the saved previous artifact and run its installer
with its actual `-Flavor` and `-Force`, refresh through native `plugin add`, and
verify saved bytes. There is no `-Rollback` flag. Discovery, exact native trust and
real callback smoke are separate requirements for a claim of automatic host
enforcement. Verified paired/host evidence is a separate stable-publication
requirement; it is not supplied by a functionally tested installable candidate.

The release workflow runs the contract suite on Windows, Linux, and macOS,
builds and smoke-installs the extracted ZIP, and publishes a GitHub prerelease
containing the ZIP, its SHA-256 checksum, and notes from the matching versioned
section of `CHANGELOG.md`. The workflow requires the tag, manifest, archive,
and changelog version to agree. Packaging uses `git archive` of a resolved HEAD
commit in an isolated runner temporary directory, and the tag verifier requires
that same source commit. Before extraction, it compares every archive file's
Git blob hash and executable mode with the commit tree and rejects missing or
extra files. After extraction, it checks the inventory and blob bytes again,
including executable modes on Unix. Git attributes or line-ending conversion that
alter archive bytes cause a failure. Symlink and submodule entries are
unsupported and fail closed; user Git configuration and attributes are not
rewritten. Untracked or modified checkout files are excluded. A missing or
duplicate notes section fails the release. The checksum format is
`<lowercase sha256>  <archive filename>`.

Only prerelease versions such as `4.0.0-rc.2` are currently allowed. Stable
versions are blocked before the workflow creates a tag or GitHub Release:
`Stable releases are blocked until a verified release evidence protocol covers
real paired A/B trials and host callbacks.` A manually provided approval flag
or passing deterministic tests would not prove these outcomes. The stable guard
must remain in place until a separate, implemented protocol can authenticate
and validate the required evidence, including its relation to the exact release
source and host. An external push of a stable tag also fails the guard before
publication; a workflow cannot prevent the tag itself from being pushed.

Prerelease publication does not establish real behavioral improvements, trusted
hook callbacks, or production readiness. The separate evidence requirements and
current E2E limitations are described in [the evaluation guide](../evals/E2E.md)
and [hook integration](hooks.md).

For a new prerelease, update the manifests and add one matching version section
to `CHANGELOG.md` before invoking the workflow or pushing its tag. Use a new
version for changed bytes. For migration, see
[new V4 tasks from older contracts](migration-v4.md).

## Retry and partial publication

The workflow checks all pages of the authenticated GitHub release inventory
before it creates or reuses a tag. An unavailable inventory or an existing
release, including a draft, stops publication. For a retry without an existing
release, it verifies that the local and remote tag objects are identical and
that their commit is the checked-out commit. A matching remote tag can be fetched
and reused; a missing tag may be created only by a manual workflow dispatch.
Mismatched tags fail without force or overwrite. A tag-triggered run cannot
create a missing tag.

Tag verification and publication are separate operations, not an atomic GitHub
transaction. Protect release tags against changes and deletion by other actors;
verification alone cannot prevent a tag from changing between the check and
release creation.

`gh release create` is not atomic: a failed upload can leave a draft with some
assets. If a release already exists, do not rerun with asset replacement and do
not delete it automatically. Inspect the tag object and commit, title, notes,
prerelease/draft state, and all assets. Retrieve the ZIP, checksum and notes from
the **original failed workflow's uploaded artifact**; a later rebuilt ZIP can
have different bytes even for the same source. Compare every existing asset's
SHA-256 and filename with those preserved files. If all match and the release
is published with both assets, publication is already complete. If a draft has
matching existing assets, an authorized operator may upload only the missing
preserved assets without `--clobber`, recheck both hashes, and publish that
draft. If metadata or any hash differs, an asset digest is unavailable, or the
original artifact is unavailable, stop and choose a new version or an explicit
manual recovery; do not overwrite the existing tag or assets.
