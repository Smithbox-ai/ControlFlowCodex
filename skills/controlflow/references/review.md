# Review and repair

MEDIUM/LARGE need adversarial preflight and final conformance approval. Read the
saved current contract, not a chat copy. A reviewer verifies repository claims,
meaningful checks, failure/rollback paths, ownership, and scope. Unknown facts
remain unknown. HIGH risk unresolved after research keeps the task LARGE.

Native Codex generic review owns correctness/security/style. Consume its
findings, repair blockers, then compare the actual change with the contract:
scope, acceptance evidence, external behavior, and promised operability/rollback.
Any further production edit requires recapturing affected checks and recording
a new final approval for the current complete source identity.

Readers are optional and native: MEDIUM at most one, LARGE at most two concurrent
readers with precise questions. Keep one production writer. If the contract
requires an independent review, self-review cannot satisfy it: record a blocker
until that review arrives or the user explicitly revises the contract. Do not
invent another agent's verdict. Include reader usage in measured task cost.

Write short review rationale inside the run directory and record `preflight`
or `review` through update-run only after actual approval. Runtime binds the
event to the current contract (and source for final review). Adding `APPROVED`
to an old prose verdict does not bind it. The ledger validates that binding;
semantic review quality still depends on the reviewer and independent outcomes.

A failed gate gives concrete repair targets. Iterate while progress and native
authority permit. Missing product input, denied permission, cancellation,
interruption, Plan Mode, and budget exhaustion permit a structured incomplete
turn end. The 3-identical/6-total Stop circuit breaker prevents an endless loop;
it does not turn BLOCKED into DONE. Explicit user input is required to resume.
