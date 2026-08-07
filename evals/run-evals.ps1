param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [string]$CasesDir,

    [string]$RunsDir,

    [string]$Variant = "unspecified",

    [string]$OutDir,

    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

$repoResolved = (Resolve-Path $RepoRoot).Path
$resolvedCasesDir = if ([string]::IsNullOrWhiteSpace($CasesDir)) { Join-Path $repoResolved "evals/cases" } else { (Resolve-Path $CasesDir).Path }
$resolvedOutDir = if ([string]::IsNullOrWhiteSpace($OutDir)) { Join-Path $repoResolved "evals/results" } else { $OutDir }

function Get-Median([double[]]$Values) {
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = $Values | Sort-Object
    $n = $sorted.Count
    if (($n % 2) -eq 1) { return [double]$sorted[[int](($n - 1) / 2)] }
    return ([double]$sorted[$n / 2 - 1] + [double]$sorted[$n / 2]) / 2.0
}

function Read-TextSafe([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-Content -LiteralPath $Path -Raw) }
    return $null
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Assert-CaseShape([object]$Case, [string]$Source) {
    foreach ($field in @("id", "task", "must_detect", "must_not_do", "max_artifact_bytes")) {
        if ($null -eq $Case.PSObject.Properties[$field]) {
            throw "Case '$Source' is missing required field '$field'"
        }
    }
    if (-not ($Case.must_detect -is [System.Array])) { throw "Case '$($Case.id)' must_detect must be an array" }
    if (-not ($Case.must_not_do -is [System.Array])) { throw "Case '$($Case.id)' must_not_do must be an array" }
    if (-not (($Case.max_artifact_bytes -is [int]) -or ($Case.max_artifact_bytes -is [long]))) {
        throw "Case '$($Case.id)' max_artifact_bytes must be a number"
    }
}

$caseFiles = @(Get-ChildItem -LiteralPath $resolvedCasesDir -Filter *.json -File | Sort-Object Name)
if ($caseFiles.Count -eq 0) { throw "No eval cases found in $resolvedCasesDir" }

if ($ValidateOnly) {
    foreach ($file in $caseFiles) {
        try { $case = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json }
        catch { throw "Case '$($file.Name)' is not valid JSON: $($_.Exception.Message)" }
        Assert-CaseShape $case $file.Name
    }
    Write-Output "VALID eval cases: $($caseFiles.Count)"
    return
}

if ([string]::IsNullOrWhiteSpace($RunsDir)) { throw "-RunsDir is required unless -ValidateOnly is specified" }
$runsResolved = (Resolve-Path $RunsDir).Path

$perCase = [System.Collections.ArrayList]::new()
$inputTokens = [System.Collections.ArrayList]::new()
$outputTokens = [System.Collections.ArrayList]::new()
$totalTokens = [System.Collections.ArrayList]::new()
$toolCalls = [System.Collections.ArrayList]::new()
$wallMs = [System.Collections.ArrayList]::new()
$artifactBytes = [System.Collections.ArrayList]::new()

foreach ($file in $caseFiles) {
    $case = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    Assert-CaseShape $case $file.Name

    $runDir = Join-Path $runsResolved $case.id
    $plan = Read-TextSafe (Join-Path $runDir "plan.md")
    $meta = Read-TextSafe (Join-Path $runDir "plan.meta.json")
    $verdict = Read-TextSafe (Join-Path $runDir "verify-verdict.md")
    $metrics = Read-JsonSafe (Join-Path $runDir "metrics.json")

    $haystack = "$plan`n$meta`n$verdict"
    $mustDetectFound = [System.Collections.ArrayList]::new()
    $mustDetectMissing = [System.Collections.ArrayList]::new()
    foreach ($needle in $case.must_detect) {
        if ($haystack -match [regex]::Escape($needle)) { [void]$mustDetectFound.Add($needle) }
        else { [void]$mustDetectMissing.Add($needle) }
    }

    $mustNotDoViolated = [System.Collections.ArrayList]::new()
    foreach ($forbidden in $case.must_not_do) {
        if ($haystack -match [regex]::Escape($forbidden)) { [void]$mustNotDoViolated.Add($forbidden) }
    }

    $bytes = 0
    foreach ($blob in @($plan, $meta, $verdict)) {
        if (-not [string]::IsNullOrEmpty($blob)) { $bytes += $blob.Length }
    }
    $bytesOk = ($bytes -le [int]$case.max_artifact_bytes)

    $metricsSuccess = $true
    if ($null -ne $metrics -and $null -ne $metrics.PSObject.Properties["success"]) {
        $metricsSuccess = [bool]$metrics.success
    }

    $inTok = $null; $outTok = $null; $tc = $null; $wm = $null
    if ($null -ne $metrics) {
        if ($metrics.input_tokens -is [int]) { $inTok = [int]$metrics.input_tokens; [void]$inputTokens.Add([double]$inTok) }
        if ($metrics.output_tokens -is [int]) { $outTok = [int]$metrics.output_tokens; [void]$outputTokens.Add([double]$outTok) }
        if ($null -ne $inTok -and $null -ne $outTok) { [void]$totalTokens.Add([double]($inTok + $outTok)) }
        if ($metrics.tool_calls -is [int]) { $tc = [int]$metrics.tool_calls; [void]$toolCalls.Add([double]$tc) }
        if ($metrics.wall_ms -is [int]) { $wm = [int]$metrics.wall_ms; [void]$wallMs.Add([double]$wm) }
    }
    [void]$artifactBytes.Add([double]$bytes)

    $success = ($mustDetectMissing.Count -eq 0) -and ($mustNotDoViolated.Count -eq 0) -and $bytesOk -and $metricsSuccess

    [void]$perCase.Add([ordered]@{
        id = $case.id
        success = $success
        must_detect_found = @($mustDetectFound)
        must_detect_missing = @($mustDetectMissing)
        must_not_do_violated = @($mustNotDoViolated)
        artifact_bytes = $bytes
        artifact_bytes_within_limit = $bytesOk
        input_tokens = $inTok
        output_tokens = $outTok
        tool_calls = $tc
        wall_ms = $wm
    })
}

$caseCount = $perCase.Count
$successCount = ($perCase | Where-Object { $_.success }).Count
$casesWithMustDetect = @($perCase | Where-Object { $_.must_detect_found.Count -gt 0 -or $_.must_detect_missing.Count -gt 0 })
$recallDenominator = $casesWithMustDetect.Count
$recallNumerator = ($casesWithMustDetect | Where-Object { $_.must_detect_missing.Count -eq 0 }).Count
$falsePositiveCount = ($perCase | Where-Object { $_.must_not_do_violated.Count -gt 0 }).Count

$medianIn = Get-Median -Values ([double[]]$inputTokens.ToArray())
$medianOut = Get-Median -Values ([double[]]$outputTokens.ToArray())
$medianTotal = Get-Median -Values ([double[]]$totalTokens.ToArray())
$medianTc = Get-Median -Values ([double[]]$toolCalls.ToArray())
$medianWm = Get-Median -Values ([double[]]$wallMs.ToArray())
$medianBytes = Get-Median -Values ([double[]]$artifactBytes.ToArray())

$summary = [ordered]@{
    variant = $Variant
    captured_at = (Get-Date).ToString("o")
    case_count = $caseCount
    success_count = $successCount
    success_rate = if ($caseCount -gt 0) { [math]::Round($successCount / $caseCount, 4) } else { 0 }
    critical_findings_recall = if ($recallDenominator -gt 0) { [math]::Round($recallNumerator / $recallDenominator, 4) } else { $null }
    false_positive_rate = if ($caseCount -gt 0) { [math]::Round($falsePositiveCount / $caseCount, 4) } else { 0 }
    median_input_tokens = $medianIn
    median_output_tokens = $medianOut
    median_total_tokens = $medianTotal
    median_tool_calls = $medianTc
    median_wall_ms = $medianWm
    median_artifact_bytes = $medianBytes
}

$result = [ordered]@{ summary = $summary; cases = @($perCase) }

New-Item -ItemType Directory -Path $resolvedOutDir -Force | Out-Null
$jsonPath = Join-Path $resolvedOutDir "$Variant.json"
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding utf8

$csvPath = Join-Path $resolvedOutDir "$Variant.csv"
$csv = "id,success,must_detect_missing,must_not_do_violated,artifact_bytes,input_tokens,output_tokens,tool_calls,wall_ms"
foreach ($c in $perCase) {
    $csv += "`n$($c.id),$($c.success),""$($c.must_detect_missing -join ';')"",""$($c.must_not_do_violated -join ';')"",$($c.artifact_bytes),$($c.input_tokens),$($c.output_tokens),$($c.tool_calls),$($c.wall_ms)"
}
Set-Content -LiteralPath $csvPath -Value $csv -Encoding utf8

Write-Output "Eval results written:"
Write-Output "  $jsonPath"
Write-Output "  $csvPath"
Write-Output ("  success rate: {0}/{1} = {2}" -f $successCount, $caseCount, $summary.success_rate)
