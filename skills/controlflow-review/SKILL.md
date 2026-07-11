---
name: controlflow-review
description: "Use after implementation when a ControlFlow plan exists and review should focus on plan conformance, scope drift, evidence-backed correctness findings, and residual validation gaps rather than duplicating native Codex /review."
---

# ControlFlow Review

## Overview

Add the ControlFlow-specific layer after implementation: compare the aggregate
diff to the approved plan, reconcile scope drift, and require evidence-backed
findings. Native host review (Codex `/review`) remains the general code-review
pass; consume its results rather than repeating them. Invoke it explicitly with
`$controlflow-review`.

## Local Contract

- Read the approved plan, its `plans/artifacts/<task>/plan.meta.json` sidecar
  when present, and the aggregate diff.
- If native review results are available, consume them rather than repeating the
  same mechanical/style pass.
- Findings come first, ordered by severity, with file/line evidence and
  confidence. Distinguish validated blockers from hypotheses and state validation
  gaps.

## Review Checklist

This covers the ControlFlow-specific layer: plan conformance, over-engineering,
and aggregate scope reconciliation. Native `/review` owns general correctness,
style, security, and size-signal mechanics.

### Over-Engineering Pass

After correctness, security, data integrity, and scope checks, ask what can
delete, inline, or replace with a standard library or native platform feature.
Flag one-use abstractions, speculative configuration, wrappers with no policy
value, and new dependencies an already-installed dependency or platform primitive
covers. Treat over-engineering as a maintainability signal; block only when it
creates real review, behavior, test, dependency, or operability risk.

### Documentation and Comment Pass

Verify that changed code includes XML documentation and business-logic comments
where it introduces or changes business-significant APIs, rules, invariants,
exceptions, compliance constraints, calculations, or rationale. The documentation
and comments must use the dominant local language unless the user explicitly
requested a different language. Flag missing or mismatched documentation when it
can obscure business behavior, public contracts, or maintenance-critical intent.
Also flag any speculative abstraction added without concrete duplication, a real
boundary, or an established local pattern.

### Stop-the-Line Decision Points

Halt for security, authorization, secret-handling, destructive-action, or
data-integrity defects; failed core behavior or acceptance criteria;
migration/schema/contract changes without rollback or compatibility evidence; or
scope drift that prevents comparison to the approved plan.

### Feedback Loop Closure

Close the feedback loop by comparing the implementation, tests, and stated
evidence with the approved goal and success criteria. If the result cannot show
that the user-facing goal was reached, or if criteria changed without an approved
plan update, treat that as scope drift or a validation gap rather than a completed
handoff.

### Out-of-Scope Reconciliation

Compare every aggregate changed path and behavior to the approved phases.
When a `context-snapshot.json` artifact exists, compare the final tracked file tree against the pre-planning baseline to detect files added, removed, or changed outside the plan scope. Run `scripts/detect-drift.ps1 -RepoRoot . -PlanPath plans/<task>-plan.md` when available to classify each changed path as `approved_follow_through`, `justified_deviation`, or `blocking_scope_drift` against the planned files in `plan.meta.json`. Classify each difference as approved follow-through, justified deviation, or blocking scope drift. When metadata is present, compare changed paths with its planned paths and compare final evidence with its structured success criteria; record any Markdown-to-metadata mismatch as a validation gap.

### Novelty Filter

Compare final findings with prior phase findings. Mark recurring findings as
regressions and report only genuinely new findings as novel. Re-check verified
items affected by later revisions.

## Evidence Discipline

Separate what you observed from what you inferred.

- Strong: direct file/line references, command output you ran, repository
  tests/fixtures demonstrating behavior.
- Acceptable inference: short extrapolations from nearby code or architectural
  implications that follow directly. Mark as inference, not verified fact.
- Weak: memory of older file contents, unverified framework-default assumptions,
  "probably breaks" with no path. If you cannot point to file, line, command
  output, or a precise reasoning path, downgrade or omit the finding.

## Validation Status Labels

- `confirmed` - verified directly from code, tests, or command output; strongest
  candidates for blocking findings.
- `likely` - reasoning is strong but not fully reproduced; good for advisory or
  near-blocking issues.
- `unvalidated` - plausible but not yet proven; state what would validate it. Do
  not present as blockers unless the risk is extreme and clearly explained.

## Security Review Discipline

Use only when this review enters a security-focused pass on a plan that touches
authentication, authorization, secrets, or trust boundaries. General security
review belongs to native `/review`; this only adds anti-noise rules.

- Confidence threshold: flag a security vulnerability only when confidence is
  >80%; below that, record as an observation.
- Exclusion list: do not flag DoS without a concrete exploitation chain,
  secrets-on-disk hygiene, rate-limiting gaps without a concrete abuse scenario,
  theoretical issues without a realistic path, or style/formatting.
- Skip for ordinary refactors with no trust-boundary impact.

## Soft Comment Labels

Use `Nit`, `Optional`, and `FYI` only after blocking findings. These are not
severity levels and must not hide correctness, security, or test coverage
defects.

## Change Size Caution

When a diff is much larger than roughly 100 changed lines or mixes unrelated
concerns, ask for a split or review by file area and risk axis with an explicit
confidence limit.

## Review-Specific Failure Checks

- Do not lead with nits before behavior checks.
- Do not mark missing tests as `FYI` when the untested behavior can regress.
- Do not state a blocker without validation evidence or an explicit
  unconfirmed-risk label.
- Do not duplicate native host review's mechanical findings.
- Do not skip plan comparison when an approved plan exists.
