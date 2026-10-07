# Execute a non-trivial task

Resolve the installed plugin root from this skill's file location. All commands
below are bundled scripts, invoked with `pwsh -NoProfile -File`. Repository and
run paths are explicit. Tools retain native sandbox/permission policy; these
helpers do not grant authority to run a check or commit.

For multi-step work follow [native progress](progress.md): restore the accepted
milestones and verified status, use available `update_plan`, and update after
meaningful milestones or plan changes. If unavailable, report textual progress.
Progress does not replace the contract, captured evidence, or delivery gates.

1. Observe the repository and user request. Use `classify-task.ps1`
   (`ChangedFiles`, `BehaviorChange`, `CrossBoundary`, `ProductQuestion`,
   `HighRisk`) for the observed signals. Do not downgrade an unresolved HIGH
   risk because only one file changes. TRIVIAL returns to native execution.
2. Write `plans/artifacts/<task_id>/plan.meta.json` using
   `plans/templates/plan.meta.v3.json` and `schemas/plan-meta-v3.schema.json`.
   Criteria and checks have unique IDs; each check declares its command,
   repository-relative working directory, and criterion references. Use the
   real HEAD SHA and observed dirty paths. `commit.mode` defaults to `none` and
   becomes `required` only for an explicit user commit request. SMALL needs only
   JSON; MEDIUM/LARGE also write brief rationale **inside the run directory**
   after creation so bookkeeping is excluded precisely from source identity.
3. Run `validate-contract.ps1 -Path <contract>`. Start with
   `start-run.ps1 -RepoRoot <repo> -ContractPath <contract> -SessionId <native-id>`.
   Obtain the session from native runtime identity, such as `CODEX_THREAD_ID`
   when supplied; never invent one. If identity or trusted hook callbacks are
   unavailable, pass `-ManualFallback` and report the limitation. Keep the
   returned `run_path`. A legacy v2 plan needs explicit migration and a new run.
4. For MEDIUM/LARGE, use `$controlflow-verify` and record approved preflight
   through `update-run.ps1` before production edits. Repair/replan when rejected.
   One writer implements using [proportional implementation](#proportional-implementation);
   readers only answer bounded questions. Count all usage.
5. Execute each declared check through
   `capture-check.ps1 -RepoRoot <repo> -RunPath <run> -CheckId <id>`. Read its
   actual exit/output. Review whether the check really proves the criterion;
   record criterion coverage only then. Repair failures and recapture stale checks.
6. For MEDIUM/LARGE, consume native generic review, repair findings, and use
   `$controlflow-review` for conformance. Record bound final review after repair.
7. Run `completion-gate.ps1 -RepoRoot <repo> -RunPath <run>` before final claims.
   When commit is required, first run `commit-gate.ps1` and inspect its concrete
   candidate parent/tree/owned paths. Use native selective commit of those exact
   paths; exclude initial user staging. Rerun completion with `-CommitSha <sha>`.
   No broad staging, amend, or foreign-hunk adoption. A Git hook that changes
   source makes checks/review stale; repair and recapture.

## Proportional implementation

Prefer the smallest coherent implementation satisfying accepted requirements
and fitting existing repository architecture. Smallest means cohesive, not
fewest lines; a focused module can be better than growing an unrelated god-file.

- Follow repository conventions. Refactor adjacent code for correctness, safety,
  or a materially simpler accepted solution; avoid unrelated refactoring.
  Consider removing obsolete code or indirection before adding another layer.
- Keep clear one-use logic local. New abstractions, files, or dependencies need
  current requirements, repository conventions, demonstrated duplication, a
  meaningful boundary, or material testability or side-effect isolation.
  If none applies, prefer simpler concrete code.
- Do not add layers, interfaces, wrappers, factories, helper classes, providers,
  strategies, or configuration surfaces solely for hypothetical future reuse.
  A new file should represent a coherent responsibility or established repository
  organization, not merely an extractable small class/function.
- Compatibility aliases, deprecated paths, migration shims, dual implementations,
  and fallback APIs need an explicit requirement or repository/product evidence.
- Comments and documentation explain non-obvious decisions, invariants,
  constraints, and reasons; avoid restating straightforward code.
- Match validation effort to risk: retain meaningful verification and use existing
  test mechanisms before adding testing infrastructure.

This guides the writer and existing MEDIUM/LARGE preflight and review. TRIVIAL
gains no artifact or review; SMALL gains no mandatory review pass.

Gate JSON uses `status: PASS | FAIL | ERROR`, exits `0 | 1 | 2`. FAIL means
recorded gaps; ERROR means UNVERIFIABLE. Do not equate either with DONE.
With manual fallback, publish a `complete` event after PASS; it rechecks the gate.
Final output states the outcome, actual checks, commit SHA if requested, and gaps.

`update-run.ps1 -RepoRoot <repo> -RunPath <run> -EventPath <json>` accepts events:

```json
{"type":"preflight","status":"APPROVED"}
{"type":"coverage","criterion_id":"C1","check_ids":["check-1"]}
{"type":"review","status":"APPROVED"}
{"type":"blocker","id":"B1","status":"OPEN","text":"Concrete defect"}
{"type":"stop","reason":"CLARIFICATION","evidence":"Unknown product default","pending_decision_id":"choice-1","question":"Which default?"}
{"type":"resume","user_decision_ref":"Actual user reply reference"}
{"type":"complete"}
```

Use one event object per file, stored inside the run directory. Blockers resolve
with a `blocker` event of the same ID and `status: RESOLVED`, citing the fix in
`text`. Other lawful stop reasons are `PERMISSION_DENIED`, `CANCEL`, `PLAN_MODE`,
`BLOCKED`, and `INTERRUPT`; all require concrete evidence. A user question ends
the turn pending an answer. A guessed answer or elapsed time is not resumption.

Helpers capture evidence and gate delivery. They do not schedule tools, retry
checks, manage agents, infer user decisions, or bypass native permissions.
