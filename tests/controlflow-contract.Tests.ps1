Describe "ControlFlow contract runner" {
    It "runs the portable validation suite" {
        $runnerPath = Join-Path $PSScriptRoot "run-contract-tests.ps1"
        if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
            throw "Missing contract runner: $runnerPath"
        }

        $output = & $runnerPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Contract runner failed: $($output -join [Environment]::NewLine)"
        }
    }
}
