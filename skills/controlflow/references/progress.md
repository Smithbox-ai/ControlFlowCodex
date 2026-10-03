# Native TODO and progress

For multi-step work, use native `update_plan` only when the current host exposes
that tool. Inspect its actual schema; do not imitate a successful call through
a shell command, guess another tool, or introduce a TODO runtime, MCP server,
hook, or parallel task-state store. TRIVIAL does not need a progress ceremony.

At entry or resume, restore a short list of main milestones from the accepted
plan, saved contract, actual repository progress, and available check/review
evidence. Preserve verified completed work and the current stage; do not start
the task again. Incorporate subsequent user changes into that same list.

Use the native statuses the tool supports, typically `pending`, `in_progress`,
and `completed`. Keep the active stage `in_progress` and remaining stages
`pending`. Mark a stage `completed` only after its applicable checks confirm it
and required review findings are resolved. Implementation, validation, release,
and publication may be separate milestones with different evidence and authority.

Update after meaningful milestones, failed checks that reopen work, material
plan changes, and before final delivery. Avoid updates for each small edit.
If contract or source mutation makes the evidence for a milestone stale, reopen
the affected milestone and its dependent validation instead of preserving a
misleading completion status. Reuse unaffected verified progress.

A clarification, denied permission, cancellation, interruption, BLOCKED state,
budget limit, or waiting for a decision keeps the task incomplete. Explain the
reason in the native update's explanation or the accompanying progress message;
do not invent a `blocked` enum if the host lacks it, or mark waiting work complete.
Resume dependent work only on the actual user decision or recovered authority.

If `update_plan` is absent or its call fails, give honest concise textual
progress: verified completed milestones, current work, remaining work, and any
blocking reason. State that the native list was not updated when relevant. Do
not claim native synchronization based on intent or a local document edit.

TODO reflects work status; it is not contract approval, criterion coverage,
check capture, reviewer evidence, or a completion gate. Native progress marked
`completed` never authorizes a commit or DONE. Require fresh delivery-gate PASS
and report actual checks and remaining gaps before final task completion.
