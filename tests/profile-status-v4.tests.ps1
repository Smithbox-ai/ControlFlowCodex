. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$module=Get-TestControlFlowModule
$r=NewFixture
function NewSummaryFixture([string]$Report='{"schemaVersion":"1","files":{"owned.txt":{"source":"initial","mutants":[{"id":"1","status":"Killed"}]}}}') {
    File $r '.cache/mutation.json' $Report
    $check=@{id='mutation-1';command='Write-Output mutation';working_directory='.';criteria=@('C1');report=@{format='stryker-json';path='.cache/mutation.json';minimum_score=80;scope=@('owned.txt')}}
    $quality=Read-ControlFlowQualityReport (Join-Path $r '.cache/mutation.json') stryker-json 1 80 -RepoRoot $r -Scope @('owned.txt')
    $quality.raw_report_ref=@{path='output/00000000000000000000000000000000.stdout.bin';sha256=('0'*64)}
    $capture=@{capture_id='capture-1';check_id='mutation-1';status=$(if($quality.status -ceq 'PASS'){'PASS'}else{'FAIL'});exit_code=0;timed_out=$false;process_incomplete=$false;contract_digest='contract-current';command_digest=(& $module {param($Check) Get-CFJsonHash $Check} $check);source_before='source-current';source_after='source-current';quality=$quality}
    $capture.input_before=& $module {param($Root,$Check) Get-CFCheckInputDigest $Root $Check} $r $check
    $capture.input_after=$capture.input_before
    return @{read=@{state=@{binding=@{worktree_realpath=$r}};evidence=@{checks=@($capture)}};contract=@{digest='contract-current';contract=@{checks=@($check)}};source=@{digest='source-current'};profile=@{id='mutation';kind='mutation';required=$false;capability='available';check_ids=@('mutation-1')}}
}
function Summary($Fixture) { & $module {param($F) Get-CFV4ProfileSummary $F.read $F.contract $F.source $F.profile} $Fixture }
try {
    # A failed optional profile must remain visible even though it does not block completion.
    $f=NewSummaryFixture '{"schemaVersion":"1","files":{"owned.txt":{"source":"initial","mutants":[{"id":"1","status":"Survived"}]}}}'
    $summary=Summary $f
    Assert ($summary.status -ceq 'FAIL' -and -not $summary.required) 'FailedOptionalProfileIsFail'
    Assert ($summary.id -ceq 'mutation' -and $summary.kind -ceq 'mutation' -and $summary.capability -ceq 'available' -and $summary.check_ids[0] -ceq 'mutation-1') 'ProfileIdentityAndCapabilityPreserved'
    Assert ($summary.observations[0].capture_status -ceq 'FAIL' -and $summary.observations[0].quality_status -ceq 'FAIL' -and $summary.observations[0].quality.mutation_score -eq 0) 'ThresholdFailureKeepsRawObservations'
    Assert ($summary.observations[0].quality.acceptance_status -ceq 'FAIL' -and $summary.observations[0].quality.scope_verified -and $summary.observations[0].quality.verified_scope[0] -ceq 'owned.txt') 'AcceptanceAndScopeObservationsPreserved'
    Assert ('QUALITY_REPORT_FAILED' -cin $summary.observations[0].reasons) 'ThresholdFailureHasReason'

    $f=NewSummaryFixture;$f.read.evidence.checks[0].source_after='old-source'
    $summary=Summary $f
    Assert ($summary.status -ceq 'STALE' -and $summary.observations[0].quality_status -ceq 'PASS' -and 'CAPTURE_SOURCE_MISMATCH' -cin $summary.observations[0].reasons) 'StaleSourceDoesNotMasqueradeAsUnrun'
    foreach($field in @('contract_digest','command_digest')){
        $f=NewSummaryFixture;$f.read.evidence.checks[0][$field]='old'
        Assert ((Summary $f).status -ceq 'STALE') ('BindingMismatchIsStale:'+ $field)
    }
    $f=NewSummaryFixture;$f.read.evidence.checks[0].status='STALE'
    Assert ((Summary $f).status -ceq 'STALE') 'ExplicitStaleCaptureIsStale'

    $f=NewSummaryFixture;$f.read.evidence.checks=@()
    $summary=Summary $f
    Assert ($summary.status -ceq 'NOT_RUN' -and 'CAPTURE_MISSING' -cin $summary.observations[0].reasons) 'AbsentCaptureIsNotRun'
    $f=NewSummaryFixture '{"schemaVersion":"1","files":{"owned.txt":{"source":"initial","mutants":[{"id":"1","status":"Pending"}]}}}'
    $summary=Summary $f
    Assert ($summary.status -ceq 'NOT_RUN' -and $summary.observations[0].capture_status -ceq 'FAIL' -and $summary.observations[0].quality_status -ceq 'NOT_RUN' -and $summary.observations[0].quality.counts.Pending -eq 1) 'PendingReportOverridesOuterFailWithoutHidingObservation'
    $f=NewSummaryFixture;$f.read.evidence.checks[0].quality=Read-ControlFlowQualityReport (Join-Path $r 'missing.json') stryker-json;$f.read.evidence.checks[0].status='FAIL'
    Assert ((Summary $f).status -ceq 'NOT_RUN') 'MissingReportIsNotThresholdFailure'
    $f.read.evidence.checks[0].exit_code=1
    $summary=Summary $f
    Assert ($summary.status -ceq 'FAIL' -and $summary.observations[0].quality_status -ceq 'NOT_RUN' -and $summary.observations[0].exit_code -eq 1) 'NonzeroProcessExitWithMissingReportIsFail'
    $f.read.evidence.checks[0].exit_code=0;$f.read.evidence.checks[0].process_incomplete=$true
    $summary=Summary $f
    Assert ($summary.status -ceq 'FAIL' -and $summary.observations[0].quality_status -ceq 'NOT_RUN' -and $summary.observations[0].process_incomplete) 'IncompleteProcessWithMissingReportIsFail'
    $f=NewSummaryFixture;$f.read.evidence.checks[0].quality.Remove('raw_report_ref')
    Assert ((Summary $f).status -ceq 'NOT_RUN') 'UncapturedReportCannotPass'
    foreach($scopeCase in @('missing','false','different','case-different')){
        $f=NewSummaryFixture
        switch($scopeCase){
            'missing'{$f.read.evidence.checks[0].quality.Remove('scope_verified')}
            'false'{$f.read.evidence.checks[0].quality.scope_verified=$false}
            'different'{$f.read.evidence.checks[0].quality.verified_scope=@('foreign.txt')}
            'case-different'{$f.read.evidence.checks[0].quality.verified_scope=@('Owned.txt')}
        }
        $summary=Summary $f
        Assert ($summary.status -ceq 'NOT_RUN' -and 'QUALITY_SCOPE_UNVERIFIED' -cin $summary.observations[0].reasons) ('HistoricalOrMismatchedScopeCannotPass:'+ $scopeCase)
    }

    $f=NewSummaryFixture;$f.read.evidence.checks[0].status='TIMEOUT';$f.read.evidence.checks[0].timed_out=$true
    $summary=Summary $f
    Assert ($summary.status -ceq 'TIMEOUT' -and $summary.observations[0].quality_status -ceq 'PASS') 'WrapperTimeoutDoesNotEraseReportOutcome'
    Assert ($summary.observations[0].timed_out -and $summary.observations[0].exit_code -eq 0 -and -not $summary.observations[0].process_incomplete) 'WrapperObservationRetainsExecutionDetails'
    $f=NewSummaryFixture '{malformed'
    $summary=Summary $f
    Assert ($summary.status -ceq 'ERROR' -and $summary.observations[0].quality.error) 'MalformedReportIsError'
    $f=NewSummaryFixture;$f.read.evidence.checks[0].status='FAIL';$f.read.evidence.checks[0].exit_code=1
    Assert ((Summary $f).status -ceq 'FAIL') 'FailedWrapperWithPassingReportIsFail'

    foreach($capability in @(@('unsupported','UNSUPPORTED'),@('not_applicable','NOT_APPLICABLE'),@('unknown','NOT_RUN'))){
        $f=NewSummaryFixture '{malformed';$f.profile.capability=$capability[0]
        Assert ((Summary $f).status -ceq $capability[1]) ('CapabilityPrecedesCheckResults:'+ $capability[0])
    }
    $f=NewSummaryFixture;$f.profile.check_ids=@()
    Assert ((Summary $f).status -ceq 'NOT_RUN') 'EmptyProfileIsNotRun'

    # The profile keeps every latest check and chooses a stable aggregate regardless of check order.
    $f=NewSummaryFixture;$checks=@();$captures=@()
    foreach($pair in @(@('pass','PASS'),@('unrun','NOT_RUN'),@('stale','STALE'),@('timeout','TIMEOUT'),@('fail','FAIL'),@('error','ERROR'))){
        $check=$f.contract.contract.checks[0]|ConvertTo-Json -Depth 40|ConvertFrom-Json -AsHashtable;$check.id=$pair[0];$checks+=,$check
        $capture=$f.read.evidence.checks[0]|ConvertTo-Json -Depth 40|ConvertFrom-Json -AsHashtable;$capture.check_id=$pair[0];$capture.capture_id=$pair[0];$capture.command_digest=& $module {param($Check) Get-CFJsonHash $Check} $check
        switch($pair[1]){'NOT_RUN'{$capture.quality.status='NOT_RUN';$capture.status='FAIL'};'STALE'{$capture.source_after='old'};'TIMEOUT'{$capture.status='TIMEOUT';$capture.timed_out=$true};'FAIL'{$capture.status='FAIL'};'ERROR'{$capture.quality.status='ERROR';$capture.quality.error='INVALID_MUTATION_REPORT'}}
        $captures+=,$capture
    }
    $f.contract.contract.checks=$checks;$f.read.evidence.checks=$captures;$f.profile.check_ids=@($checks.id)
    $summary=Summary $f
    Assert ($summary.status -ceq 'ERROR' -and $summary.observations.Count -eq 6) 'AllLatestObservationsSurviveAggregation'
    foreach($pair in @(@('error','FAIL'),@('fail','TIMEOUT'),@('timeout','STALE'),@('stale','NOT_RUN'),@('unrun','PASS'))){
        $f.profile.check_ids=@($f.profile.check_ids|Where-Object {$_ -cne $pair[0]})
        Assert ((Summary $f).status -ceq $pair[1]) ('AggregatePrecedenceAfterRemoving:'+ $pair[0])
    }
    $f=NewSummaryFixture;$old=$f.read.evidence.checks[0]|ConvertTo-Json -Depth 40|ConvertFrom-Json -AsHashtable;$old.status='FAIL';$old.capture_id='old';$f.read.evidence.checks=@($old,$f.read.evidence.checks[0]);$f.read.evidence.checks[1].stdout='unbounded raw output'
    $summary=Summary $f
    Assert ($summary.status -ceq 'PASS' -and $summary.observations.Count -eq 1 -and $summary.observations[0].capture_id -ceq 'capture-1' -and -not $summary.observations[0].Contains('stdout')) 'OnlyLatestBoundedObservationIncluded'

    $f=NewSummaryFixture;$f.contract.contract.checks[0].inputs=@('owned.txt');$capture=$f.read.evidence.checks[0];$capture.command_digest=& $module {param($Check) Get-CFJsonHash $Check} $f.contract.contract.checks[0];$capture.input_before=& $module {param($Root,$Check) Get-CFCheckInputDigest $Root $Check} $r $f.contract.contract.checks[0];$capture.input_after=$capture.input_before
    Assert ((Summary $f).status -ceq 'PASS') 'CurrentDeclaredInputsCanPass'
    File $r 'owned.txt' 'changed'
    $summary=Summary $f
    Assert ($summary.status -ceq 'STALE' -and 'CAPTURE_INPUT_MISMATCH' -cin $summary.observations[0].reasons) 'ChangedDeclaredInputIsStale'
    Write-Output "profile-status-v4: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
