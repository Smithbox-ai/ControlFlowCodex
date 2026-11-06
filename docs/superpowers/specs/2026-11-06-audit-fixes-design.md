# Project audit fixes

The user authorized fixing every finding from the preceding audit. Preserve
the existing mutation improvements and work in the current checkout. No commit,
publication or installation into the user's real plugin home is requested.

1. Completion must reject source or contract changes observed during its gate
   and revalidate the gate's source/contract immediately before publishing a
   completed state, including ignored check inputs and newly pending interrupts.
   Preserve explicit FAIL/ERROR results, ownership and commit
   checks; do not claim filesystem-wide transactional isolation after return.
2. Resolve relative public paths against PowerShell's filesystem location, not
   the process directory. Keep absolute paths and existing path protections.
3. Mutable state, active-pointer and interrupt mailbox readers permit atomic
   deletion/replacement of the old file. Bounded Windows sharing retries handle
   transient incompatible readers; persistent failures remain explicit. Missing
   optional turn_id must not prevent durable interruption.
4. Reject the reserved review target `design` as a V4 criterion/phase ID before
   run creation. Keep V3 semantics and the separate final-review target unchanged.
5. Include Stryker report.scope files in check-input hashing automatically,
   including ignored source files. Hash before/after capture and at every gate
   and summary freshness check. Validate paths before reading; old captures
   lacking this evidence need recapture. Explicit inputs remain supported.
6. Publish the generated inventory sidecar with the archive/checksum and pin
   release actions and Pester consistently with CI, preserving publishing auth.

Use targeted regression fixtures and independent review, then run the complete
contract set after writers are stable. Test the wrong-cwd, source/contract race,
duplicate loaded-module, ignored scope, Windows reader overlap, missing payload
field and reserved-ID cases. Document remaining host/platform verification limits.
