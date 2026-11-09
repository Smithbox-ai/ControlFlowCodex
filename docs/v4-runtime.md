# V4 runtime interfaces

New runs use contract/runtime 4.0.0. The package candidate version is recorded
in the package manifests; it is independent of the runtime schema version.
Requires PowerShell 7.4 or newer; recorded validation uses 7.6.9. A minimum
version declaration is not evidence of executing the platform matrix on 7.4.
Public run creation rejects V3 before storage initialization. Existing V3 runs
retain their original semantics and are visibly marked `legacy_semantics`.
Their strict schema is `schemas/compat/plan-meta-v3.schema.json`, used only for
existing runs, read-only validation and migration. Unknown versions fail closed.
No daemon, workflow DSL, new mandatory dependency or plugin agent is added.
Local receipts provide integrity/provenance, not authentication.

## Git executable boundary

Core Git observations resolve an application to an absolute physical executable
before the first Git invocation. Filesystem ancestor `.git` markers (directory
or linked-worktree file) establish logical and physical worktree boundaries.
Both the selected spelling and physical destination must remain outside them,
including intermediate links and Windows short-path aliases. A missing boundary
fails closed; environment-only bare/worktree discovery is not supported.
This avoids Windows process-current-directory executable lookup without changing
the process cwd. It does not lock executable files against concurrent replacement.

## Routing

`classify-task.ps1 -WorkType feature|bugfix|refactor|docs
-Domain core|supporting|generic|unknown` adds a fixed workflow and review policy.
Risk remains independent. Persisted tier SMALL also covers trivial v4 docs.
Only safe docs may use light. All other profiles require the six compact kinds;
medium core bugfix has the same defined prerequisites as feature. Tiny core,
unknown/mixed and high-risk changes cannot drop human design/final review.
Represent mixed domains conservatively as unknown. Existing reader limits apply.

## Contract and snapshots

Use `get-storage-paths.ps1` and the V4 template. Both draft and final
live outside source. Start-run observes source, index, foreign dirty paths,
worktree/session/task/run identity. It cannot prove absence of edits before start.
Known preparatory edits remain original foreign work, never adopted owned edits.
Draft permits incomplete check/criterion declarations but cannot authorize checks,
preflight, commit or completion. Final requires all declarations and review targets.

`Get-ControlFlowPlanningContext -RepoRoot <repo> -RunPath <run>` returns current
intent/policy/source hashes, epoch and exact artifact refs. Intent includes fixed
goal, baseline/scope, non-goals, constraints, user decisions, domain and risks.
Policy includes fixed workflow/review requirements. Adding downstream commands
alone does not change either. Changed goal/scope/design/policy requires new review.

The artifact event is `{type:"artifact", artifact:<phase-artifact-v1 envelope>}`.
Schema defines exact typed payloads. Envelope contains schema_version 1.0.0,
artifact_id (new 32hex), kind, increasing revision per kind/epoch, task_id, run_id,
planning_epoch_id, source_digest, intent_digest, policy_digest, inputs (exact
path/sha256 refs), policy_refs, criterion_refs and payload. Runtime stores validated
JSON under artifacts/32hex.json using existing lock and atomic state publication.
Refs cannot traverse or follow links, and foreign/tampered refs fail closed.

| Kind | Required inputs and content |
|---|---|
| context | No inputs; goals/non-goals, decisions, assumptions, unknowns, code refs, invariants |
| design | Current context; behavior/boundaries/data, selected solution, alternative, risk/rollback |
| qa-plan | Current design plus required human design decision; external expected results and sources, inputs, negative/boundary cases, criterion/check IDs |
| implementation-plan | Current QA; ordered parts, exact components, earlier dependencies, readiness, criterion IDs |
| qa-recheck | Current QA and implementation; one disposition per original scenario, unchanged expected value, current declared check captures (including reports when declared) |
| review-packet | Current recheck (light needs none); behavior/invariants/diff, results/limitations/open decisions/rollback |

Artifact source identity is observed when saved. Context/design stay linked to
their baseline and intent after ordinary authorized production edits; final QA
and packet bind current source and final contract bytes. Adding downstream
artifacts never edits an upstream snapshot. A new upstream revision stales its
dependants. Preflight promotes early refs to final raw-byte contract digest after
checking exact design/intent/policy bindings; promotion is not human approval.
Later raw-byte contract changes conservatively stale promoted evidence.

QA snapshots also retain runtime-generated hashes of referenced criterion/check
definitions. Promotion rechecks those exact definitions, including command,
working directory and mappings; changed definitions stale QA and implementation.
IDs and carried paths use ordinal case-sensitive uniqueness. Historical V4 QA
with collapsed case-distinct bindings becomes stale; no receipts are rewritten.
Unresolved human targets are also recovered from current-epoch review events
when an older V4 publisher collapsed its mutable wait set.

Record decisions with `phase_review`: artifact_ref, target_id, judge human|agent,
verdict APPROVED|REJECTED|UNKNOWN, assurance manual|verified, user_decision_ref.
Targets are design, final, or declared criterion/phase IDs. Code judges derive
from captures and cannot be self-authored phase_review events. All listed judges
are required. Human design binds design; other decisions bind current packet.
Manual receipt_id records supplied provenance and is visibly weaker than verified.
No trusted human verifier is installed: verified submissions and required verified
preflight fail closed. Neither local flags nor app-server request cleanup proves
human consent. Human review semantics/understanding remain outside hashes.

Preflight uses existing `{type:"preflight",status:"APPROVED"}` only with final
contract, required artifacts/decisions and unchanged observed planning source.
Adding a test counts as an edit. New owned code/tests are allowed only afterwards.
Existing coverage events still map criterion IDs to captured checks. Human-only
criteria need no dummy command. Existing V3 runs keep their original executable
coverage rule; a migrated V4 task collects fresh artifacts and evidence.

## Re-entry and stops

Use resume with mode planning and user_decision_ref after previously authorized
implementation. Runtime records previous preflight, carried source and increments
planning_epoch_id; initial_ref and original foreign snapshots never change.
Only changes inside prior authorized scope can be carried. Edits during the new
planning epoch reject preflight. Fresh context/design/QA/plan/decisions are needed.

Rejection/unknown human decisions persist HUMAN_WAIT. Stop hooks treat it as a
lawful incomplete end. Resume requires user_decision_ref plus exact current
approved decision_receipt_id; old revisions, source and policies cannot resume.
Pending human targets persist across other stop reasons; unrelated approvals
cannot clear them. Generic HUMAN_WAIT needs an existing bound decision; create
that wait with an UNKNOWN human phase_review. Session start, timeout or elapsed
wait is never approval. Existing native interrupt
mailbox and 3-identical/6-total Stop continuation budget remain. A stop preserves
its first observed source boundary, including repeated interrupts. The native
fast path uses the last observed source conservatively, so legitimate edits
not observed before interruption may require repair/replanning rather than carry.
Three rejected corrections for one target or six total block automatic repair.
Explicit planning re-entry records and resets correction history; it grants no
new approval. Completion is
terminal; a stale completed result can become BLOCKED without reopening edits.
For V4, late Interrupt notifications cannot reopen COMPLETED, CANCELLED or a
`lifecycle_closed` run. A closed BLOCKED run can relinquish its session to a new
run. A notification observed before completion's final mailbox check still
rejects completion; a later generation cannot change the durable terminal state.
Historical V3 notification/resume behavior remains unchanged.

Completion rechecks source, raw contract and required check-input digests before
returning PASS and again before publishing COMPLETED. The gate retains its
`input_digests` observation, including QA-referenced checks. A detected concurrent
change or newly pending interrupt rejects completion. V4 completion also rechecks
the observed state revision and evidence reference; concurrent ledger publication
returns `LEDGER_CHANGED_DURING_GATE`. Results retain `observed_revision` and
`observed_evidence_ref`. This read-only check does not acquire a nested writer lock.
These checks do not lock
external editors or guarantee unchanged files after the operation returns.

## Capture byte limits

V4 checks retain at most 33,554,432 bytes (32 MiB) independently for stdout and
stderr. Exactly the limit is accepted. An extra byte stops the owned process tree
and records capture `FAIL`, `error: OUTPUT_LIMIT_EXCEEDED`, the bounded prefixes,
`output_limit_bytes`, `output_limit_exceeded`, and each stream's observed byte
count. Observed counts are lower bounds, not total output after termination.
Limit failure takes precedence over timeout/staleness diagnostics; those facts
remain visible. Truncated output cannot support a successful check.

Legacy V3 checks and ordinary Git observations retain their previous output
defaults. The byte budget bounds collected buffers, not total RSS, source hashing,
XML/JSON object graphs or historical evidence reads. Process groups/jobs remain
cleanup mechanisms rather than a sandbox.

Reports retain the existing 32 MiB limit. One bounded, opened-file snapshot supplies
both the parser and raw receipt, including its handle-derived timestamp. A path
replacement cannot make parsed metrics describe different archived bytes.
Oversized reports record quality `ERROR / REPORT_TOO_LARGE` and capture failure
without archiving the entire report. XML encoding detection and DTD prohibition,
JSON BOM handling, scope checks and acceptance thresholds remain unchanged.
`Read-ControlFlowQualityReport -Path` remains supported.

## Quality capabilities

V4 criterion and phase IDs must not equal the reserved design-review target
`design`; use a distinct ID such as `C-design` or `phase-design`. Validation
rejects this collision before a new run starts. V3 reading semantics are unchanged.

Check `report` declares format/path/tool/version/scope/config/baseline/exclusions,
optional minimum_tests (default 1) and minimum_score (mutation only, no universal
threshold). Paths are literal repository-relative files, preferably ignored
output directories. Reports must be rewritten by each capture; old reports cannot
substitute for a run. Captures store raw bytes/hash and actual process outcome.
Every check in a required, available mutation profile of a final contract needs
an explicit `minimum_score > 0`, chosen for the project and scope. An optional
mutation report without a threshold remains a measurement; it cannot support a
claim that sensitivity acceptance passed.
This final-contract invariant also applies when reading an older V4 contract:
add the missing positive threshold before resuming and collect fresh bound
evidence. It does not rewrite historical artifacts or change V3 semantics.

Supported count parsing is deliberately narrow: one JUnit testsuite with direct
testcase children and matching summary counts; NUnit 3 test-run with matching
case/result counts and nonzero asserts; Stryker JSON mutant status counts. Unknown
shapes/statuses fail closed. JUnit counts cases but cannot establish assertions.
The JUnit subset accepts optional case `status="run"` and `result="completed"`
or `result="skipped"` consistent with its skipped child; other explicit execution
statuses/results and nonzero suite `disabled` counts are unsupported. They cannot
be silently counted as completed tests.
NUnit counts are report claims, not semantic proof. Pending mutation results are
NOT_RUN. Invalid/ignored/no-coverage/survived/timeouts remain visible; Stryker's
timeout-as-detected metric differs from an incomplete wrapper run.

Stryker report file keys must be canonical relative paths. They resolve through
the report's `projectRoot` when present, otherwise through the check's
`working_directory`. A relative
projectRoot resolves from that working directory; an absolute root must remain
inside the repository. Resolved files must match the literal repository-relative
files in declared `report.scope`: every reported file is in scope, and every
scoped file is represented. No globs, traversal, backslashes or linked source
paths are accepted. Source is read with UTF-8 as the default and standard BOM
detection. Report source must equal the current decoded text exactly, except the
encoding BOM; line endings and all other text must match. A fresh report timestamp
does not replace this source/scope binding. Report metadata retains
`scope_verified` and `verified_scope`; `acceptance_status` distinguishes
UNCONFIGURED, PASS, FAIL and NOT_EVALUATED.

Every Stryker scoped source file is automatically included in check-input
hashing, even when ignored by Git. It is hashed before/after execution and again
when checking freshness or preparing profile summaries. Missing old input
receipts require recapture. Explicit `inputs` still cover other dependencies.

Required unsupported profiles block. Optional lint/tests/mutation/complexity/CRAP/
SAST/DAST/environment profiles record their limitations and require existing tools;
the runtime never installs scanners. Available tests/environment/lint profiles
require recognized JUnit/NUnit reports; mutation requires Stryker JSON. Native
complexity/CRAP/SAST/DAST report adapters are currently UNSUPPORTED, even when
capability was optimistically declared available. Empty optional profiles are
NOT_RUN, not PASS. Tool/version metadata are declared by the contract and retained
with raw outputs; they are not independently authenticated executable identity. Unknown tools/formats are not invented PASS.
QA scenarios require actual current captures for every declared `check_refs` entry.
Build, diff and other command checks without a `report` use their captured process
outcome and the same contract, command, source and declared-input freshness checks.
They do not establish test counts or assertions. A check that declares a `report`
also requires a recognized passing report and saved raw bytes; QA does not waive
that requirement. Test-count assurance requires a declared report (or an available
tests quality profile); do not manufacture test reports for build/diff commands.
Review packets add
runtime-generated evidence_summary from saved captures; prose cannot replace it.

Quality profile summaries include reasons and per-check observations, keeping
`ERROR`, `FAIL`, `TIMEOUT`, `STALE`, `NOT_RUN` and `PASS` distinct. A malformed or
unverifiable report is ERROR; failed checks or thresholds are FAIL; a command
deadline is TIMEOUT; changed source/definitions/inputs make evidence STALE;
absent or incomplete execution is NOT_RUN. PASS requires the applicable current
checks and report rules. Capability outcomes `UNSUPPORTED` and `NOT_APPLICABLE`
remain distinct from those execution outcomes. Neither PASS nor a count or score
proves semantic quality.

Own PowerShell controlled mutants are a separate isolated sensitivity pilot, not
Stryker support for PowerShell or proof of full correctness. CRAP remains a risk
indicator without an arbitrary threshold.

### QA sensitivity assessment

Every newly saved code-judged `qa-plan` includes `payload.mutation_assessment`.
Full human-only and light docs plans are exempt from this guard. Historic saved
QA and V3 data remain readable; do not rewrite historical artifacts to add fields.
Choose run/skip/unsupported using the
[test sensitivity recipe](../skills/controlflow/references/evidence.md#test-sensitivity).
For bugfixes, plan a regression that fails on the old defect and passes on the
fix. A green suite alone supplies no negative control. Relevant comparisons,
recurring bugs and critical access/financial/integrity invariants warrant a
bounded sensitivity run when a suitable existing mechanism is available.

This example connects the QA payload to contract checks and a required mutation
profile. It assumes an existing repository script `tests/run-billing-mutation.ps1`
that invokes its pinned Stryker tool and rewrites `.reports/billing-mutation.json`.
Use actual paths, tool version, config, baseline and acceptance for the project;
90 is an illustrative project decision, not a plugin default. Merge `payload`
into the normal QA envelope and the declarations into the final contract, with
the corresponding code-judged criterion `C-billing`.

```json
{
  "payload": {
    "scenarios": [{
      "id": "billing-boundary",
      "inputs": "Amounts immediately below, equal to and above the limit",
      "expected": "Only amounts below the limit are accepted",
      "expectation_source": "Accepted billing rule and incident reproducer",
      "criterion_refs": ["C-billing"],
      "check_refs": ["billing-tests", "billing-mutation"],
      "negative": "The regression fails with the old inclusive comparison",
      "boundary": "An amount equal to the limit is rejected"
    }],
    "mutation_assessment": {
      "decision": "run",
      "method": "stryker",
      "rationale": "A recurrent financial defect changes a comparison",
      "scope": ["src/Billing/Guard.cs"],
      "criterion_refs": ["C-billing"],
      "check_refs": ["billing-mutation"],
      "budget": "One source file; at most 120 seconds",
      "acceptance": "Score at least 90; comparison mutant detected; review survivors"
    }
  },
  "checks": [{
    "id": "billing-tests",
    "command": "pwsh -NoProfile -File tests/billing-regression.tests.ps1",
    "working_directory": ".",
    "timeout_seconds": 120,
    "criteria": ["C-billing"]
  }, {
    "id": "billing-mutation",
    "command": "pwsh -NoProfile -File tests/run-billing-mutation.ps1",
    "working_directory": ".",
    "timeout_seconds": 120,
    "criteria": ["C-billing"],
    "report": {
      "format": "stryker-json",
      "path": ".reports/billing-mutation.json",
      "tool": "dotnet-stryker",
      "version": "repository-pinned-version",
      "scope": ["src/Billing/Guard.cs"],
      "config": "stryker-config.json",
      "baseline": "incident-reproducer",
      "exclusions": [],
      "minimum_score": 90
    }
  }],
  "quality_profiles": [{
    "id": "billing-sensitivity",
    "kind": "mutation",
    "required": true,
    "capability": "available",
    "check_ids": ["billing-mutation"]
  }]
}
```

The ordinary `billing-tests` command here asserts the intended failure on an
isolated old-defect copy and success on fixed code; it is a command check, not
test-count assurance. Declare a recognized test report separately if acceptance
depends on discovered/executed counts. The runtime binds declared checks; a
reviewer must still examine whether this script and the mutant dispositions
establish the stated external behavior.

## Verification and release limits

Deterministic tests exercise supported APIs. Adapter smoke simulates callback
payloads and is not real host dispatch. Local/plugin command hooks are unsupported
in cloud orchestration; no trust is granted by packaging. Real host verification
requires existing exact-definition trust and a separate local host path.
Paired E2E execution and discovery remain blocked before native CLI, auth or
session access: supported telemetry does not establish actual context/policy
provenance, ambient isolation and complete child usage. A budget alone cannot
supply that missing capability. JSON stdout may provide root usage but cannot
prove complete child usage or skill injection/isolation. Missing measurements
stay absent; no superiority or production-readiness claim follows from unit tests.

Sources: [hooks](https://learn.chatgpt.com/docs/hooks),
[plugin packaging](https://developers.openai.com/plugins/build/plugins),
[app-server approvals](https://learn.chatgpt.com/docs/app-server#approvals),
[managed cloud hook limitation](https://learn.chatgpt.com/docs/enterprise/managed-configuration#enforce-managed-hooks-from-requirements),
[NUnit 3 XML](https://docs.nunit.org/articles/nunit/technical-notes/usage/Test-Result-XML-Format.html),
[Stryker states/metrics](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/).
