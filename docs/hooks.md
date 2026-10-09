# Native hook integration

The supported adapter is a local PowerShell 7 command hook. Its definition is
`hooks/hooks.json`; command paths derive from the native `PLUGIN_ROOT` environment.
It consumes JSON on stdin and emits one JSON object on stdout. It does not parse
session transcripts or intercept commit command text.

Native callback `session_id` and `cwd` select an already active v3 run. An absent
marker leaves the session unmanaged. A corrupt marker, invalid reference, wrong
binding, or missing identity is UNVERIFIABLE. No older v2 plan is adopted and no
foreign session is updated.

Markers and evidence live in the dedicated external ControlFlow state root,
not the callback's working directory. `CONTROLFLOW_STATE_ROOT`, when configured,
must be inherited by both tools and the native hook host; otherwise the default
`CODEX_HOME/controlflow` is used. Subdirectories resolve to the same physical
Git worktree; a sibling worktree or another session cannot adopt its marker.
The hook never creates project-local state or scans old project artifact folders.

Stop runs a fresh completion gate. PASS is required for completion; publishing
COMPLETED repeats the gate under the state transaction. A failed active gate
continues only within the persistent 3-identical/6-total bounds. The signature
uses contract identity, effective source identity, and sorted unmet reason codes.
Changing timestamps or wording cannot reset the repetition count.

Structured lawful stops have a reason and concrete evidence. They allow ending
the turn while keeping the task incomplete. SessionStart reloads context after
resume or compaction; it never treats reopening as a user decision to resume an
interrupted or blocked run. Interrupt stores interruption without a source scan
and never prevents cancellation or restarts the turn. A native pending-interrupt
notification persists even while a capture holds the evidence writer lock.
Readers treat an unacknowledged notification as INTERRUPTED. Explicit resumption
acknowledges that exact notification in the next atomic state revision; a later
interruption remains pending.

If a damaged ledger cannot safely receive a new revision, the adapter returns
`continue: false` with a visible BLOCKED/UNVERIFIABLE warning. It cannot certify
the model's final wording. Fix the observation/state problem and obtain an
explicit user decision before resuming; never label such a turn DONE.

Installation and enabling a plugin do not grant hook trust. The user must review
and trust the exact current hook definition. A hook edit may require trust again.
The plugin does not change global feature flags, sandbox rules, permissions, or
trust lists. Missing/untrusted/disabled hooks require `-ManualFallback` at run
creation and a direct completion-gate call before final claims; report the weaker
automatic guarantee. Cloud orchestration does not support all local command
hooks, even when tools execute locally.

Deterministic protocol tests and actual native host integration are separate.
Tests can prove JSON decisions, state isolation, counters, and recovery. Actual
CLI/Desktop callback evidence must record the enabled definition, callback event,
session binding, native continuation, lawful stop, and interruption behavior.
An E2E run using manual fallback is not proof of automatic Stop enforcement.

Sources: [Codex hooks](https://learn.chatgpt.com/docs/hooks) and
[portable plugin packaging](https://developers.openai.com/plugins/build/plugins).
