# Real repository E2E evaluation (development only)

`run-e2e.ps1` launches the installed **real Codex CLI**. The fake CLI used by
`tests/e2e-evals.tests.ps1` is generated in a temporary test directory and is
never used for a baseline. Nothing in this directory is a plugin runtime
dependency. Evaluation evidence requires actual repository outcomes and native
usage collection.

Unpaid validation:

```powershell
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Pilot -ValidateOnly
pwsh -NoProfile -File evals/run-e2e.ps1 -RepoRoot . -Suite Release -ValidateOnly
pwsh -NoProfile -File tests/e2e-evals.tests.ps1
```

The factory catalog in `e2e-fixtures.ps1` contains 55 named release cases:
5 TRIVIAL, 10 SMALL, 15 MEDIUM, 10 LARGE, 15 TRAP. The 12-case pilot selects
two examples from each ordinary tier plus four safety/product-choice cases.
Each trial creates a separate Git repository; its initial state requires actual
work. The executable hidden oracle and reference repair stay outside the model
repository. Diagnostic case names are absent from the prompt and fixture cwd.
Public tasks specify the desired behavior without describing the trap diagnosis.

The corpus uses PowerShell 7 functions, config files, wrappers, docs, and staged
or unstaged foreign edits. Medium/large tasks add helper/config boundaries;
large tasks include a file-to-file CLI wrapper and interface documentation.
These are controlled synthetic repositories, not a representative sample of
all production software. Hidden behavior checks call the documented operation;
LARGE checks also execute the file-to-file CLI against controlled JSON inputs
and require actual collected output with matching content. The reference repairs are executable sanity checks of
the fixtures, not model results.

## Explicit execution

The following is one **authorized arm**, not an automatic command. The output
directory must be new and outside the source checkout, to keep ancestor project
config/instructions out of trial repositories. Set every model/host/version and
budget field explicitly. No execution occurs without `-Execute`.

```powershell
$arguments = @{
    RepoRoot = 'C:/path/to/ControlFlowCodex'
    Suite = 'Pilot'
    Variant = 'native'
    OutDir = 'C:/path/outside/checkout/pilot-native'
    Model = 'gpt-6.1-sol'
    Effort = 'max'
    HostLabel = 'windows-codex-cli-0.160.0'
    CliPath = (Get-Command codex).Source
    ExpectedCliVersion = '0.160.0'
    SessionRoot = 'C:/Users/Smith/.codex/sessions'
    MaxWallSeconds = 600
    MaxTotalWallSeconds = 7800
    MaxTokens = 500000
    MaxTotalTokens = 2247883
    MaxToolCalls = 150
    MaxRuns = 12
    Trials = 1
    ApprovalPolicy = 'on-request'
    ApprovalReviewer = 'auto_review'
    Sandbox = 'workspace-write'
    WindowsSandbox = 'elevated'
    MarketplaceName = 'controlflow-eval'
}
& ./evals/run-e2e.ps1 @arguments -Execute
```

Use `-DiscoverOnly` with those same arguments to test the real CLI's local
marketplace and prompt rendering **without a model call**. For the v3 arm, set
`Variant=v3`, a new `OutDir`, and the explicit `MarketplaceName` whose unchanged
candidate snapshot is provisioned in the native cache. Set `PluginRoot` to that
immutable candidate source. A copied marketplace alone is discoverable but does
not install the plugin. V3 discovery must declare the exact identity installed
and enabled, with its local source matching this arm's copied snapshot; otherwise
the runner stops before any model trial. Native discovery requires it disabled.
The package snapshot hash may differ from the earlier inactive native snapshot.
Record that difference; compare fixture/model/effort/host/native settings and
budgets exactly. Release assessment needs 55 cases × at least 3 paired trials ×
2 arms, separately authorized with adequate budgets. The current pilot's one
pair per fixture cannot establish the release targets.

`-SettingsPath` optionally supplies a JSON array of provider metadata overrides,
such as `model_provider="openai"`. Authentication remains native. Credentials,
security overrides, and home-directory overrides are prohibited. The runner
does not set HOME, USERPROFILE or CODEX_HOME, edit their config, install hooks,
bypass hook trust, or disable native sandbox/approvals. Native managed/cloud
requirements remain binding and may make a trial incomplete. Fixture Git
identity, autocrlf, signing and empty ignore configuration are repository-local.

The example reserves 152,117 startup tokens (native-4:38,503;
native-6:113,614 including its linked reviewer) from the original per-arm
2,400,000-token agent working cap. The user authorized the scenario runs;
this token cap was an implementation limit. Preserve those attempts' evidence and spend;
neither establishes a valid paired baseline.

Exec ignores user configuration and receives explicit plugin/marketplace CLI
overrides; a copied, hashed local marketplace supplies ControlFlow. Native
has that plugin disabled; v3 enables it and prefixes the same task with explicit
`$controlflow-codex:controlflow`. Real read-only discovery filters the explicit `--marketplace`
name and validates identity, activation state and copied local source.
CLI 0.160 override paths split on literal dots: use bare
`plugins.controlflow-codex@MARKETPLACE.enabled=true`, without TOML key quotes.
`source_type="local"` is supplied independently alongside the source path.
Read-only `debug prompt-input` uses a different loader and remains diagnostic.
Native explicit-only skills are hidden from the available-skills catalog,
and plugin names are qualified. The actual exec rollout must prove native
policy, model/effort and catalog isolation. For v3, the SDK's selected-skill
user fragment must contain `controlflow-codex:controlflow`, the exact owned
native cache path and the complete entry contents matching the immutable
snapshot. Catalog presence alone cannot prove invocation. The runner validates
the cached entry before execution and records `native-entry.expected.json`.
Missing selected entry stays pending during startup; sampling without it or
final missing proof is incomplete. Native rejects selected plugin fragments.
The installed CLI may retain its four native built-in
system skills (imagegen, openai-docs, skill-creator, skill-installer). This is
recorded in actual exec evidence and held constant, not described as zero skills.
No trust grant is inferred from plugin discovery.

SDK 0.160.0 startup has a separate host side effect: for a writable Git fixture
whose trust is unspecified, native thread startup persists a trusted project
entry in the real home `config.toml`. `--ignore-user-config` does not prevent
that write; a profile only changes loading and does not redirect this writer.
Every future initial/resume exec supplies a session-only whole `projects` map
with the fixture's absolute native path and `trust_level="untrusted"`. Windows
keys preserve native separators; slash rewriting does not match the SDK lookup.
This grants no trust and keeps native authentication, sandbox and approvals.
Manifest/result provenance requires `project_trust="untrusted"`; legacy captures
without it are incomplete for pairing and remain preserved as observations.
The corrected localhost-only startup proof retained identical global config
hashes and verified native policy plus SDK skill injection. It also exposed
ambient remote skills, which the strict context guard rejected. Explicit
session overrides now disable the five observed remote plugin identities;
their effectiveness is not yet proven by actual exec. A subsequent offline
startup was rejected by automatic approval review because of the earlier SDK
trust writes. The user then authorized exactly one bounded localhost-only probe.
That probe again preserved the global config hash and proved the selected entry,
but still exposed the same 24 ambient skills despite all five disable overrides.
Actual isolation therefore failed; the host pilot remains on hold. Do not treat
the flags or successful unit tests as SDK isolation evidence. This runner does
not restore global config.

On a user host, temporary cache provisioning must use a new, owned evaluation
namespace, preserve the exact manifest/runtime file inventory, refuse existing
targets, and remove only that owned namespace after related trials finish.
It must preserve global config, trust and authentication home. The native
`plugin add` command writes user enablement settings and is not used for this
host's cache-only pilot. CI uses the development cache helper against an
ephemeral runner. Cache installation metadata and actual SDK injection checks
remain separate from the immutable source snapshot's canonical digest.
Trial raw evidence includes `version.process.json` and `turn-N.process.json`
with adapter-owned exit, timeout, stream and cleanup facts. A missing receipt
cannot certify that related processes stopped before cache cleanup.

On Windows, workspace-write requires an explicit `WindowsSandbox=elevated`
or `unelevated`. `--ignore-user-config` otherwise drops the existing Windows
implementation setting, and native Codex downgrades workspace-write to read-only.
The parameter sets only `windows.sandbox` for the isolated invocation; it does
not modify global settings or disable enforcement. Both arms must match it.
See the [OpenAI configuration documentation](https://learn.chatgpt.com/docs/config-file/config-basic).

Before any trial, the runner executes the exact initial and UUID-resume argv
with empty stdin. Both must exit1 with no stdout and the exact native
`No prompt provided via stdin.` guard, which occurs before generation.
The `policy-preflight` directory keeps argv, stdout/stderr and process evidence.
`--help` skips argument conflicts and cannot validate execution argv.

The adapter passes native `--sandbox <mode>` before `exec` and exact UUID
`exec resume`. CLI 0.160.0 headless execution forces `never` for a user reviewer;
`on-request` with a user reviewer is rejected before generation. The bounded
default is `ApprovalPolicy=never`, `ApprovalReviewer=user`. Explicit
`on-request`, `ApprovalReviewer=auto_review` and `workspace-write` use native
resolved reviewer/policy configuration with the explicit sandbox flag.
`--approve-for-me` conflicts with `--sandbox` in CLI 0.160.0 and is omitted.
No bypass flag is used. Actual rollout `approval_policy`, `approvals_reviewer` and sandbox
must match; pairs must use the same reviewer.

The adapter also passes `--no-daemon`, `--json`, `--ignore-user-config`, the
model/effort and final response schema. A required product
choice is a structured `needs_clarification` response. Only a predeclared answer
whose stable question ID and question regex both match is supplied, or the
unique predeclared regex match when the model chooses another ID. Exact
`exec resume <UUID>` continues that session with the same settings and budget;
`--last` is never used. An unmatched question, denied approval, lawful stop,
cancel, version/session mismatch, timeout, bad JSONL, or missing usage is
`incomplete`. Unmatched or ambiguous questions remain incomplete; no answer is guessed.

## Evidence and measurement

Each arm writes `manifest.json`, immutable plugin inventory, read-only discovery
and prompt evidence, and `trials/fixture-<opaque-hash>/<trial>/`. Each trial keeps
its repository, separate `raw/turn-N.jsonl`, stderr and safe argv, final response schema,
and `result.json`. Results include fixture baseline/content/index provenance,
actual outcome checks, final HEAD, dirty index/diff observations, session IDs,
wall time, model/effort/host/settings/version, budgets, and usage provenance.
The grader checks actual files/behavior, foreign bytes, staged blob/mode/stage
entries, preserved source markers, prohibited or required commits, and whether
task files are actually delivered. A plausible textual "done" is insufficient.
JSON config grading accepts equivalent formatting/property order. Hidden behavior
checks require an unpredictable grader-owned completion receipt with a positive
planned assertion count. Early exit, timeout or missing receipt is incomplete.
Protected files, index and HEAD are observed after the behavior subprocess.

Root and descendant sessions are linked by native `session_meta` IDs and parent
IDs. The latest cumulative `token_count.info.total_token_usage` is counted once
per exact session, including resumption. `cached_input_tokens` is a subset of
input, never added again. Root cwd/model/effort/version and native reviewer must match. Spawned
children need linked completed rollouts and usage; missing metrics stop the
whole arm because remaining total spend is unknown. Raw exec turn usage is
required too; root/child rollout hashes identify the usage sources.
Live telemetry reads use bounded shared-read/write snapshots so an active
native writer cannot hide a policy mismatch. Unterminated append tails and
changing/truncated snapshots remain incomplete; final stable files retain
full byte hashes and observed root/child totals.
Automatic-review model charges are not presumed included in root usage. Native
linked reviewer telemetry must prove inclusion; report unlinked or unavailable
reviewer accounting explicitly when inspecting the real pilot.

Wall budgets include output pipe lifetime after the original process exits.
Windows uses a kill-on-close Job Object; Linux uses a `setsid` process group;
macOS requires `python3` to establish a session before executing the child.
Group cleanup uses `/bin/kill`. Unavailable ownership or incomplete stream
collection fails closed. Windows ownership is regression tested; Linux/macOS
need their CI platform checks. Deliberately detached POSIX descendants are not
proven contained. Token/tool budgets are enforced on
**observed cumulative native telemetry**, both during execution and at the
end. Codex exec exposes no hard pre-request token ceiling: a request or child
already in flight may overshoot before its usage is published and before a
kill reaches it. This is not a strict prepaid cost cap. Summary records actual
observed spend, incomplete/failed/unrun counts, and the stopping reason. No
baseline metrics are invented or inferred from missing files. A structured
invalid-request HTTP 400 before any generation is retained as a rejected attempt,
not a completed model trial. A native parser exit2 with no events/stdout and
explicit error/Usage diagnostics is separately a configuration rejection;
the exact native invalid-UTF8 stdin guard with exit1, empty stdout, no events,
and complete process cleanup is also a provable pre-generation rejection.
The process adapter sends all initial/resume prompts as UTF-8 without a BOM.
A pre-generation rejection leaves the requested model trial unrun. Trusted session IDs and partial telemetry survive
nonzero exits; a rejected final attempt still leaves its requested trial unrun.

Compare completed arms:

```powershell
pwsh -NoProfile -File evals/compare-e2e.ps1 `
  -NativeDirectory C:/results/pilot-native `
  -V3Directory C:/results/pilot-v3 `
  -OutputPath C:/results/pilot-paired.json
```

Pairing requires identical fixture, trial, tier, model, effort, host, CLI,
provider settings, native sandbox/approvals and budgets. Duplicate/mismatched
records are rejected; missing pairs/metrics are reported. Success ingestion
requires nonempty declared provenance, a 64-hex fixture hash, bounded enum
values, a settings array (empty is valid), and positive integral per-run budgets.
Matched null or empty provenance is incomplete and has no measured token median.
Incomplete pairs contribute no success delta or bootstrap sample; when no
pair has complete evidence, the aggregate success delta is null.
Trial identities must be actual positive integers.
Success also requires nonnegative integer token/tool fields, consistent totals and positive
grader collection evidence. Missing metrics cannot become zero-token successes.
Output includes
absolute counts, tier medians, paired success deltas, and a deterministic
fixture-cluster bootstrap interval (2,000 resamples, equal fixture weights).
One cluster has no uncertainty interval. Baseline zero false completions has
no relative reduction. Independent critical-risk diagnostics use a separate
three-case `Diagnostics` suite and bound source/report hashes. Missing artifact
collection is incomplete. Generic diagnostic success verifies source preservation
and artifact collection; it does not establish semantic recall. Every report,
including an empty report, needs independent offline annotation before semantic metrics become complete.
No Diagnostics model run is authorized by the current pilot. `production_ready` always remains
false: real A/B release evidence and Desktop callbacks remain required.
