param(
    [switch]$UsePester
)

$ErrorActionPreference = "Stop"

$testRoot = $PSScriptRoot

function Invoke-ContractScript([string]$Name) {
    $path = Join-Path $testRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing contract test: $path"
    }

    $suiteClock = if ($env:CONTROLFLOW_TEST_PROGRESS -ceq '1') { [Diagnostics.Stopwatch]::StartNew() } else { $null }
    if ($suiteClock) { [Console]::Out.WriteLine(("SUITE_START {0} {1:o}" -f $Name,[datetime]::UtcNow)) }
    $global:LASTEXITCODE = 0
    $output = @(& $path 2>&1)
    foreach ($line in $output) {
        Write-Output $line
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Contract test failed: $Name"
    }
    if ($suiteClock) { [Console]::Out.WriteLine(("SUITE_PASS {0} elapsed_ms={1} {2:o}" -f $Name,$suiteClock.ElapsedMilliseconds,[datetime]::UtcNow)) }
}

Invoke-ContractScript "controlflow-skill-contract.tests.ps1"
Invoke-ContractScript "template-contract.tests.ps1"
Invoke-ContractScript "installer-smoke.tests.ps1"
Invoke-ContractScript "installer-lifecycle.tests.ps1"
Invoke-ContractScript "git-evidence.tests.ps1"
Invoke-ContractScript "storage.tests.ps1"
Invoke-ContractScript "legacy-contract-compat.tests.ps1"
Invoke-ContractScript "contract-v4.tests.ps1"
Invoke-ContractScript "v4-release.tests.ps1"
Invoke-ContractScript "phase-gates.tests.ps1"
Invoke-ContractScript "decisions-v4.tests.ps1"
Invoke-ContractScript "v4-integrity.tests.ps1"
Invoke-ContractScript "promotion-v4.tests.ps1"
Invoke-ContractScript "stop-boundary-v4.tests.ps1"
Invoke-ContractScript "quality-v4.tests.ps1"
Invoke-ContractScript "quality-profiles-v4.tests.ps1"
Invoke-ContractScript "workflow-v4.tests.ps1"
Invoke-ContractScript "run-evidence.tests.ps1"
Invoke-ContractScript "process-timeout.tests.ps1"
Invoke-ContractScript "interrupt-evidence.tests.ps1"
Invoke-ContractScript "gates.tests.ps1"
Invoke-ContractScript "hook-policy.tests.ps1"
Invoke-ContractScript "hooks.tests.ps1"
Invoke-ContractScript "hooks-v4.tests.ps1"
Invoke-ContractScript "entry-skill.tests.ps1"
Invoke-ContractScript "package.tests.ps1"
Invoke-ContractScript "diagnostics.tests.ps1"
Invoke-ContractScript "release-workflow.tests.ps1"
Invoke-ContractScript "release-tag.tests.ps1"
Invoke-ContractScript "release-availability.tests.ps1"
Invoke-ContractScript "release-snapshot.tests.ps1"
Invoke-ContractScript "e2e-evals.tests.ps1"
Invoke-ContractScript "e2e-review-metrics.tests.ps1"
Invoke-ContractScript "e2e-v4-adapter.tests.ps1"
Invoke-ContractScript "e2e-v4-cli.tests.ps1"
Invoke-ContractScript "e2e-release-grading.tests.ps1"


if ($UsePester) {
    $invokePester = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
    if ($null -eq $invokePester) {
        throw "Pester is required when -UsePester is specified"
    }

    $pesterTestPath = Join-Path $testRoot "controlflow-contract.Tests.ps1"
    $pesterResult = Invoke-Pester -Path $pesterTestPath -PassThru

    # Be robust across Pester versions: Pester 5 exposes .Result ("Passed"/"Failed"),
    # while Pester 3 exposes .FailedCount. Treat either as the failure signal.
    $pesterFailed = $false
    if ($null -ne $pesterResult.PSObject.Properties["Result"]) {
        $pesterFailed = ($pesterResult.Result -ne "Passed")
    } elseif ($null -ne $pesterResult.PSObject.Properties["FailedCount"]) {
        $pesterFailed = ($pesterResult.FailedCount -ne 0)
    }

    if ($pesterFailed) {
        throw "Pester contract tests failed"
    }
}

Write-Output "VALID ControlFlow contract suite"


