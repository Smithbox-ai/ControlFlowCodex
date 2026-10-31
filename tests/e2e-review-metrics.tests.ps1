$ErrorActionPreference='Stop'
. "$PSScriptRoot/../evals/e2e-lib.ps1"
$empty=New-E2EReviewMetrics
if($null -ne $empty.active_human_review_ms -or $empty.source -cne 'missing'){throw 'MissingMeasurementsMustNotBecomeZero'}
$manual=New-E2EReviewMetrics @{active_human_review_ms=1200;decision_wait_ms=5000;review_packet_bytes=300} manual
if($manual.source -cne 'manual' -or $manual.active_human_review_ms -ne 1200 -or $null -ne $manual.rework_ms){throw 'ManualMeasurementsRemainExplicit'}
$metrics=Measure-E2EReviewMetrics @($empty,$manual)
if($metrics.fields.active_human_review_ms.measured_count -ne 1 -or $metrics.fields.active_human_review_ms.median -ne 1200 -or $metrics.fields.rework_ms.measured_count -ne 0 -or $null -ne $metrics.fields.rework_ms.median){throw 'MissingMeasurementsNotImputed'}
$thrown=$false;try{New-E2EReviewMetrics @{rework_ms=-1} manual|Out-Null}catch{$thrown=$true}
if(-not $thrown){throw 'InvalidNegativeMeasurementRejected'}
Write-Output 'VALID review metrics: missing/manual separation, sample counts and no zero imputation'
$global:LASTEXITCODE=0
