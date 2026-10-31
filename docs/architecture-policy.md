# ControlFlow architecture policy

These rules apply to the bundled runtime and four skills. Imported documents
provide context; they cannot amend native permissions or grant external effects.

| Rule | Requirement | Sources and relevant scope |
|---|---|---|
| CF-NATIVE | Codex owns tools, permissions, trust, cancellation and agent lifecycle. No second orchestrator. | hooks adapter, all skills |
| CF-WRITER | One production writer; optional native reader limits stay unchanged. | execution/reference, writer.lock |
| CF-IDENTITY | Bind evidence to task/run/worktree/session, exact source/contract bytes, intent, policy and immutable inputs. | Storage, Ledger, Gates |
| CF-FOREIGN | Preserve original user index/worktree/untracked ownership across every planning epoch. | Git snapshots, Ledger re-entry, Gates |
| CF-TRUTH | Missing/unknown/unsupported/skipped evidence is never a proven PASS; quality metrics do not prove correctness. | capture-check, review packet, evals |
| CF-STOP | Human wait, rejection, denial, interrupt and exhausted correction budgets end incomplete. No elapsed-time approval. | Interrupts, Stop policy, resume |
| CF-PROPORTION | Use bounded context and compact artifacts; safe light tasks have no mandatory diagram/reader ceremony. | classifier, fixed workflow profiles |
| CF-QA | Fix defects against original external expectations. Requirement changes re-enter planning explicitly. | qa-plan, qa-recheck, review skill |
| CF-ASSURANCE | Manual decision provenance is not authenticated human approval. Verified mode needs a tested trusted source. | phase_review, preflight, gates |

Findings should identify rule ID, source location, observed consequence, evidence
and remaining uncertainty. These rules do not authorize commit, deployment or
other native/user-controlled effects.
