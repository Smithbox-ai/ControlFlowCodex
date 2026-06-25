---
name: controlflow-verify
description: "Use after a ControlFlow plan is saved and before implementation. Runs tier-gated adversarial verification inline: structural audit, assumption/mirage detection, and cold-start executability simulation."
---

# ControlFlow Verify

## Overview

Verify a saved plan before implementation. The checks run inline with zero
subagents shipped by the plugin, combining structural audit, mirage detection,
and cold-start executability. Invoke it explicitly with `$controlflow-verify`.

## Input and Contract

- Read the plan from disk; do not verify a chat copy.
- Use the active repository's schema and template when present, otherwise the
  bundled `controlflow-plan` format.

## Tier Gating

| Tier | Verification |
| --- | --- |
| `TRIVIAL` | Skip unless explicitly requested |
| `SMALL` | Phase 1 |
| `MEDIUM` | Phases 1-2 |
| `LARGE` | Phases 1-3 |

Any unresolved applicable `HIGH` semantic risk requires all three phases.

## Adversarial Stance

Apply this stance to every phase; inline verification risks confirmation bias.

- Try to break the plan, not defend it. Steelman the strongest rejection before
  accepting.
- Default to `uncertain` when evidence is insufficient. For each claim ask what
  would make it false, then check that condition.
- The planner is usually careful -> check this claim, not the planner's
  reputation. It probably exists -> open the file or search for the symbol.
  Execution can decide later -> flag it now if it blocks the first phases. The
  risk is low -> name evidence or mark uncertain. I saw it earlier -> reconfirm
  current repository state. The user can fix it later -> block now if it changes
  scope or blast radius.
- Every blocker cites a file, line, command output, or precise reasoning path.
  Planner confidence never substitutes for verifier confidence.

## Phase 1 - Structural Audit

1. Referenced files, paths, tests, and commands are real.
2. Objectives are clear and same-wave write ownership does not overlap.
3. Acceptance criteria are measurable.
4. Verification commands run without guessing.
5. Destructive or migration-heavy work has recovery and the correct safety gate.
6. Dependencies and external contracts are verified or explicitly uncertain.
7. The Minimum Viable Change Ladder was applied before any new abstraction, new
   dependency, or generated surface.
8. The first phases can start without hidden context.
9. Every requested outcome is implemented by a phase.
10. Security, access-control, and operability risks have proportional gates.

## Phase 2 - Assumption and Mirage Check

Apply the mirage catalog to every factual claim. Verify presence claims and
search for missing error, validation, cleanup, migration, and security
requirements. Unknown is `uncertain`, never an automatic pass.

### Mirage Catalog

Presence mirages: P1 Phantom API; P2 Version mismatch; P3 Pattern mismatch; P4
Missing dependency; P5 File-path hallucination; P6 Schema mismatch; P7 Integration
fantasy; P8 Scope creep; P9 Test-infrastructure mismatch; P10 Concurrency
blindness.

Absence mirages: A11 Missing error path; A12 Missing validation; A13 Missing edge
case; A14 Missing requirement; A15 Missing cleanup; A16 Missing migration or
rollback; A17 Missing security boundary.

For each suspected mirage record the plan claim, pattern ID, repository evidence,
classification, and required correction.

## Phase 3 - Cold-Start Executability

For the first relevant phases confirm: what is being changed; exact location;
approach and preserved behavior; required inputs; expected outputs; dependencies;
runnable verification command; concrete test behavior. Simulate opening the file,
reading the existing pattern, writing a failing test, running it, implementing the
minimum change, rerunning tests, and refactoring. Stop at the first hard blocker
and record it.

## Verdict

- `APPROVED`: all required phases pass and implementation may start.
- `NEEDS_REVISION`: the design is viable but specific plan defects must be fixed.
- `REJECTED`: the scope or architecture is not safely deliverable as written.
- Include `failure_classification`: `fixable`, `needs_replan`, or `escalate` for
  non-approval.
- Write a compact verdict to `plans/artifacts/<task-slug>/verify-verdict.md`.
- Do not start implementation until the verdict is `APPROVED`.

## Native Host Boundary

- Do not spawn plugin verifier agents. If the user wants an isolated second
  opinion, native `/review` or an explicitly requested native subagent
  supplements this inline pass.
- The host owns approvals, sandboxing, retries, and subagent lifecycle.