# Context Snapshot Design

## Goal

Add a deterministic, dependency-free PowerShell command that captures the
repository state immediately before planning, so every ControlFlow plan carries
a reproducible baseline of the branch, commit, and tracked file tree that
existed when the planner started. The snapshot supplements the existing
artifact-first workflow without adding a runtime, router, or external service.

## Scope

This delivery creates `scripts/snapshot-context.ps1`, a standalone contract test,
planner and review skill updates, and public documentation. It does not
implement automatic scope-drift detection, multi-candidate planning, release
packaging, or a planning runtime.

## Design Decision: Save Alongside Plans

The snapshot is saved to `plans/artifacts/<task>/context-snapshot.json` alongside
the plan metadata and verifier verdict. This keeps all task evidence in one
directory and lets `$controlflow-review` compare the final repository state
against the pre-planning baseline. The script itself writes JSON to standard
output (consistent with `score-plan.ps1`); the planner skill instructs saving
the output to the artifact location.

## Snapshot Content

The JSON output contains:

- `schema_version`: `1.0.0`
- `plan_path`: the relative plan path (forward-slash normalized)
- `task_slug`: extracted from the plan filename
- `captured_at`: ISO 8601 UTC timestamp
- `git.available`: whether git is reachable
- `git.branch`: current branch name (`null` if git unavailable)
- `git.head_commit`: full SHA-1 of HEAD (`null` if no commits or git unavailable)
- `git.dirty`: `true` if the working tree has any staged, unstaged, or untracked
  changes; `false` if clean
- `git.tracked_files`: sorted array of all git-tracked file paths
- `git.tracked_file_count`: integer count of tracked files
- `git.file_tree_digest`: SHA-256 of the sorted tracked file list joined by
  newlines, for quick structural comparison

## Planner Behavior

`$controlflow-plan` will instruct the planner to run
`scripts/snapshot-context.ps1 -RepoRoot . -PlanPath plans/<task>-plan.md` before
authoring the plan, and save the output to
`plans/artifacts/<task>/context-snapshot.json`. The snapshot is evidence of the
starting state; it does not gate plan creation or add a runtime dependency.

## Review Behavior

`$controlflow-review` will mention the context snapshot as an optional input for
comparing the final repository state against the pre-planning baseline, helping
identify scope drift through new, removed, or changed tracked files.

## Testing and Documentation

`tests/snapshot-context.tests.ps1` will assert that the script produces valid
JSON with all required fields, that tracked files include known repository
files, that the file list is sorted, and that the digest is a 64-character
hexadecimal string. It will also verify graceful behavior when the plan path does
not match the `-plan.md` convention. `tests/run-contract-tests.ps1` will run it
alongside existing contract checks.

README will document the snapshot command, its artifact location, and its
role as evidence rather than a planning gate. CHANGELOG will record the
addition.

## Acceptance Criteria

- `scripts/snapshot-context.ps1` emits one parseable JSON object with all
  required fields and a stable `schema_version`.
- The snapshot captures git branch, HEAD commit, dirty flag, sorted tracked
  file tree, tracked file count, and a SHA-256 file-tree digest.
- The script never executes plan commands and adds no dependencies.
- The planner skill documents the snapshot step and artifact location.
- The review skill mentions the snapshot as an optional comparison input.
- README and CHANGELOG document the feature.
- Windows PowerShell and PowerShell 7 full suites pass.

## Risks and Mitigations

- Git may be unavailable in some environments: the script sets `git.available`
  to `false` and emits null git fields rather than crashing.
- The tracked file list can be large in big repositories: the full list is
  included because the plugin targets small to medium repos; callers can
  redirect and truncate if needed.
- The timestamp makes each snapshot unique: this is intentional for a
  point-in-time capture; tests validate the field exists and is a valid ISO
  string without checking the exact value.
