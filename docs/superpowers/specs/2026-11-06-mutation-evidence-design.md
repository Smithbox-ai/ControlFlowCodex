# Mutation evidence and selection

The user approved implementing the preceding audit recommendations. The change
must make mutation evidence relevant to the declared source, report its actual
outcome, and prompt a proportionate decision about test sensitivity.

Use the existing V4 contracts, QA artifacts, captures and review packets. New
code-judged QA plans record a mutation assessment: run, skip or unsupported with
a reason, scope and criterion/check references. A run declares its method,
budget and acceptance criterion. Stryker uses the existing report adapter;
controlled faults use ordinary declared checks in an isolated copy. All run
checks also belong to QA scenarios, preserving existing freshness and capture
requirements. Existing immutable QA artifacts and V3 remain readable.

Mutation report capture validates literal repository-relative scope, report file
correspondence and embedded source against the current repository. Reject
unrelated, omitted, outside-scope and mismatching source reports. Capture uses
the check's working directory to resolve report-relative files. Do not infer
tool authenticity from these consistency checks. Standalone report parsing
without repository context remains a measurement API.

Required available mutation checks in final contracts declare a positive
project-specific minimum_score. Optional measurements can omit a threshold;
their result must explicitly distinguish measurement from configured acceptance.
Review still assesses material surviving/no-coverage faults; no global score is
introduced. Profile summaries preserve FAIL, ERROR, TIMEOUT, STALE and NOT_RUN
with deterministic precedence and per-check observations.

Skills recommend bounded sensitivity evidence for recurring defects, critical
guards/data invariants and changed boundaries/branches. Bugfixes demonstrate
failure on the original defect. Documentation and mechanical changes may skip
with a reason; no scanner is automatically installed.

Alternatives considered: instructions alone leave report mismatches unguarded;
mandatory mutation runs for every task add cost and unsupported-tool blockers.
The selected approach combines deterministic consistency checks with a required
planning decision and risk-based recommendations.

Work stays in the suitable clean current checkout. No commit, push, publishing,
installation or database changes are part of this task.
