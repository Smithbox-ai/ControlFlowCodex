[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$NativeDirectory,
    [Parameter(Mandatory)][string]$V3Directory,
    [string]$ReviewsDirectory='',
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'e2e-lib.ps1')
if(Test-Path -LiteralPath $OutputPath){throw 'Comparison output must be new; evidence is immutable'}
$catalog=@(Get-E2EReleaseDiagnosticCases)
$all=[Collections.Generic.List[object]]::new();$grades=[Collections.Generic.List[object]]::new();$counts=@{};$trials=$null
foreach($arm in @('native','v3')){
    $directory=if($arm -eq 'native'){$NativeDirectory}else{$V3Directory}
    $manifest=Get-Content -LiteralPath (Join-Path $directory 'manifest.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    if($manifest.suite -cne 'Diagnostics' -or $manifest.variant -cne $arm -or $manifest.trials -le 0){throw 'Expected a declared diagnostic cohort with matching variant'}
    foreach($field in @('model','effort','host','cli_version','project_trust','sandbox','approval_policy','approvals_reviewer')){if($manifest[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($manifest[$field])){throw "Diagnostic manifest missing $field provenance"}}
    if(-not $manifest.ContainsKey('windows_sandbox') -or $manifest.settings -isnot [array]){throw 'Diagnostic manifest missing platform/settings provenance'}
    foreach($field in @('max_tokens','max_tool_calls','max_wall_seconds')){if(($manifest[$field] -isnot [int] -and $manifest[$field] -isnot [long]) -or $manifest[$field] -le 0){throw 'Diagnostic manifest missing positive native trial budgets'}}
    if($null -ne $trials -and $trials -ne $manifest.trials){throw 'Diagnostic arms must request the same trial count'}
    $trials=$manifest.trials
    if(@($manifest.case_ids).Count -ne $catalog.Count -or @($catalog|Where-Object {$_.id -cnotin $manifest.case_ids}).Count){throw 'Diagnostic coverage requires every predeclared case'}
    $summary=Get-Content -LiteralPath (Join-Path $directory 'summary.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    $seen=@{};$collected=0;$reviewed=0;$identified=0;$observed=0
    foreach($row in @($summary.results)){
        $case=@($catalog|Where-Object id -CEQ $row.case_id)
        if($case.Count -ne 1 -or $row.variant -cne $arm -or $row.trial -lt 1 -or $row.trial -gt $trials){throw 'Unexpected diagnostic result identity'}
        $key="$($row.case_id):$($row.trial)";if($seen.ContainsKey($key)){throw 'Duplicate diagnostic trial'};$seen[$key]=$true
        $opaque=(Get-E2EHash $row.case_id).Substring(0,16)
        $trialDirectory=Join-Path $directory "trials/fixture-$opaque/$($row.trial)"
        $resultPath=Join-Path $trialDirectory 'result.json'
        $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json -AsHashtable -Depth 100
        if($result.case_id -cne $row.case_id -or $result.variant -cne $arm -or $result.trial -ne $row.trial){throw 'Summary and native result identity mismatch'}
        foreach($field in @('model','effort','host','cli_version','project_trust','sandbox','windows_sandbox','approval_policy','approvals_reviewer')){
            if(-not $result.provenance.ContainsKey($field) -or $result.provenance[$field] -cne $manifest[$field]){throw "Actual diagnostic result differs from declared $field provenance"}
        }
        if($result.provenance.settings -isnot [array] -or ($result.provenance.settings -join "`n") -cne ($manifest.settings -join "`n")){throw 'Actual diagnostic settings differ from declared cohort'}
        foreach($binding in @(@('tokens','max_tokens'),@('tools','max_tool_calls'),@('wall_seconds','max_wall_seconds'))){if($result.provenance.budget[$binding[0]] -ne $manifest[$binding[1]]){throw 'Actual diagnostic budgets differ from declared cohort'}}
        if($result.risk_diagnostics.criteria_sha256 -cne (Get-E2EDiagnosticCriteriaHash -Case $case[0])){throw 'Persisted diagnostic criteria differ from current predeclared catalogue'}
        $all.Add($result)
        $reviewPath=if($ReviewsDirectory){Join-Path $ReviewsDirectory "$arm/$($case[0].id)/$($row.trial).json"}else{''}
        if($reviewPath -and -not (Test-Path -LiteralPath $reviewPath)){$reviewPath=''}
        $grade=Test-E2ECriticalRiskDiagnostics -Case $case[0] -Fixture @{root=(Join-Path $trialDirectory 'repo')} -ReviewPath $reviewPath -ResultPath $resultPath
        $grade.variant=$arm;$grade.trial=$row.trial;$grades.Add($grade)
        $observed+=$grade.criterion_count
        if($grade.collection_complete){$collected+=$grade.criterion_count}
        if($grade.semantic_review_complete -and (Test-E2EResultEnvelope $result)){$reviewed+=$grade.criterion_count;$identified+=$grade.identified_count}
    }
    $expected=($catalog|ForEach-Object {$_.diagnostic_criteria.Count}|Measure-Object -Sum).Sum*$trials
    $complete=$reviewed -eq $expected -and $observed -eq $expected
    $counts[$arm]=@{expected_criteria=$expected;observed_criteria=$observed;collected_criteria=$collected;reviewed_criteria=$reviewed;identified_criteria=$identified;unobserved_criteria=$expected-$observed;collection_coverage=$collected/$expected;semantic_coverage=$reviewed/$expected;recall=if($complete){$identified/$expected}else{$null};observed_subset_recall=if($reviewed){$identified/$reviewed}else{$null};complete=$complete}
}
$pairs=Measure-E2EPairs -Results $all.ToArray()
$complete=$counts.native.complete -and $counts.v3.complete -and $pairs.unpaired_records -eq 0 -and $pairs.incomplete_metrics_pairs -eq 0
$comparison=@{schema_version='1.0.0';protocol='release-risk-diagnostics-1.0.0';arms=$counts;diagnostic_metrics_complete=$complete;critical_risk_recall_delta=if($complete){$counts.v3.recall-$counts.native.recall}else{$null};criteria_source='predeclared HIGH-risk diagnostic cases';semantic_judge='independent human annotations bound to source, diagnostic artifact and immutable result hashes; no model or regex judge';pairing=$pairs;observations=$grades.ToArray();production_ready=$false}
Write-E2EText $OutputPath ($comparison|ConvertTo-Json -Depth 40)
Write-Output "Diagnostic coverage/recall comparison: $OutputPath"
