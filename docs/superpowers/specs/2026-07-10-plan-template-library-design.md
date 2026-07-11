# Plan Template Library Design

## Goal

Add a small, repository-owned library of plan templates that makes the existing
ControlFlow artifact-first workflow easier to start consistently. The library
supports five common task types without adding a planner runtime, router, or
automatic task classifier.

## Scope

This delivery creates paired Markdown and JSON metadata templates for:

- bugfix
- refactor
- migration
- feature
- docs-test-only

It updates the planning skill, public README, and automated contract tests. It
does not implement release packaging, context extraction, automatic template
selection, scope-drift detection, or multi-candidate planning.

## Artifact Design

`plans/templates/` will contain one pair per task type:

- `<kind>-plan-template.md`
- `<kind>-plan-template.meta.json`

Markdown is a complete ControlFlow-plan skeleton with clear placeholders for
the goal, evidence, files, commands, risks, and success criteria. JSON is a
parseable sidecar skeleton with the same goal, tier, phase IDs, dependencies,
files, commands, risks, and criteria. Template placeholders are intentionally
not submitted to `validate-plan.ps1` as executable plans; the template contract
test verifies their structure and JSON syntax instead.

Each template leads with the task-specific invariant:

- Bugfix: reproduce the observed regression before implementation.
- Refactor: characterize and preserve behavior before structural change.
- Migration: state compatibility, backup/rollback, and safety gates.
- Feature: connect requested behavior to a measurable acceptance criterion.
- Docs/test-only: limit scope to documentation or tests and state that runtime
  behavior must not change.

## Planner Behavior

`$controlflow-plan` will map an unambiguous task type to the matching template,
copy it into the task plan, replace every placeholder with repository evidence,
and then create the normal sidecar under `plans/artifacts/<task>/`.

If task type is unclear, the planner asks a clarifying question rather than
selecting a speculative template. Templates guide authoring only; they never
take ownership of native Codex execution, approvals, sandboxing, routing, or
subagents.

## Testing and Documentation

`tests/template-contract.tests.ps1` will assert that all ten template files are
present, every Markdown template includes the ControlFlow required headings and
its type-specific invariant, and every JSON template parses with the mandatory
sidecar fields. `tests/run-contract-tests.ps1` will run it alongside existing
contract checks. The existing Pester wrapper therefore covers the template suite
without a new dependency.

README will document the library, its intentionally manual selection model, and
the difference between a template and a validated plan. The existing skill
contract test will protect the planner's type mapping language.

## Acceptance Criteria

- Five Markdown/JSON template pairs exist under `plans/templates/`.
- Every template pair passes the template contract test in Windows PowerShell
  and PowerShell 7.
- The planner skill documents the five task-type mappings and clarification
  behavior for ambiguous work.
- README documents templates without implying runtime orchestration.
- The full contract suite and `git diff --check` pass.

## Risks and Mitigations

- Placeholder text can look executable: README and the skill will state that a
  template must be grounded in repository evidence before validation.
- A template can drift from the artifact contract: the template contract test
  checks required Markdown sections and JSON fields.
- Task types can overlap: the planner asks rather than guessing when the choice
  affects scope or safety.
