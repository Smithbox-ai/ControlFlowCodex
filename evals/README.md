# ControlFlow behavioral evals

These are **behavioral** regression tests for the ControlFlow skills, not
structural validators. They check whether the skills still do the right thing
after the Compact vNext refactor: does the verifier catch a phantom API, does
review catch scope drift, does a dirty worktree get recorded, and are plan
artifacts staying compact?

## Why this exists

Structural contract tests (`tests/`) prove the artifact *shape* is valid.
They cannot prove the *model behavior* is correct. This harness is the one new
capability added in vNext, because the refactor removes a lot of prompt text and
the only honest way to know that did not hurt quality is to measure it on a
fixed corpus.

## Layout

```
evals/
  cases/        one JSON per scenario (task + expected behavior)
  expected/     optional golden artifacts (reserved)
  baseline/     static-metrics.json captured before the refactor
  legacy/       the retired score-plan.ps1, kept for optional offline correlation
  run-evals.ps1 the scoring runner (dev/CI only, no runtime dependency)
```

## Case shape

```json
{
  "id": "phantom-api",
  "task": "<the prompt handed to the planner/verifier>",
  "tier": "SMALL",
  "must_detect": ["strings that MUST appear in the produced verdict/plan/meta"],
  "must_not_do": ["strings that MUST NOT appear (e.g. an approval it should not give)"],
  "max_artifact_bytes": 12000
}
```

## Running an eval pass

The runner scores **already-produced** artifacts; it does not call a model
itself. Produce the artifacts first by running the skills (locally or in nightly
CI) and dropping each case's output under a runs directory:

```
<runs-dir>/
  phantom-api/
    plan.md
    plan.meta.json
    verify-verdict.md
    metrics.json   # { input_tokens, output_tokens, tool_calls, wall_ms, success }
```

Then score:

```powershell
pwsh -File evals/run-evals.ps1 -RepoRoot . -RunsDir <runs-dir> -Variant compact-vnext
```

`-ValidateOnly` just checks every case JSON is well-formed (used in PR CI).

## Metrics recorded

For each case: `success`, `must_detect_found`, `must_not_do_violated`,
`artifact_bytes`, and any `metrics.json` fields. Aggregated across the corpus:
success rate, critical-findings recall, false-positive rate, and medians for
tokens, artifact bytes, and tool calls. Results are written to
`evals/results/<variant>.json` and `<variant>.csv`.

## Acceptance targets (Compact vNext)

| Metric | Target |
| --- | --- |
| Median total tokens | >= -25% vs v1 baseline |
| Median plan artifact bytes | >= -40% |
| Task-success regression | <= 2-3 pp |
| Critical-risk recall regression | 0 on the high-risk corpus |

These are engineering goals measured by this harness, not promises.
