# ControlFlow v3 implementation plan

Accepted in chat on 2026-10-03; implement without committing or publishing unless requested.

User amendment after candidate delivery: remove obsolete v2 files from the v3
repository and distribution, update documentation, and commit the checked result
to main. This supersedes the initial keep-v2-readers/templates requirement and
authorizes a local main commit. Migration of an external old input remains a v3
capability; no v2 runtime or templates are shipped. A/B remains separately
blocked by actual native SDK ambient isolation; do not claim release readiness.

## Binding specification

- Explicit `$controlflow`; commits only on explicit user request. Windows/Linux, PowerShell 7, CLI and locally orchestrated Desktop. Keep three manual skills with v3 binding; remove obsolete v2 files.
- Native execution/sandbox/permissions/review/agents stay native. No custom runtime, MCP or PreToolUse commit parser.
- TRIVIAL no state/agents; SMALL JSON only; MEDIUM/LARGE JSON + rationale. Unresolved HIGH risk -> LARGE. Ask product-critical questions only.
- Contract schema 3.0.0 adds IDs/references for criteria/checks, assumptions, commit none|required. Contract mutation invalidates preflight/check definition/coverage; source mutation invalidates checks/final review.
- Separate foreign initial index (OID/mode/stage), worktree and untracked content. Detect later mutation of dirty paths; never subtract them. No foreign hunks in commit without explicit authority; overlap -> native worktree or concrete human ownership decision.
- Source digest: effective contents/types/modes/deletions vs immutable initial baseline, not HEAD/staging/timestamps. Stage/commit identical content preserves evidence. Incomplete Git -> ERROR/UNVERIFIABLE/BLOCKED.
- Deterministic single-check capture via native tools records command/cwd/exit/output hash and before/after digest. Ledger checks provenance/freshness/coverage, not truth of LLM PROVEN.
- Immutable evidence/output revisions; state.json sole atomic publication point, OS-held exclusive lock. Crash sees coherent old/new state; corrupt/missing references -> UNVERIFIABLE.
- Runtime artifacts use the dedicated external state root resolved by get-storage-paths.ps1. Contracts, runs and active markers are separated by physical worktree/Git identity and session; no project bookkeeping directory. Bind trusted native session + task + run. No v2/foreign adoption or guessed session.
- Gate JSON PASS|FAIL|ERROR exits 0|1|2. Commit gate verifies deliverability/ownership; completion adds actual SHA/tree only for required commit.
- Stop lawful clarification/needed denied permission/cancel/Plan Mode/BLOCKED != DONE. Structured reason/evidence. Third identical no-progress signature or sixth attempt -> BLOCKED. Interrupt never auto-resumes.
- Missing/untrusted hooks -> explicit fallback and accurate weaker guarantee. Minimal Stop/resume/interrupt adapters, no transcript parser.
- One writer; optional measured native readers MEDIUM 0-1, LARGE <=2 concurrent. Generic native review -> repair -> conformance.
- User amendment during implementation: synchronize multi-step progress through native `update_plan` when available; restore accepted milestones and verified progress after resume, update after substantial milestones/plan changes, keep waiting/blocked work incomplete. Honest textual fallback when absent. No separate TODO runtime/MCP; TODO never substitutes for evidence/gates.
- A/B real repository outcome, same fixtures/model/effort/host/budgets/settings, >=3 paired trials. Parent+children usage without double count. Missing metrics/checks never success. Release smoke installs extracted ZIP.

## Execution tasks

A. Build dev-only real Codex CLI E2E adapter, scripted responder, hidden graders, 12 neutral pilot and 55 release fixtures (5 trivial/10 small/15 medium/10 large/15 traps); strict results/usage and paired aggregation. Real model runs require explicit configured budgets; never fabricate baseline.

B. Portable root plugin.json with OpenAI extension and consistent compatibility overlay; shared package inventory; paired example artifacts; extract/archive install tests.

C. Strict NUL-safe Git observation, scope matching, foreign snapshot, stable source digest; transactional bounded installer and marketplace preservation. Reject retired v2 package paths.

D. V3 schemas/readers/migration copy; start-run, capture-check, update-run; immutable evidence and atomic state; preflight/review identity; crash/provenance tests.

E. Explicit short entry skill, tier-specific progressive instructions, observed-signal classification and direct delivery/commit/completion gates; actual selective commit verification.

F. Stop/resume/interrupt hook protocol, trusted session identity, lawful stops, 3/6 circuit breaker, isolation/recovery/fallback and separate host integrations.

G. Native review/conformance repair loop and measured optional readers; unresolved required independent review remains a gap. Native TODO/progress policy shared by entry and manual skills, with unavailable-tool fallback and documentation/checks.

H. Windows/Linux deterministic CI, opt-in authenticated E2E/nightly, 55x3x2 release assessment, v3 candidate package/docs/migration/rollback.

## Release targets

Zero observed corruption/unsafe commit/false DONE with failed gate; no observed tier task-success/critical-risk recall regression; small/trivial median tokens <=10% overhead; medium/large success +5pp OR trap false completion -50% without success regression. Count blocked/abandoned as incomplete. Report absolute counts, paired fixture-clustered uncertainty; baseline zero false completion has no relative reduction. Real A/B and Desktop callback evidence required before production-readiness claims.

## Review focus

Partial staging and dirty-path mutation; stage/commit digest invariance; contract/source invalidation; atomic crash recovery; lawful Stop vs completion; incomplete Git/check/usage collection; extracted artifact layout/install and rollback.
