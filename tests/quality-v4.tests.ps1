. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
$p=Join-Path $r 'report.xml'
File $r 'report.xml' '<testsuite tests="0" failures="0" errors="0" skipped="0"/>'
$q=Read-ControlFlowQualityReport $p junit
Assert ($q.status -ceq 'FAIL' -and $q.executed_tests -eq 0) 'ZeroTestsDoNotSatisfyScenario'
Throws {Read-ControlFlowQualityReport $p junit 0} 'ReaderCannotDisableNonzeroMinimum'
File $r 'report.xml' '<testsuite tests="2" failures="0" errors="0" skipped="0"><testcase name="one"/></testsuite>'
Assert ((Read-ControlFlowQualityReport $p junit).status -ceq 'ERROR') 'IncompleteRunNotPass'
File $r 'report.xml' '<testsuite tests="1" failures="0" errors="0" skipped="0"><testcase name="one"/></testsuite>'
Assert ((Read-ControlFlowQualityReport $p junit).status -ceq 'PASS') 'RecognizedNonzeroJUnit'
File $r 'report.xml' '<testsuite tests="1" failures="1" errors="0" skipped="0"><testcase name="one"><failure/></testcase></testsuite>'
Assert ((Read-ControlFlowQualityReport $p junit).status -ceq 'FAIL') 'ReportFailureOverridesExitZero'
File $r 'report.xml' '<test-run total="1" passed="1" failed="0" skipped="0" inconclusive="0" asserts="0" result="Passed"><test-case result="Passed" asserts="0"/></test-run>'
Assert ((Read-ControlFlowQualityReport $p nunit3).status -ceq 'FAIL') 'ZeroAssertionsNUnitNotPass'
File $r 'report.xml' '<!DOCTYPE x [<!ENTITY e SYSTEM "file:///forbidden">]><testsuite tests="1"><testcase name="&e;"/></testsuite>'
Assert ((Read-ControlFlowQualityReport $p junit).status -ceq 'ERROR') 'ReportExternalEntitiesRejected'
File $r 'report.json' '{"schemaVersion":"1","thresholds":{"high":80,"low":60},"files":{"a.ps1":{"language":"powershell","source":"x","mutants":[{"id":"1","status":"Pending"}]}}}'
Assert ((Read-ControlFlowQualityReport (Join-Path $r 'report.json') stryker-json).status -cne 'PASS') 'IncompleteMutationNotPass'
Assert ((Read-ControlFlowQualityReport $p unknown).status -ceq 'UNSUPPORTED') 'UnknownReportNotInferredFromStdout'
Write-Output "quality-v4: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
