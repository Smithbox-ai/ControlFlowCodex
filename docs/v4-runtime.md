# V4 opt-in runtime interfaces

Package candidate 4.0.0-rc.1 supports contract/runtime 3.0.0 and opt-in 4.0.0.
V3 remains default. No daemon, workflow DSL, new mandatory dependency or plugin
agent is added. Local receipts provide integrity/provenance, not authentication.

## Routing

`classify-task.ps1 -SchemaVersion 4.0.0 -WorkType feature|bugfix|refactor|docs
-Domain core|supporting|generic|unknown` adds a fixed workflow and review policy.
Risk remains independent. Persisted tier SMALL also covers trivial v4 docs.
Only safe docs may use light. All other profiles require the six compact kinds;
medium core bugfix has the same defined prerequisites as feature. Tiny core,
unknown/mixed and high-risk changes cannot drop human design/final review.
Represent mixed domains conservatively as unknown. Existing reader limits apply.

## Contract and snapshots

Use `get-storage-paths.ps1` and the separate v4 template. Both draft and final
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
| qa-recheck | Current QA and implementation; one disposition per original scenario, unchanged expected value, current captured report evidence |
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
criteria need no dummy command. V3 keeps its original executable coverage rule.

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

## Quality capabilities

Check `report` declares format/path/tool/version/scope/config/baseline/exclusions,
optional minimum_tests (default 1) and minimum_score (mutation only, no universal
threshold). Paths are literal repository-relative files, preferably ignored
output directories. Reports must be rewritten by each capture; old reports cannot
substitute for a run. Captures store raw bytes/hash and actual process outcome.

Supported count parsing is deliberately narrow: one JUnit testsuite with direct
testcase children and matching summary counts; NUnit 3 test-run with matching
case/result counts and nonzero asserts; Stryker JSON mutant status counts. Unknown
shapes/statuses fail closed. JUnit counts cases but cannot establish assertions.
NUnit counts are report claims, not semantic proof. Pending mutation results are
NOT_RUN. Invalid/ignored/no-coverage/survived/timeouts remain visible; Stryker's
timeout-as-detected metric differs from an incomplete wrapper run.

Required unsupported profiles block. Optional lint/tests/mutation/complexity/CRAP/
SAST/DAST/environment profiles record their limitations and require existing tools;
the runtime never installs scanners. Available tests/environment/lint profiles
require recognized JUnit/NUnit reports; mutation requires Stryker JSON. Native
complexity/CRAP/SAST/DAST report adapters are currently UNSUPPORTED, even when
capability was optimistically declared available. Empty optional profiles are
NOT_RUN, not PASS. Tool/version metadata are declared by the contract and retained
with raw outputs; they are not independently authenticated executable identity. Unknown tools/formats are not invented PASS.
QA scenarios require actual current declared report captures. Review packets add
runtime-generated evidence_summary from saved captures; prose cannot replace it.

Own PowerShell controlled mutants are a separate isolated sensitivity pilot, not
Stryker support for PowerShell or proof of full correctness. CRAP remains a risk
indicator without an arbitrary threshold.

## Verification and release limits

Deterministic tests exercise supported APIs. Adapter smoke simulates callback
payloads and is not real host dispatch. Local/plugin command hooks are unsupported
in cloud orchestration; no trust is granted by packaging. Real host verification
requires existing exact-definition trust and a separate local host path.
Paired E2E remains blocked until ambient isolation, pinned inventories/settings,
permitted telemetry and a concrete trial budget are established. No session-path
reads are permitted for this task. JSON stdout may provide root usage but cannot
prove complete child usage or skill injection/isolation. Missing measurements
stay absent; no superiority or production-readiness claim follows from unit tests.

Sources: [hooks](https://learn.chatgpt.com/docs/hooks),
[plugin packaging](https://developers.openai.com/plugins/build/plugins),
[app-server approvals](https://learn.chatgpt.com/docs/app-server#approvals),
[managed cloud hook limitation](https://learn.chatgpt.com/docs/enterprise/managed-configuration#enforce-managed-hooks-from-requirements),
[NUnit 3 XML](https://docs.nunit.org/articles/nunit/technical-notes/usage/Test-Result-XML-Format.html),
[Stryker states/metrics](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/).
