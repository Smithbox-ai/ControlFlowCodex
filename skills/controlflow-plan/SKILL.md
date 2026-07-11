---
name: controlflow-plan
description: "Use when a non-trivial repository task needs a durable, execution-ready ControlFlow plan before coding, especially for cross-file changes, migrations, architectural uncertainty, or explicit risk review."
---

# ControlFlow Plan

## Overview

Produce a saved ControlFlow plan without replacing the host's native planning
workflow. Native `/plan` gathers context and clarifies the task; this skill adds
the durable artifact format, complexity tiers, semantic-risk review, and
restartability discipline. Invoke it explicitly with `$controlflow-plan`.

## Plan Contract Sources

1. If the active repository contains `schemas/planner.plan.schema.json` and
   `plans/templates/plan-document-template.md`, read both and treat them as
   authoritative.
2. Otherwise use the bundled standalone format below.
3. If repository canonical files conflict with the bundled fallback, repository
files win and the difference must be noted under `## Discoveries`.

## Context Snapshot

Before authoring a plan, capture the repository state so later review can
compare the final state against the pre-planning baseline:

1. Run `scripts/snapshot-context.ps1 -RepoRoot . -PlanPath plans/<task>-plan.md`
   when available.
2. Save the JSON output to
   `plans/artifacts/<task>/context-snapshot.json`.
3. Use the snapshot as evidence of the starting branch, HEAD commit, and
   tracked file tree; it does not gate plan creation or add a runtime
   dependency.

The snapshot is taken before authoring the plan and supplements the
artifact-first workflow. It records git branch, HEAD commit, dirty flag,
sorted tracked file tree, and a SHA-256 file-tree digest. The script reads
git state only and never executes plan commands.
## Artifact-First Output

For every non-trivial plan that is ready for execution, produce two aligned
artifacts:

- Artifact A: `plans/<task>-plan.md`
- Artifact B: `plans/artifacts/<task>/plan.meta.json`

Artifact B uses the bundled `schemas/plan-meta.schema.json` contract. It records
the exact plan path, user-facing goal, complexity tier, phases, dependencies,
planned files, commands, semantic risks, and success criteria. Markdown remains
the human-facing source of reasoning and evidence; the sidecar is the structured
projection used for deterministic validation and later comparison. Keep the goal,
tier, and phase IDs synchronized between both artifacts.

## Template Library

For an unambiguous task, start from the matching pair in `plans/templates/`:

| Task type | Markdown template | Metadata template |
| --- | --- | --- |
| bugfix | `bugfix-plan-template.md` | `bugfix-plan-template.meta.json` |
| refactor | `refactor-plan-template.md` | `refactor-plan-template.meta.json` |
| migration | `migration-plan-template.md` | `migration-plan-template.meta.json` |
| feature | `feature-plan-template.md` | `feature-plan-template.meta.json` |
| docs or test only | `docs-test-only-plan-template.md` | `docs-test-only-plan-template.meta.json` |

Copy the matching pair into the task plan and artifact locations, then replace
every authoring marker with verified repository evidence, exact commands, and
measurable criteria. Templates are starting structure, not completed plans; run
the normal sidecar and verdict validation only after grounding them. If the task
type is ambiguous or the choice changes scope or safety, ask a clarifying
question; do not select a template speculatively.

## Multi-Candidate Planning

For `MEDIUM` and `LARGE` complexity tiers, consider producing 2–3 candidate
plans before selecting the best one. Run `$controlflow-verify` on each
candidate, compare their score breakdowns from `scripts/score-plan.ps1`, and
select the candidate with the strongest metrics and fewest blocking findings.
Save the selected plan as the normal artifacts and discard the others.

Multi-candidate planning is optional: use it when the task has architectural
uncertainty or multiple viable approaches. For `TRIVIAL` and `SMALL` tasks,
produce a single plan directly. Do not use multi-candidate planning as a
runtime mechanism; it is an authoring-time technique that leverages the
existing verify and score tools.

## Bundled Plan Format

### Header

- `Status`: `READY_FOR_EXECUTION`, `ABSTAIN`, or `REPLAN_REQUIRED`
- `Agent`: `Planner`
- `Schema Version`: `1.2.0`
- `Complexity Tier`: `TRIVIAL`, `SMALL`, `MEDIUM`, or `LARGE`
- `Confidence`: numeric `0.0-1.0`
- `Abstain`: boolean state plus reasons when true
- `Summary`: one concise paragraph

### Required Main Sections

1. `## Context & Analysis`
2. `## Design Decisions`
3. `## Implementation Phases`
4. `## Inter-Phase Contracts`
5. `## Open Questions`
6. `## Risks`
7. `## Semantic Risk Review`
8. `## Success Criteria`
9. `## Handoff`
10. `## Notes for Execution`

### Feedback Loop Contract

Every non-abstaining plan must preserve the user feedback loop before execution:

- Include a `Goal Statement` in `## Context & Analysis` that restates the
  user-facing outcome in one or two concrete sentences.
- If the goal, constraints, success threshold, or allowed scope is ambiguous,
  ask clarifying questions before marking the plan `READY_FOR_EXECUTION`, or use
  `ABSTAIN`/`REPLAN_REQUIRED` and record the blocker under `## Open Questions`.
- `## Success Criteria` must tie directly back to the `Goal Statement`, and
  Success Criteria must be measurable enough for verification and review to
  decide whether the goal was achieved.

### Phase Shape

Each phase includes:

- objective
- one executor role label
- wave and dependencies
- concrete files and actions
- tests and exact commands
- measurable acceptance criteria
- quality gates from `tests_pass`, `lint_clean`, `schema_valid`, `safety_clear`,
  `human_approved_if_required`
- failure expectations with `transient`, `fixable`, `needs_replan`, or `escalate`
- numbered prose steps

Executor role labels are portable planning metadata, not shipped agents.

### Semantic Risk Review

Include every category exactly once:

- `data_volume`
- `performance`
- `concurrency`
- `access_control`
- `migration_rollback`
- `dependency`
- `operability`

Each row records applicability, impact, evidence source, and disposition. A
`not_applicable` row still requires evidence or justification.

### Living-Document Sections

For non-trivial plans, append these exact headings in this order:

1. `## Progress`
2. `## Discoveries`
3. `## Decision Log`
4. `## Outcomes`
5. `## Idempotence & Recovery`

### Diagram Rules

- Plans with three or more phases include a compact `flowchart TD` dependency DAG.
- `LARGE` plans also include a compact `sequenceDiagram`; `MEDIUM` plans add one
  when orchestration is non-trivial.
- Keep each Mermaid source at or below 30 lines.

### Hard Rules

- No fenced code blocks inside plan artifacts.
- No manual-only verification.
- Prefer 3-10 incremental phases.
- Handoff points to the saved artifact path instead of inlining the plan in chat.
- Non-ready outcomes use a short terminal structure: resolved scope, blockers,
  missing evidence, recovery next step, and partial semantic-risk items.

## Complexity Tiers

- `TRIVIAL` - usually 1-2 files, one concern, low blast radius. Use native Codex
  directly; no plan artifact unless requested.
- `SMALL` - usually 3-5 files in one domain. Save a plan and run
  `controlflow-verify` phase 1.
- `MEDIUM` - usually 6-14 files or multiple concerns. Save a durable plan and run
  verify phases 1-2.
- `LARGE` - usually 15+ files or system-wide/high-impact risk. Save a durable
  plan, run verify phases 1-3, and add research or a spike when material
  uncertainty remains.

Override: any unresolved semantic risk with `applicability: applicable` and
`impact: HIGH` forces `LARGE` regardless of file count.

## Workflow

1. Read the repository before phase decomposition. Keep verified facts separate
   from assumptions.
2. Create a saved plan for `SMALL`, `MEDIUM`, or `LARGE` work; skip it for truly
   `TRIVIAL` work unless the user explicitly requests an artifact.
3. Save Artifact A to `plans/<task-slug>-plan.md` unless the user names another
   path, and save Artifact B to `plans/artifacts/<task-slug>/plan.meta.json`.
4. Map concrete files, tests, commands, dependencies, boundaries, and existing
   patterns.
5. Assign one tier (see Complexity Tiers). Any unresolved applicable `HIGH`
   semantic risk forces `LARGE`.
6. Fill every semantic-risk category exactly once.
7. Keep phases incremental and executable. Each phase names files, tests,
   acceptance criteria, quality gates, dependencies, failure expectations, and
   numbered prose steps.
8. Preserve the five living-document sections for non-trivial plans.
9. Add compact Mermaid diagrams when required by the contract.
10. Use `ABSTAIN` or `REPLAN_REQUIRED` when evidence is insufficient or
    confidence is below the contract threshold.
11. Apply the Feedback Loop Contract: state the goal, ask clarifying questions
    when required, and keep success criteria measurable.
12. Run the deterministic metadata check when the bundled validator is available:
    `scripts/validate-plan.ps1 -RepoRoot . -PlanPath plans/<task-slug>-plan.md -RequirePlanMetadata`.
13. Run `scripts/score-plan.ps1 -RepoRoot . -PlanPath
    plans/<task-slug>-plan.md` when available and retain its JSON output as
    reproducible plan evidence. The scorer reads plan artifacts only and does
    not execute declared plan commands.
14. Hand every non-trivial ready plan to `$controlflow-verify` before
    implementation.

## Execution Deltas

This is the small amount of execution guidance that is ControlFlow-specific. It
does not restate how the host executes; the host owns live state, parallelism,
sandboxing, approvals, retries, and subagent lifecycle.

- Use the saved ControlFlow plan for durable scope, acceptance criteria,
  decisions, and recovery. Use native host plan tracking for the current step and
  next action.
- Update the plan's lifecycle sections at phase boundaries, not after every
  command.
- A resumable plan must identify the next incomplete phase without relying on
  chat history.
- Task-specific evidence belongs under `plans/artifacts/<task-slug>/`. Native host
  memories may help recall preferences, but re-open repository files before
  treating a remembered claim as fact.
- The native host owns subagent spawning and closure; use subagents only when the
  user explicitly requests them. Diagnose before retrying; replan the affected
  phase when the correction changes files, dependencies, acceptance criteria,
  phase order, or blast radius. The native host requires approval before
  destructive or gated work; the plan records the safety gate.

## Behavior Guardrails

### Minimum Viable Change Ladder

Before adding code, phases, dependencies, or abstractions, check in order:
existing project behavior; the standard library or native platform; an
already-installed dependency; one localized line or existing helper. Only then
write new machinery.

### No Speculative Abstractions

- Do not introduce a new class, interface, factory, provider, wrapper, options
  model, extension point, or generic helper only because it might be useful
  later.
- Add a new abstraction only when it removes concrete repeated logic, isolates a
  real policy or integration boundary, or matches an established local pattern.
- A phase that adds an abstraction must name the existing duplication, boundary,
  or local precedent that justifies it. Otherwise keep the change inline or use a
  localized helper.

### Context Language Rule

- Unless the user explicitly requests a documentation or comment language, infer
  the dominant local language from the nearest context: same member, same class,
  same file, then neighboring files in the same feature area.
- Use that language for XML documentation, doc comments, inline comments, and
  business-logic comments. If the nearest context is mixed, prefer the language
  that dominates the class or file being edited.
- When writing C#/.NET or another ecosystem that supports XML documentation, add
  XML documentation to new or materially changed business-significant APIs and
  members. Preserve the local XML style, tag set, and level of detail.
- Add business-logic comments for non-obvious rules, invariants, exceptions,
  compliance constraints, calculations, and rationale. Do not comment obvious
  syntax or repeat names.

### Anti-Rationalization

- Assume a missing requirement -> ask if it changes scope; otherwise record a
  bounded assumption.
- Add future-proof abstraction -> build only accepted scope; record future
  options separately.
- Add dependency before checking native options -> check project behavior,
  standard library, native platform, and installed dependencies first.
- Clean adjacent code -> keep the edit surgical and report the observation.
- Skip verification for prompt or docs changes -> run the smallest relevant
  automated check plus required gates.
- Treat a narrow pass as broad proof -> state exactly what was and was not
  verified.

### Preserving Business Intent

- Document non-obvious business rules, invariants, exceptions, constraints, and
  rationale.
- Use ecosystem-native API documentation when the contract or changed API carries
  business meaning; match the nearest documentation language and style.
- Do not add comments by quota or narrate obvious syntax.

## Native Host Boundary

- Do not implement a second router, task state machine, approval engine, retry
  scheduler, subagent lifecycle, or memory layer.
- Use native host plan tracking for live progress and the saved plan for durable
  state.
- The host owns sandboxing, approvals, and subagent orchestration; use subagents
  only when explicitly requested.
- Host memories are optional ambient context, never repository evidence.

## Planning Failure Checks

- Do not invent requirements that change behavior, scope, architecture, or
  destructive risk.
- Do not mark a plan ready without concrete automated verification.
- Do not add plugin-level runtime controls that Codex already owns.
