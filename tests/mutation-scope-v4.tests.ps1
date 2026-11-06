. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
    File $r 'src/guard.cs' "return amount <= limit;`n"
    File $r 'src/other.cs' 'unrelated'
    $reportPath=Join-Path $r 'report.json'
    function Report($Files,$ProjectRoot=$null) {
        $report=@{schemaVersion='1';files=$Files}
        if($null -ne $ProjectRoot){$report.projectRoot=$ProjectRoot}
        [IO.File]::WriteAllText($reportPath,($report|ConvertTo-Json -Depth 30))
    }
    function Entry([string]$Source,[string]$Status='Killed') {
        @{language='csharp';source=$Source;mutants=@(@{id='1';status=$Status})}
    }
    function BoundReport([string[]]$Scope=@('src/guard.cs'),[string]$WorkingDirectory='.') {
        Read-ControlFlowQualityReport -Path $reportPath -Format stryker-json -MinimumScore 80 -RepoRoot $r -Scope $Scope -WorkingDirectory $WorkingDirectory
    }
    # Replacing an in-scope source with an unrelated report must break this test.
    Report @{'src/other.cs'=(Entry 'unrelated')}
    $q=BoundReport
    Assert ($q.status -ceq 'ERROR' -and $q.error -like 'MUTATION_REPORT_OUTSIDE_SCOPE:*') 'UnrelatedReportCannotProveScopedSource'
    Report @{'src/guard.cs'=(Entry "return amount <= limit;`n")}
    $q=BoundReport
    Assert ($q.status -ceq 'PASS' -and $q.scope_verified -and $q.acceptance_status -ceq 'PASS') 'MatchingCurrentSourceAccepted'
    Report @{'src/guard.cs'=(Entry 'old source')}
    Assert ((BoundReport).error -like 'MUTATION_REPORT_SOURCE_MISMATCH:*') 'OldSourceRejected'
    Report @{'src/guard.cs'=(Entry "return amount <= limit;`n")}
    Assert ((BoundReport @('src/guard.cs','src/other.cs')).error -like 'MUTATION_REPORT_SCOPE_MISSING:*') 'OmittedScopedFileRejected'
    Report @{'../guard.cs'=(Entry 'outside')}
    Assert ((BoundReport).error -like 'MUTATION_REPORT_PATH_INVALID:*') 'ReportTraversalRejected'
    Report @{'src/guard.cs'=(Entry "return amount <= limit;`n")}
    Assert ((BoundReport @('src/*.cs')).error -like 'MUTATION_SCOPE_INVALID:*') 'ScopeGlobsRejected'
    Assert ((BoundReport @()).error -eq 'MUTATION_SCOPE_REQUIRED') 'EmptyScopeRejected'
    Report @{'guard.cs'=(Entry "return amount <= limit;`n")}
    Assert ((BoundReport @('src/guard.cs') 'src').status -ceq 'PASS') 'NestedCheckWorkingDirectorySupported'
    Report @{'guard.cs'=(Entry "return amount <= limit;`n")} 'src'
    Assert ((BoundReport).status -ceq 'PASS') 'ExplicitRelativeProjectRootSupported'
    Report @{'guard.cs'=(Entry "return amount <= limit;`n")} (Join-Path $r 'src')
    Assert ((BoundReport).status -ceq 'PASS') 'ExplicitContainedAbsoluteProjectRootSupported'
    Report @{'guard.cs'=(Entry "return amount <= limit;`n")} '..'
    Assert ((BoundReport).error -like 'MUTATION_PROJECT_ROOT_INVALID*') 'ProjectRootOutsideRepositoryRejected'
    Report @{'src/guard.cs'=(Entry "return amount <= limit;`n" 'Survived')}
    $q=Read-ControlFlowQualityReport -Path $reportPath -Format stryker-json
    Assert ($q.status -ceq 'PASS' -and $q.mutation_score -eq 0 -and $q.acceptance_status -ceq 'UNCONFIGURED' -and -not $q.scope_verified) 'OptionalStandaloneMeasurementDoesNotClaimAcceptanceOrScope'
    Assert ((BoundReport).status -ceq 'FAIL') 'ConfiguredThresholdRejectsAllSurvived'
    foreach($status in @('Pending','Ignored','CompileError','RuntimeError')) {
        Report @{'src/guard.cs'=(Entry "return amount <= limit;`n" $status)}
        Assert ((BoundReport).status -cne 'PASS') ('IncompleteOrInvalidMutantsNotAccepted:'+ $status)
    }
    Write-Output "mutation-scope-v4: $script:Count assertions passed"
} finally {RemoveFixture $r}
$global:LASTEXITCODE=0
