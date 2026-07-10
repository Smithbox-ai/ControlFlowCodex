$repoRoot = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $PSScriptRoot "run-contract-tests.ps1"

Describe "ControlFlow contract runner" {
    It "runs the portable validation suite" {
        if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
            throw "Missing contract runner: $runnerPath"
        }

        $output = & $runnerPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Contract runner failed: $($output -join [Environment]::NewLine)"
        }
    }
}
