# Evidence and ownership

Start a run before production changes. Its immutable initial snapshot separates
staged index OID/mode/stage, effective worktree content, and untracked content.
`baseline.dirty_paths` is an inventory, not a list to subtract. New edits inside
an already dirty file must be detected. Preserve user staged and unstaged hunks;
in this MVP ownership overlap blocks instead of trying to split mixed hunks.

Source identity covers effective contents, types, modes, and deletion against a
fixed baseline. It does not depend on current HEAD, staging, timestamps, or a
diff that disappears on commit. Exact run bookkeeping and its contract are
excluded; arbitrary artifact globs are not. Put only bookkeeping under the run,
never product source or acceptance-test implementations hidden from the digest.

`capture-check` executes exactly one declared command from its declared working
directory and stores immutable output, actual exit status, command identity,
and source identity before/after. A successful exit with zero discovered tests
does not prove behavior. Read discovery/results and assess criterion coverage.
Check-generated source edits make the capture STALE even when its exit is zero.

Contract mutation invalidates preflight, check definition, and coverage. Code
mutation invalidates check evidence and final review. Intended edits after
preflight do not by themselves invalidate its contract approval. Staging or
committing the same effective content preserves check identity. Corrupt or
missing references and incomplete Git observations are UNVERIFIABLE.

The deterministic ledger checks provenance, freshness, and coverage links. It
does not prove the semantic truth of `PROVEN`, the suitability of a command, or
an LLM's review. Keep observed evidence separate from hypotheses. A criterion
without suitable executable evidence remains a gap; do not manufacture PASS.

Never edit state.json or immutable captures to repair a gate. Use supported
events and new captures. The OS-held writer lock and expected revision reject
concurrent stale writes; unreferenced crash leftovers are not published evidence.
