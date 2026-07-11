# Context Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add a dependency-free PowerShell snapshot command that captures git branch, HEAD commit, dirty flag, sorted tracked file tree, and a SHA-256 file-tree digest as JSON, then wire it into the planner and review skills with contract-test coverage.

**Architecture:** `scripts/snapshot-context.ps1` reads only git state and writes one JSON object to stdout. A standalone contract test validates the output shape, sorted file list, and graceful error handling. The planner skill instructs saving the output to `plans/artifacts/<task>/context-snapshot.json` before authoring a plan.

**Tech Stack:** PowerShell, git, JSON, Pester, GitHub Actions.

## Global Constraints

- Keep the plugin skill-only: no router, runtime, task classifier, package dependency, or custom agent.
- The snapshot script must work in Windows PowerShell 5.1 and PowerShell 7.
- The script never executes plan commands; it reads git state only.
- Use only PowerShell standard APIs and git CLI; no modules.
- Every test must pass in both PowerShell shells.

## File Structure

| Path | Responsibility |
| --- | --- |
| `scripts/snapshot-context.ps1` | Captures git state and tracked file tree as JSON. |
| `tests/snapshot-context.tests.ps1` | Contract test for snapshot output shape and edge cases. |
| `tests/run-contract-tests.ps1` | Adds the snapshot test to the portable suite. |
| `tests/controlflow-skill-contract.tests.ps1` | Guards snapshot wording in skills. |
| `skills/controlflow-plan/SKILL.md` | Documents the pre-planning snapshot step. |
| `skills/controlflow-review/SKILL.md` | Mentions snapshot as optional comparison input. |
| `README.md` and `CHANGELOG.md` | Public documentation. |

### Task 1: Snapshot Contract Test

**Files:**
- Create: `tests/snapshot-context.tests.ps1`
- Modify: `tests/run-contract-tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/snapshot-context.tests.ps1` that runs the snapshot script on the repo root with `plans/score-plan-plan.md`, parses the JSON, and asserts all required fields, sorted tracked files, valid commit SHA, and valid digest. Also tests invalid plan path error handling.

- [ ] **Step 2: Register and observe RED**

Add `Invoke-ContractScript "snapshot-context.tests.ps1"` to `tests/run-contract-tests.ps1`. Run the test and confirm it fails because the script does not exist.

### Task 2: Snapshot Script

**Files:**
- Create: `scripts/snapshot-context.ps1`

- [ ] **Step 1: Implement the script**

Parameters: `-RepoRoot` and `-PlanPath`. Resolve paths, extract task slug, capture git state (branch, HEAD, dirty, tracked files), compute SHA-256 digest, emit one JSON object. Handle git-unavailable gracefully. Handle invalid plan path with error JSON and exit 1.

- [ ] **Step 2: Verify GREEN**

Run the contract test and confirm it passes.

### Task 3: Skill and Public Documentation

**Files:**
- Modify: `skills/controlflow-plan/SKILL.md`, `skills/controlflow-review/SKILL.md`, `README.md`, `CHANGELOG.md`, `tests/controlflow-skill-contract.tests.ps1`

- [ ] **Step 1: Write failing skill assertions**
- [ ] **Step 2: Implement minimum wording**
- [ ] **Step 3: Verify GREEN**

### Task 4: Full Verification

- [ ] **Step 1: Run Windows PowerShell suite**
- [ ] **Step 2: Run PowerShell 7 suite**
- [ ] **Step 3: Check whitespace**
- [ ] **Step 4: Commit**
