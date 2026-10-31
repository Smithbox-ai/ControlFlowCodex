$ErrorActionPreference='Stop'
. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
    $doctor=Join-Path $script:CoreRoot 'scripts/doctor.ps1'
    $explain=Join-Path $script:CoreRoot 'scripts/explain-gate.ps1'
    $before=Git $r @('status','--porcelain=v1','--untracked-files=all')
    $paths=Get-ControlFlowStoragePaths $r 'doctor-test'
    $report=& $doctor -RepoRoot $r -Json | ConvertFrom-Json -AsHashtable
    Assert ($report.repository.status -eq 'OK') 'doctor identifies the repository'
    Assert ($report.storage.status -eq 'CONFIGURED_UNVERIFIED') 'doctor does not claim to have tested storage writes'
    Assert ($report.hooks.status -eq 'UNKNOWN') 'doctor does not infer hook trust or callbacks'
    Assert (-not [IO.Directory]::Exists($paths.root)) 'doctor does not create state'
    Assert ((Git $r @('status','--porcelain=v1','--untracked-files=all')) -ceq $before) 'doctor leaves repository unchanged'

    $p=Contract $r 'SMALL' 'none' 'Write-Output ok' 'diagnostics'
    $run=Start-ControlFlowRun $r $p 'diagnostics'
    $failure=(& $explain -RepoRoot $r -RunPath $run.run_path | Out-String)
    Assert ($LASTEXITCODE -eq 1 -and $failure -match 'CHECK_MISSING:check-1' -and $failure -match 'run') 'missing check has a reason and an action'
    Capture-ControlFlowCheck $r $run.run_path 'check-1' | Out-Null
    Update-ControlFlowRun $r $run.run_path @{type='coverage';criterion_id='C1';check_ids=@('check-1')} | Out-Null
    $success=(& $explain -RepoRoot $r -RunPath $run.run_path | Out-String)
    Assert ($LASTEXITCODE -eq 0 -and $success -match 'PASS') 'pass is explained with the gate exit code'
    $invalid=(& $explain -RepoRoot $r -RunPath (Join-Path $r 'bad') | Out-String)
    Assert ($LASTEXITCODE -eq 2 -and $invalid -match 'UNVERIFIABLE') 'errors are not treated as success'
    Write-Output "VALID diagnostics ($script:Count assertions)"
} finally {RemoveFixture $r}
$global:LASTEXITCODE=0
