# ControlFlow for Codex v3

An explicit, compact reliability layer for native Codex. `$controlflow` adds a
durable execution contract and evidence for completion. Native Codex owns tools,
sandboxing, permission decisions, execution, review, and agent lifecycle.

This is a **v3 release candidate**. Deterministic tests establish the mechanical
guarantees; real A/B outcomes and host callbacks need separate evidence before
claiming production readiness.

## Use

### First run

1. Install from a trusted checkout with `pwsh -NoProfile -File scripts/install.ps1 -Force`.
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

- **SMALL / PASS:** the agent records successful checks and coverage; the completion
  gate returns `PASS`. With manual fallback, the agent records completion and reports
  that automatic Stop enforcement was not verified.
- **BLOCKED / manual fallback:** a missing check, inaccessible evidence or unanswered
  question leaves the task incomplete. The agent reports the reason and next action;
  it does not call the task done. Resume an interrupted or blocked run only after
  the user's explicit decision.

The detailed lifecycle is in [execution](skills/controlflow/references/execution.md).

For native plugin text invocation, use `$controlflow-codex:controlflow` with a
repository task. Short aliases such as `$controlflow` require host support.
Native plugins namespace skill names and explicit-only skills may be hidden
from the implicit prompt catalogue. The entry skill chooses the tier
from observed scope, behavior, boundaries, product uncertainty, and risk:

| Tier | Artifacts and review |
| --- | --- |
| TRIVIAL | Native work; no run state or agents |
| SMALL | `plan.meta.json`, captured checks, direct delivery gate |
| MEDIUM | JSON + short rationale; preflight and final conformance review |
| LARGE | MEDIUM with explicit risks/ordering; at most two optional native readers |

An unresolved HIGH risk forces LARGE. Only product-critical missing information
requires clarification. A commit is required only when the user requests it.
There is one production writer per task. Optional readers must have a concrete
question and their usage counts toward the task total.

Use `plans/templates/plan.meta.v3.json` for a new contract and validate it with
`scripts/validate-contract.ps1 -Path <contract>`. The SMALL v3 example is
`plans/examples/small-v3.meta.json`; replace its sample baseline and checks with
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

The schema version is `3.0.0`. All runtime bookkeeping is stored outside project
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
and run. A v2 plan or another session cannot activate a v3 gate.

Old project-local runs are never automatically adopted, rewritten or deleted.
See [migration](docs/migration-v3.md) before moving existing data. Only requested
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

Requires Git and PowerShell 7. The root `plugin.json` is canonical; the
`.codex-plugin/plugin.json` compatibility manifest mirrors its OpenAI extension.

```powershell
pwsh -NoProfile -File scripts/install.ps1 -Force
pwsh -NoProfile -File scripts/install.ps1 -Uninstall -Force
pwsh -NoProfile -File scripts/package.ps1
```

`-HomeRoot <path>` supports isolated installation. The installer validates
ownership and containment, stages the shared inventory, and rolls back a failed
replacement or marketplace update. Other marketplace entries are preserved.
Release smoke extracts the ZIP and installs **that extracted source**.
See [release procedure](docs/release.md) for artifact publication and the stable
release evidence gate.

## Development and evaluation

```powershell
pwsh -NoProfile -File tests/run-contract-tests.ps1
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Pilot -ValidateOnly
```

Windows/Linux CI runs deterministic suites. Authenticated E2E is explicit and
budgeted. [Evals](evals/README.md) compare actual repository outcomes on the same
fixtures/model/settings and count parent plus subagent tokens. Missing checks
or metrics are incomplete, never success. The 12-case pilot is distinct from
the 55-case release corpus; release assessment needs at least three paired
trials and reports paired uncertainty and per-tier regressions.
LARGE graders also exercise the file-to-file CLI. The separate
[critical-risk diagnostic protocol](evals/RISK-DIAGNOSTICS.md) measures collection
and independently reviewed recall; unreviewed findings have no certified recall.

## Migration and rollback

The v3 distribution contains only its current runtime, schema, template and
examples. Retired v2 validators, drift/scoring runners, templates and example
verdicts are removed. The v3 migration command accepts an external v2 contract
and writes a separate copy; inspect its coverage and approve a fresh run.
Do not reuse a v2 verdict as v3 evidence. See
[migration and rollback](docs/migration-v3.md).

MIT — see [LICENSE](LICENSE).

## V4 opt-in candidate

Package `4.0.0-rc.1` adds separate contract/runtime `4.0.0` while v3 remains
default. V4 fixes phase order, exact artifact inputs, original foreign ownership
across planning epochs, manual decision provenance, QA baseline/recheck and
source-bound review packets. Required verified human assurance blocks because no
trusted verifier is provided. Full routes remain compact; safe docs can use light.

Read [runtime interfaces](docs/v4-runtime.md), [migration](docs/migration-v4.md)
and [architecture policy](docs/architecture-policy.md). No new software is
automatically installed. Known report formats do not prove semantic correctness.
Real host callbacks, complete platform-matrix evidence and isolated paired E2E
remain separate acceptance gates. No production-readiness or superiority claim
is made by this opt-in candidate.
