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

For Stryker checks, literal source files in `report.scope` are also automatic
inputs. This includes ignored sources; changing one makes the capture stale.
Old mutation captures without these input hashes need recapture.

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

V4 stdout/stderr are capped independently at 32 MiB per check. Overflow is a
failed capture with `OUTPUT_LIMIT_EXCEEDED`, bounded prefixes and observed byte
counts; truncated output is never PASS. V3 and Git output defaults are unchanged.
Reports use one bounded 32 MiB snapshot for parsing and raw evidence; oversized
reports are rejected without copying their entire contents into the ledger.

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

## Test sensitivity

For each newly saved code-judged QA plan, include `payload.mutation_assessment`
before the implementation plan. Full human-only plans and light docs are exempt
from this assessment guard; historic saved QA and V3 evidence remain readable.
The assessment is a decision record, not evidence that the tests are adequate.

| Field | Content |
|---|---|
| `decision` | `run`, `skip`, or `unsupported` |
| `method` | `stryker`, `controlled`, or `none` |
| `rationale` | Changed risk, available tooling, and why this decision is proportionate |
| `scope` | Literal repository-relative source file paths, with `/` separators; no globs |
| `criterion_refs` | Existing criterion IDs the sensitivity decision addresses |
| `check_refs` | Existing check IDs; a run requires nonempty references, also present in QA scenarios |
| `budget`, `acceptance` | For `run`, nonempty strings defining limits and the expected sensitivity result |

A run needs nonempty scope, criterion_refs and check_refs. Each run check must
also occur in a QA scenario, so normal definition, capture and freshness bindings
apply. Choose a bounded run for recurring bugs, critical access, financial or
data-integrity invariants, changed comparisons, and branch refactors when an
existing suitable mechanism is available. Budget files/faults and execution time;
state which relevant faults must be detected and how survivors are dispositioned.
There is no global mutation-score target.

Before choosing unsupported, check whether the existing deterministic tests can
exercise a bounded fault in an isolated copy. Verify both harness and isolation
availability; an absent mutation tool alone does not exclude controlled checks.

- `run` / `stryker`: use existing Stryker tooling, `stryker-json` report checks
  and a mutation quality profile. In a final contract, every check in a required,
  available mutation profile needs an explicit project-chosen `minimum_score > 0`.
  Optional reports without a threshold are measurement; they do not establish
  accepted sensitivity. Inspect relevant survivors and no-coverage results even
  when an aggregate score meets its threshold.
- `run` / `controlled`: use ordinary declared checks in an isolated copy. Record
  each fault -> expected failing test -> actual result, verify the intended test
  failure rather than a build/harness error, and restore the copy. The outer check
  succeeds only when these assertions and restoration succeed. Keep injected
  defects out of the active source. This is bounded sensitivity evidence, not a
  Stryker report or invented language-wide mutation support.
- `skip` / `none`: use empty check_refs and an honest rationale tied to risk and
  cost. Docs or mechanical changes can justify skipping. A green suite alone
  cannot justify it.
- `unsupported` / `none`: use empty check_refs and state the missing suitable
  tool or isolation capability and the remaining gap. Do not install tools or
  invent adapters to satisfy a profile; required unsupported evidence blocks.

For bugfixes, plan and demonstrate a regression that fails on the old defect,
then passes on the fixed source. Execute new tests and any isolated old-defect
control after approved preflight. Preserve the original external expected result;
an unrelated failure does not establish that the regression detects the defect.
If a reliable old-defect control is unavailable, record the evidence gap instead
of claiming the bugfix is proven. Mutation does not replace that regression.

QA recheck compares the unchanged expected results with actual captured output,
fault dispositions and limitations. The packet retains skipped/unsupported work,
survivors and per-check observations. Reviewers judge semantic quality; the
runtime verifies bindings, reports and declared thresholds, not test adequacy or
complete correctness. See [quality capabilities](../../../docs/v4-runtime.md#quality-capabilities)
for report source/scope binding and profile status meanings.
