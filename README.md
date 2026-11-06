# ControlFlow for Codex

Compact planning and completion discipline for native Codex repository tasks.
`$controlflow` adds a durable execution contract: what should change, how it will
be checked, which decisions are needed, and what evidence permits completion.
It helps keep a multi-step feature or fix aligned with its agreed behavior,
preserve existing user work, and resume without treating missing checks as done.
Native Codex owns tools, sandboxing, permission decisions, execution, review,
and agent lifecycle. ControlFlow does not add a second orchestrator.

**Package `4.0.0-rc.3` is a candidate. V4 is the default for every new run.**
New contracts use schema/runtime `4.0.0`. Existing V3 runs remain readable and
retain their original rules, visibly marked `legacy_semantics`; they are not
upgraded in place. New V3 runs, templates and examples are no longer offered.
Functional acceptance of an installable candidate requires platform checks and
verified packages bound to its exact source. Stable publication, comparative
benefit and production-readiness claims require separate evidence; see the
[release procedure](docs/release.md).

## What V4 adds

| Capability | What it does for a task |
| --- | --- |
| Risk-aware routes | Chooses a fixed feature, bugfix, refactor or docs workflow. Safe, small docs can stay light; tiny core, unknown-domain or high-risk changes retain the stronger review requirements. |
| Context and design before edits | Records intent, constraints, relevant rules and a bounded design. Features require a human design decision; other human requirements follow domain/risk and the declared policy. A draft cannot authorize code or test edits. |
| QA before the implementation plan | Saves scenarios with external expected results, negative/boundary cases and criterion/check IDs. QA recheck compares the result with that baseline; rewriting an expectation cannot legalize a defect. |
| Evidence that becomes stale | Binds immutable phase snapshots and decisions to the task, run, intent, policy and exact inputs. Changed upstream artifacts invalidate dependent evidence; final QA and review packets bind the current source. |
| Explicit replanning | Opens a new planning epoch after authorized implementation, preserving original foreign ownership and carried work. It cannot turn early unauthorized edits into an accepted baseline. |
| Required judges and quality evidence | Requires every declared code, agent and human judge. Captured checks and supported reports supply code evidence; an agent verdict cannot replace a required human decision. Unsupported required capabilities block. |
| Honest stops and delivery | Keeps human wait, rejection, interruption and exhausted retries incomplete. Resume needs the exact current decision where required; completion needs a fresh gate and a compact evidence-backed review packet. |

There is one production writer. Native readers are optional and bounded by the
existing tier limits. Relevant references, shared IDs and small artifacts keep
context focused; reduced token use or better results than vanilla Codex have
not been established by comparative measurement.

## A typical V4 task

For a feature, the route is:

1. Observe the baseline and prepare a draft contract, context and design.
2. Obtain the required design decision, then save the QA baseline and
   implementation plan. Finalize the contract and pass preflight before edits.
3. Implement, capture the declared checks, obtain the required independent
   reviews, and recheck the unchanged QA expectations against the result.
4. Present the current review packet, obtain a final human decision if required,
   and pass the completion gate. Missing evidence leaves the run incomplete.

The six compact artifact kinds are `context`, `design`, `qa-plan`,
`implementation-plan`, `qa-recheck` and `review-packet`. They are immutable JSON
receipts in external state, not six mandatory repository documents. The safe
`light` docs route requires only its review packet and applicable check evidence.
See [V4 interfaces and payloads](docs/v4-runtime.md).

## Use

### First run

1. For Codex `0.166.0-alpha.5.1`, install from a trusted checkout with
   `pwsh -NoProfile -File scripts/install.ps1 -Flavor NativeLegacy -Force`.
   An existing owned installation can be updated with `-Force` alone: its flavor
   is preserved and reported. A fresh checkout defaults to Universal; it does not
   detect the host automatically.
   Enable the plugin in your Codex host. Review and trust its current hook definition
   in the host before relying on automatic enforcement; installation alone does not
   establish trust. See [hook setup and limitations](docs/hooks.md).
2. From the checkout, run `pwsh -NoProfile -File scripts/doctor.ps1 -RepoRoot <repo>`.
   This read-only diagnostic checks the repository and storage path configuration.
   It does not establish host activation, hook trust, callback delivery or storage
   write access; those remain explicitly unverified.
3. In Codex, request a repository task using
   `$controlflow-codex:controlflow <your task>`. The agent chooses a tier and, for
   non-trivial work, prepares a contract, captures checks and evaluates completion.
   If a trusted callback or native session identity is unavailable, it uses manual
   fallback and runs the completion gate directly.
4. Read the result and evidence. For an existing run, use
   `pwsh -NoProfile -File scripts/explain-gate.ps1 -RepoRoot <repo> -RunPath <run>`
   for an explanatory view; `completion-gate.ps1` remains the machine-readable JSON
   interface. Both use exits 0/1/2 for PASS/FAIL/ERROR.

Illustrative outcomes, not recorded runs:

- **SMALL / PASS:** the agent records the required current artifacts, decisions,
  successful checks and coverage; the completion
  gate returns `PASS`. With manual fallback, the agent records completion and reports
  that automatic Stop enforcement was not verified.
- **BLOCKED / manual fallback:** a missing check, inaccessible evidence or unanswered
  question leaves the task incomplete. The agent reports the reason and next action;
  it does not call the task done. Resume an interrupted or blocked run only after
  the user's explicit decision.

The detailed lifecycle is in [execution](skills/controlflow/references/execution.md).

### Start a V4 task

After installation and host setup, request a repository task in Codex:

```text
$controlflow-codex:controlflow Complete this repository task:
add label normalization with Unicode-preserving trimming and an 80-character
limit. Prepare the design and QA baseline before implementation. Do not commit.
```

New runs always use V4; no opt-in flag is needed. Use
`plans/templates/plan.meta.v4.json` at the new task's canonical external
`contract_path` returned by `get-storage-paths.ps1`. Replace the sample task,
baseline, scope, criteria and check declarations with actual task evidence.
The template is a draft, and successful schema validation alone permits no edits.
These read-only commands show the route and validate the bundled draft shape:

```powershell
pwsh -NoProfile -File scripts/classify-task.ps1 -WorkType feature -Domain supporting -ChangedFiles 2 -BehaviorChange
pwsh -NoProfile -File scripts/validate-contract.ps1 -Path plans/templates/plan.meta.v4.json
```

Classification does not activate a run. The agent must save the actual contract,
collect its phase artifacts/decisions and pass preflight. Existing V3 runs
stay legacy; [explicit migration](docs/migration-v4.md) creates a separate draft and
requires fresh evidence. No approval or captured result is copied.

For native plugin text invocation, use `$controlflow-codex:controlflow` with a
repository task. Short aliases such as `$controlflow` require host support.
Native plugins namespace skill names and explicit-only skills may be hidden
from the implicit prompt catalogue. The entry skill chooses the tier
from observed scope, behavior, boundaries, product uncertainty, and risk:

Tier limits bound review effort and native readers; the V4 workflow profile also
depends on work type, domain and risk:

| Tier | Artifacts and review |
| --- | --- |
| SMALL | Compact contract and evidence; safe docs can use light, other work retains its fixed phase route |
| MEDIUM | Explicit risks/ordering and required reviews; at most one optional native reader |
| LARGE | Relevant boundary/high-risk review; at most two optional concurrent native readers |

An unresolved HIGH risk forces LARGE. Only product-critical missing information
requires clarification. A commit is required only when the user requests it.
There is one production writer per task. Optional readers must have a concrete
question and their usage counts toward the task total.

Use `plans/templates/plan.meta.v4.json` for a new contract and validate it with
`scripts/validate-contract.ps1 -Path <contract>`. The SMALL V4 draft example is
`plans/examples/small-v4.meta.json`; replace its sample baseline and checks with
actual repository evidence before starting a run.

For multi-step work, ControlFlow uses native `update_plan` when available. It
restores the accepted milestones and verified progress after resume, updates
after meaningful stages or plan changes, and keeps blocked/waiting work
incomplete. Hosts without that tool receive honest textual progress. The native
TODO reflects work status; captured evidence and completion gates still decide
delivery. See [the progress policy](skills/controlflow/references/progress.md).

The three manual skills remain explicit: `$controlflow-codex:controlflow-plan`,
`$controlflow-codex:controlflow-verify`, and `$controlflow-codex:controlflow-review`.
Internal references use their logical names. Native `/plan` and `/review`
remain available. See [the execution reference](skills/controlflow/references/execution.md).

## Evidence and completion

New contract/runtime version is `4.0.0`; existing `3.0.0` runs retain explicit
legacy semantics, and unknown versions are rejected. All runtime bookkeeping is stored outside project
directories, by default under `<CODEX_HOME>/controlflow` (or
`~/.codex/controlflow` when CODEX_HOME is unset). Set `CONTROLFLOW_STATE_ROOT` to
an absolute external directory if the host requires another writable location;
tools and native hooks must inherit the same value. Relative, linked or
project-local roots are rejected. Missing write permission is an explicit error,
never a fallback to the project. Native Codex sessions and databases are untouched.

Use `scripts/get-storage-paths.ps1 -RepoRoot <repo> -TaskId <task_id>
-SessionId <native-id> -Create` to prepare storage and obtain `contract_path`.
Omit SessionId for explicit manual fallback. Each physical worktree/Git identity
and session has a separate task contract and active marker; immutable evidence
lives below that task's `runs/<run_id>/`. `state.json` publishes the coherent revision. The active
session marker is bound to the physical worktree, Git directory, session, task,
and run. Another session or a mismatched contract/runtime version cannot activate
that gate.

Old project-local runs are never automatically adopted, rewritten or deleted.
See [migration](docs/migration-v4.md) before moving existing data. Only requested
task deliverables or explicitly requested report exports belong in the project;
ControlFlow never adds bookkeeping directories or ignore rules there.

`capture-check.ps1` executes one declared command and records its working
directory, exit status, output hashes, and source identity before and after.
Contract edits invalidate contract approval and check definitions; source edits
invalidate checks and final review. Staging or committing identical content
preserves its identity. The ledger verifies provenance, freshness, and coverage;
it cannot establish the semantic truth of a model's `PROVEN` assessment.

Checks may declare `inputs` as literal file paths relative to the repository root,
including ignored files. Their content hashes are checked before and after the
command and again at the gate; file contents are not stored in the ledger. Declare
every such file that can affect the check. Directories, links, glob patterns and
paths outside the repository are not supported. Input paths use `/` separators;
literal backslashes in file names are unsupported on all platforms. Undeclared ignored files, external
files, environment variables and other external dependencies are not tracked, so
their changes require a fresh check; a gate cannot infer them automatically.
For example, a check whose behavior depends on an ignored local configuration can
include `"inputs": ["config/local.json"]` in its contract.

Stryker `report.scope` source files are automatic check inputs, including ignored
files. Their hashes are captured before/after execution and checked again at the
gate; do not duplicate them in `inputs`. Older mutation captures without these
input receipts require recapture.

Check timeouts cover command execution and output collection. On Unix, cleanup
uses a dedicated process group; a process that deliberately leaves that group
can escape observation and cleanup. Run only checks whose background processes
remain in the group and complete before the command exits. The process group is
not a security boundary.

The delivery scripts `completion-gate.ps1` and `commit-gate.ps1` emit JSON
`status: PASS | FAIL | ERROR` with exits `0 | 1 | 2`. Missing or incomplete Git
observations are ERROR/UNVERIFIABLE. For a required commit, completion also
verifies the actual commit's parent, tree, and owned paths.

Initial staged, worktree, and untracked user content is captured separately.
Later changes inside an already dirty file are detected. Initial user hunks
cannot enter the task commit; overlapping ownership blocks the conservative
MVP and requires an isolated worktree or a concrete ownership decision.

## Hooks and fallback

Bundled local command hooks handle Stop, SessionStart, and Interrupt. Review and
trust the current hook definition in Codex before relying on them; installation
alone does not trust it. A clarification, denied permission, cancellation,
interruption, Plan Mode, or BLOCKED state is a lawful turn end, distinct from
DONE. The third identical no-progress continuation or sixth total attempt
blocks further automatic continuation. Interrupted runs require explicit user
resumption.

Unavailable or untrusted hooks require an explicit manual fallback: run the
completion gate directly and report that automatic Stop enforcement is absent.
A callback error or damaged ledger ends visibly as BLOCKED/UNVERIFIABLE; no
secondary state machine guesses how to repair it. Native hooks are a reliability
aid, not a security boundary. See [hook integration and limitations](docs/hooks.md).

## Install and package

Requires Git and PowerShell 7.4 or newer; 7.6.9 is tested and recommended.
The root `plugin.json` is canonical; the
`.codex-plugin/plugin.json` compatibility manifest mirrors its OpenAI extension.
For Codex `0.166.0-alpha.5.1`, use the explicit `NativeLegacy` flavor: that host's
root AgentPlugin loader omits bundled hooks. The default `Universal` flavor keeps
the canonical root manifest. NativeLegacy contains the same shared runtime,
skills and assets, omitting only that root manifest, and rejects unexpected
recursive skills, links and MCP/apps capabilities. It is a host compatibility
choice, not a trust bypass or automatic fallback. See
[the compatibility procedure](docs/release.md#explicit-native-compatibility-flavor-candidate)
before choosing a flavor.

```powershell
# Fresh install for Codex 0.166.0-alpha.5.1 (canonical checkout is supported).
pwsh -NoProfile -File scripts/install.ps1 -Flavor NativeLegacy -Force
# Upgrade: preserve the existing flavor.
pwsh -NoProfile -File scripts/install.ps1 -Force
# Remove managed local source/registration and retain a recovery backup.
pwsh -NoProfile -File scripts/install.ps1 -Uninstall -Force
pwsh -NoProfile -File scripts/package.ps1
```

For that specific native host, build with `scripts/package.ps1 -Flavor
NativeLegacy` or explicitly select `-Flavor NativeLegacy` when installing from
the canonical checkout. The installer validates Universal source, omits only its
root manifest in staging and strictly validates the NativeLegacy result. A fresh
NativeLegacy artifact requires explicit selection; an existing install preserves
its flavor unless a different `-Flavor` is explicitly supplied with `-Force`.
Every replacement/removal retains the prior `source/` and exact `marketplace.json`
in the reported recovery directory, including custom files. Uninstall does not
remove native cache, trust, configuration or run data; use the host's supported
remove flow to deactivate its cached copy. Installation/enabling still requires
exact native hook trust and callback verification. Do not edit cache or trust files.

`-HomeRoot <path>` supports isolated installation. The installer validates
ownership and containment, stages the shared inventory, and rolls back a failed
replacement or marketplace update. Other marketplace entries are preserved.
Release smoke extracts the ZIP and installs **that extracted source**.
See [installation, upgrade and rollback](docs/installation-v4.md) for ZIP
extraction and native setup, and [release procedure](docs/release.md) for artifact
publication and the stable release evidence gate.

## Development and evaluation

```powershell
pwsh -NoProfile -File tests/run-contract-tests.ps1
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Pilot -ValidateOnly
```

Deterministic suites and corpus validation run without model calls.
[Evals](evals/README.md) prepare paired native/V4 fixtures and define comparison
requirements. Execution and discovery remain blocked before CLI/auth/session
access while supported telemetry cannot establish complete context, policies,
child usage and isolation. Missing checks or metrics are incomplete, never
success. The 12-case pilot is distinct from the 55-case release corpus; future
comparative acceptance needs separately authorized, pinned paired trials.
LARGE graders also exercise the file-to-file CLI. The separate
[critical-risk diagnostic protocol](evals/RISK-DIAGNOSTICS.md) measures collection
and independently reviewed recall; unreviewed findings have no certified recall.

## Quality, verification and limits

V4 can attach existing tools through declared quality profiles. Recognized JUnit
and NUnit 3 reports support test counts; Stryker JSON supports mutation states
and scores. Captures retain raw report hashes, declared tool/version, scope,
configuration, baseline and exclusions. Missing, incomplete, unknown or
unsupported evidence is not PASS; a required unsupported profile blocks.
The runtime does not install scanners. Complexity/CRAP, SAST and DAST report
adapters are currently unsupported. See [quality capabilities](docs/v4-runtime.md#quality-capabilities).

Mutation testing measures whether tests detect controlled faults, not complete
correctness. New code-judged QA plans record `mutation_assessment`: run a bounded
Stryker or isolated controlled check, skip with a risk-based rationale, or record
unsupported tooling honestly. Bugfix regressions must fail on the old defect and
pass on the fix. Recurring defects, changed comparisons and critical financial,
access or integrity rules deserve explicit sensitivity scrutiny; green tests
alone cannot justify skipping. Required available mutation profiles need a
positive project-chosen score threshold. Optional unthresholded reports remain
measurements. Human-only plans and safe light docs keep their proportional path.
See the [assessment recipe](skills/controlflow/references/evidence.md#test-sensitivity)
and [QA example](docs/v4-runtime.md#qa-sensitivity-assessment).

The plugin's own PowerShell gate/ledger tests have a separate,
bounded source-specific mutation sensitivity pilot; this is not a universal
PowerShell framework or Stryker support for PowerShell. CRAP is a risk indicator,
not a universal threshold or a substitute for architectural review.

| Status | Scope and limits |
| --- | --- |
| Implemented | V4 new-run default, fixed phase ordering, immutable bindings, planning re-entry, manual decision provenance, quality/report handling and evidence-based completion; existing V3 runs retain marked legacy semantics. |
| Functional validation | Consult the candidate's accompanying validation report for exact source/package hashes, platform and tool versions, actual results and unresolved checks. A rebuilt ZIP requires its own byte binding. |
| Native host verification | Installation, enablement, exact hook trust and real callbacks are separate observations. Historical callback evidence does not verify rebuilt rc.2 bytes or another host. |
| Comparative and stable limits | Paired execution remains blocked without supported provenance, context, isolation and complete child accounting. Deterministic checks alone establish neither comparative benefit nor production readiness. Stable publication remains guarded by the verified release-evidence protocol requirement. |

Human decisions use visible **manual assurance**: they record supplied provenance
and exact artifact bindings. Local hashes, `human=true` or an agent's declaration
do not authenticate a human. Required verified-human assurance fails closed
because no trusted receipt verifier is provided.

Hooks cannot guarantee termination of every already-running background command;
native interruption and descendant process cleanup are different observations.
There is no global hard token cap. The paired V4 adapter blocks execution while
effective context, ambient plugin isolation, policy provenance and complete child
usage cannot be established through supported telemetry. No private-history
workaround or caller-authored capability flag supplies that proof. See
[paired V4 limits](evals/V4-ADAPTER.md#collectors-and-execution-block) and
[host limits](docs/hooks.md#v4-assurance-and-host-limits).

## Migration and rollback

Only V4 templates/examples are shipped for new work. The strict V3 schema lives
under `schemas/compat/` for existing runs, read-only validation and migration;
it does not enable new legacy runs. The migration command accepts an external
V2 or V3 contract and creates a new V4 draft with commit mode `none`, without old
state, approvals or captures. Existing run data stays untouched. Do not edit
historical state to change its version. See [V4 migration](docs/migration-v4.md)
and [package rollback](docs/installation-v4.md#upgrade-and-rollback).

MIT — see [LICENSE](LICENSE).
