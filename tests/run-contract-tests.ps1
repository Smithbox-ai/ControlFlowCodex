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
Invoke-ContractScript "validate-plan.tests.ps1"
Invoke-ContractScript "detect-drift.tests.ps1"

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

