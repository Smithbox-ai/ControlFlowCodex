param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Json)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
$report=[ordered]@{
    runtime=@{status='OK';detail="PowerShell $($PSVersionTable.PSVersion)"}
    package=@{status='PRESENT';detail='ControlFlow scripts are present at this location. This does not prove host installation or activation.'}
    repository=@{status='ERROR';detail='Repository not verified.'}
    storage=@{status='UNKNOWN';detail='Storage configuration not checked.'}
    hooks=@{status='UNKNOWN';detail='Host enablement, trust and callbacks cannot be determined here. Review docs/hooks.md and use manual fallback until verified.'}
}
try {
    $paths=Get-ControlFlowStoragePaths -RepoRoot $RepoRoot -TaskId 'doctor'
    $report.repository=@{status='OK';detail=$paths.binding.worktree_realpath}
    $report.storage=@{status='CONFIGURED_UNVERIFIED';detail="Validated path: $($paths.root). No write test was performed."}
} catch {
    $report.repository=@{status='UNVERIFIED';detail='Repository or storage configuration could not be verified.'}
    $report.storage=@{status='ERROR';detail=$_.Exception.Message}
}
if($Json){$report|ConvertTo-Json -Depth 10}
else {
    foreach($name in @('runtime','package','repository','storage','hooks')) {
        $item=$report[$name]; Write-Output ("{0}: {1} - {2}" -f $name.ToUpperInvariant(),$item.status,$item.detail)
    }
}
if($report.storage.status -eq 'ERROR'){exit 2}
exit 0
