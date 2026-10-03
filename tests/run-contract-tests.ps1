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

    $global:LASTEXITCODE = 0
    $output = @(& $path 2>&1)
    foreach ($line in $output) {
        Write-Output $line
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Contract test failed: $Name"
    }
}

Invoke-ContractScript "controlflow-skill-contract.tests.ps1"
Invoke-ContractScript "template-contract.tests.ps1"
Invoke-ContractScript "installer-smoke.tests.ps1"
Invoke-ContractScript "git-evidence.tests.ps1"
Invoke-ContractScript "contract-v3.tests.ps1"
Invoke-ContractScript "run-evidence.tests.ps1"
Invoke-ContractScript "interrupt-evidence.tests.ps1"
Invoke-ContractScript "gates.tests.ps1"
Invoke-ContractScript "hook-policy.tests.ps1"
Invoke-ContractScript "hooks.tests.ps1"
Invoke-ContractScript "entry-skill.tests.ps1"
Invoke-ContractScript "package.tests.ps1"
Invoke-ContractScript "e2e-evals.tests.ps1"
Invoke-ContractScript "e2e-release-grading.tests.ps1"
Invoke-ContractScript "e2e-cache.tests.ps1"

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


