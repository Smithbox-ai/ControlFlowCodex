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

Declare relevant ignored files in each check's optional `inputs` array, using
literal file paths relative to the repository root. Their hashes are recorded
before and after the check and compared again at the gate. Links, directories,
globs, literal backslashes and paths outside the repository are unsupported. Undeclared ignored files,
external files, environment variables and other outside inputs are not observed;
recapture checks when any of those inputs changes. Do not infer their freshness
from a PASS gate.

On Unix, a check must not detach processes from its dedicated process group.
Processes that leave that group can evade observation and cleanup; the group is
not a security boundary and the gate cannot prove their completion.

Contract mutation invalidates preflight, check definition, and coverage. Code
mutation invalidates check evidence and final review. Intended edits after
preflight do not by themselves invalidate its contract approval. Staging or
committing the same effective content preserves check identity. Corrupt or
missing references and incomplete Git observations are UNVERIFIABLE.

The deterministic ledger checks provenance, freshness, and coverage links. It
does not prove the semantic truth of `PROVEN`, the suitability of a command, or
an LLM's review. Keep observed evidence separate from hypotheses. A criterion
requiring code evidence without a suitable executable check remains a gap.
Human-only V4 criteria use the required bound decision, not a dummy command.
Every declared judge remains required; do not manufacture PASS.

Never edit state.json or immutable captures to repair a gate. Use supported
events and new captures. The OS-held writer lock and expected revision reject
concurrent stale writes; unreferenced crash leftovers are not published evidence.

## V4 report limits

Known formats: single-suite JUnit, NUnit 3 and Stryker JSON. Unknown stdout is
not proof of nonzero assertions. Captures retain tool/version, scope, config,
baseline, exclusions, raw report/hash and status. JUnit counts cases, not
assertions. Required unsupported profiles block; optional gaps stay visible.
Mutation reports describe test sensitivity. Controlled PowerShell gate/ledger
mutations are a separate bounded pilot, not universal language-tool support.
No universal mutation score or CRAP threshold is imposed.

QA `check_refs` can also include build/diff commands without a `report`. Their
current captures prove process outcome and freshness, not test counts. Every
declared report remains mandatory, including for QA rechecks and completion.
Declare reports for checks whose acceptance depends on discovered/executed tests;
do not substitute a synthetic test report for an ordinary command check.
