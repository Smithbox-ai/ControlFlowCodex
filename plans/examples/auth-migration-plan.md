# Plan: Migrate auth tokens to a new format without downtime

> Machine-critical data lives in `plans/artifacts/auth-migration/plan.meta.json`.
> This file holds only human rationale.

## Goal & Non-Goals

Goal: Accept the new token format while still accepting legacy tokens throughout
the migration window, with zero auth downtime.

Non-goals: rotating existing tokens; changing the authn protocol surface.

## Decisions

- Dual-read path: verify tokens against both formats during the window, so
  rolling back the writer does not break readers.
- Format switch is gated behind a flag, flipped per environment after the
  dual-read checks pass.

## Notes

- Rollback: disable the flag and keep the legacy writer; the dual-read remains
  valid until the window closes.
- Evidence: `tests/auth` already covers the legacy path; add cases for the new
  format and mixed tokens.

## Open Questions

- none
