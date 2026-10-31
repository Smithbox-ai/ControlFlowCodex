param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RunPath,[string]$CommitSha)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
$r=Test-ControlFlowGate @PSBoundParameters -Kind Completion
Write-Output ("Completion gate: {0}" -f $r.status)
if($r.status -eq 'PASS') {
    Write-Output 'Current recorded evidence satisfies the completion gate. This does not verify inputs that were not recorded or the semantic truth of assessments.'
    exit 0
}
foreach($reason in $r.reasons) {
    $code=($reason -split ':',2)[0]
    $action=switch -Regex ($code) {
        '^CHECK_MISSING$' {'Run and capture the declared check.';break}
        '^CHECK_FAILED$' {'Inspect the captured output, fix the failure, then run the check again.';break}
        '^CHECK_STALE$' {'Run the declared check again against the current inputs.';break}
        '^CRITERION_UNCOVERED$' {'Record coverage using a fresh check for this criterion.';break}
        '^(PREFLIGHT|REVIEW)_MISSING$' {'Obtain and record the required assessment.';break}
        '^(PREFLIGHT|REVIEW)_STALE$' {'Repeat and record the assessment against the current contract and source.';break}
        '^OPEN_BLOCKER$' {'Resolve or explicitly retain the blocker before completion.';break}
        '^RUN_NOT_ACTIVE$' {'Inspect the run state; resume an interrupted or blocked run only with an explicit user decision.';break}
        '^UNVERIFIABLE$' {'Inspect the error and restore trustworthy observations before retrying.';break}
        default {'Inspect the reason and the current contract and evidence before retrying.'}
    }
    Write-Output ("{0}: {1}" -f $reason,$action)
}
if($r.ContainsKey('error')){Write-Output ("Detail: {0}" -f $r.error)}
if($r.status -eq 'FAIL'){exit 1}
exit 2
