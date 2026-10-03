param([switch]$DiagnosticOnly)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'evals/e2e-lib.ps1')
$passed=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "ASSERT: $Message"};$script:passed++}
Assert ($null -ne (Get-Command Test-E2EReleaseCli -ErrorAction SilentlyContinue)) 'release CLI outcome grading exists (feature missing)'
Assert ($null -ne (Get-Command Test-E2ECriticalRiskDiagnostics -ErrorAction SilentlyContinue)) 'independent release risk diagnostic grading exists (feature missing)'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('cf-release-grading-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch)|Out-Null
try {
    $cases=@(Get-E2ECases -RepoRoot $repo -Suite Release)
    if(-not $DiagnosticOnly){
    foreach($case in @($cases|Where-Object tier -eq 'LARGE')){
        $fixture=New-E2EFixture -Case $case -Directory (Join-Path $scratch $case.id)
        Set-E2EReferenceOutcome -Case $case -Fixture $fixture
        $result=Test-E2EReleaseCli -Case $case -Fixture $fixture
        Assert ($result.applicable -and $result.pass -and $result.collection_complete -and $result.completed_checks -ge 1) "real file-to-file reference CLI: $($case.id) $($result.failures -join ',')"
        $cli=Join-Path $fixture.root 'cli.ps1'
        Write-E2EText $cli 'param([string]$InputFile,[string]$OutputFile); "null" | Set-Content ($OutputFile+".wrong")'
        Assert (-not (Test-E2EReleaseCli -Case $case -Fixture $fixture).collection_complete) "wrong output path cannot pass CLI: $($case.id)"
        Write-E2EText $cli 'param([string]$InputFile,[string]$OutputFile); "null" | Set-Content $OutputFile'
        $wrong=Test-E2EReleaseCli -Case $case -Fixture $fixture
        Assert ($wrong.collection_complete -and -not $wrong.pass) "wrong CLI serialization cannot pass: $($case.id)"
        Remove-Item -LiteralPath $cli
        Assert (-not (Test-E2EReleaseCli -Case $case -Fixture $fixture).collection_complete) "missing CLI cannot pass: $($case.id)"
        Write-E2EText $cli $case.files['cli.ps1']
        $doc=Join-Path $fixture.root 'docs/interface.md'
        Write-E2EText $doc 'Document the file-to-file command before release.'
        Assert (-not (Test-E2EOutcome -Case $case -Fixture $fixture).pass) "baseline placeholder cannot satisfy CLI documentation delivery: $($case.id)"
        Remove-Item -LiteralPath $doc
        Assert (-not (Test-E2EOutcome -Case $case -Fixture $fixture).pass) "missing CLI documentation cannot satisfy delivery: $($case.id)"
    }
    $case=@($cases|Where-Object id -eq 'order-pipeline')[0]
    $fixture=New-E2EFixture -Case $case -Directory (Join-Path $scratch 'broken-cli')
    Set-E2EReferenceOutcome -Case $case -Fixture $fixture
    Write-E2EText (Join-Path $fixture.root 'cli.ps1') 'param([string]$InputFile,[string]$OutputFile); exit 0'
    $result=Test-E2EReleaseCli -Case $case -Fixture $fixture
    Assert (-not $result.pass -and -not $result.collection_complete) 'zero exit without output cannot certify CLI delivery'
    Assert (-not (Test-E2EOutcome -Case $case -Fixture $fixture).pass) 'function-only repair with broken CLI cannot pass full outcome'
    Write-E2EText (Join-Path $fixture.root 'cli.ps1') 'param([string]$InputFile,[string]$OutputFile); "[]" | Set-Content $OutputFile'
    $result=Test-E2EReleaseCli -Case $case -Fixture $fixture
    Assert ($result.collection_complete -and -not $result.pass) 'collected wrong JSON is failed behavior rather than missing observation'
    Write-E2EText (Join-Path $fixture.root 'cli.ps1') 'param([string]$InputFile,[string]$OutputFile); "invalid JSON" | Set-Content $OutputFile'
    Assert (-not (Test-E2EReleaseCli -Case $case -Fixture $fixture).collection_complete) 'invalid output JSON cannot count as complete collection'
    }
    $before=Get-E2EHash (($cases|ForEach-Object {@{id=$_.id;task=$_.task;files=$_.files;answers=$_.answers}})|ConvertTo-Json -Depth 30 -Compress)
    $diagnosticCases=@(Get-E2EReleaseDiagnosticCases)
    Assert ($diagnosticCases.Count -ge 3 -and @($diagnosticCases|Where-Object {$_.diagnostic_criteria.Count -eq 0}).Count -eq 0) 'release diagnostic tasks declare risk criteria before a trial'
    $risk=$diagnosticCases[0]
    $rf=New-E2EFixture -Case $risk -Directory (Join-Path $scratch 'risk')
    $missing=Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf
    Assert (-not $missing.collection_complete -and $null -eq $missing.recall -and $missing.missing_collection_count -eq 1) 'absent diagnostic artifact is not successful recall'
    Assert (-not (Test-E2EOutcome -Case $risk -Fixture $rf).pass) 'unchanged source without requested diagnostic artifact is not delivery success'
    Write-E2EText (Join-Path $rf.root 'diagnostics.json') '{"schema_version":"1.0.0","findings":[]}'
    $empty=Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf
    Assert ($empty.collection_complete -and $empty.finding_count -eq 0 -and -not $empty.semantic_review_complete -and $null -eq $empty.recall) 'observed empty diagnosis still requires independent annotations before complete recall'
    $criterion=$risk.diagnostic_criteria[0]
    $report=@{schema_version='1.0.0';findings=@(@{category=$criterion.category;file=$criterion.file;start_line=$criterion.start_line;end_line=$criterion.end_line;mechanism='The operation permits the forbidden input.';consequence='The protected operation can occur without its required constraint.';mitigation='Enforce the documented constraint before performing the operation.'})}
    $artifact=Join-Path $rf.root 'diagnostics.json'
    Write-E2EText $artifact ($report|ConvertTo-Json -Depth 10)
    $unreviewed=Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf
    Assert ($unreviewed.collection_complete -and -not $unreviewed.semantic_review_complete -and $null -eq $unreviewed.recall) 'plausible category and location cannot self-certify semantic diagnosis'
    $criteriaHash=Get-E2EDiagnosticCriteriaHash -Case $risk
    $resultPath=Join-Path $scratch 'immutable-result.json';Write-E2EText $resultPath (@{case_id=$risk.id;variant='native';trial=1;status='success';risk_diagnostics=$unreviewed}|ConvertTo-Json -Depth 20)
    $review=@{schema_version='1.0.0';case_id=$risk.id;criteria_sha256=$criteriaHash;artifact_sha256=(Get-FileHash $artifact).Hash.ToLowerInvariant();result_sha256=(Get-FileHash $resultPath).Hash.ToLowerInvariant();sources=@{};reviewer='independent-human';reviewer_kind='human';reviewed_at='2026-10-03T00:00:00Z';criteria=@(@{id=$criterion.id;identified=$true;finding_index=0;rationale='The finding states the concrete vulnerable mechanism, its consequence and a relevant mitigation.'})}
    $review.sources[$criterion.file]=$criterion.source_sha256
    $reviewPath=Join-Path $scratch 'review.json';Write-E2EText $reviewPath ($review|ConvertTo-Json -Depth 10)
    $reviewed=Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf -ReviewPath $reviewPath -ResultPath $resultPath
    Assert ($reviewed.semantic_review_complete -and $reviewed.recall -eq 1 -and $reviewed.identified_count -eq 1 -and $reviewed.coverage -eq 1) 'hash-bound independent criterion review certifies bounded diagnostic recall'
    $savedResultText=[IO.File]::ReadAllText($resultPath);Write-E2EText $resultPath ($savedResultText+"`n")
    Assert (-not (Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf -ReviewPath $reviewPath -ResultPath $resultPath).semantic_review_complete) 'changed immutable trial result invalidates independent review'
    Write-E2EText $resultPath $savedResultText
    $originalDiagnosis=$criterion.expected_diagnosis;$criterion.expected_diagnosis='Different interpretation after collection'
    Assert (-not (Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf -ReviewPath $reviewPath -ResultPath $resultPath).semantic_review_complete) 'criterion semantics cannot change underneath the same reviewed source and diagnosis'
    $criterion.expected_diagnosis=$originalDiagnosis
    $capturedArtifact=[IO.File]::ReadAllText($artifact)
    $report.findings[0].mechanism='Changed after review';Write-E2EText $artifact ($report|ConvertTo-Json -Depth 10)
    Assert (-not (Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf -ReviewPath $reviewPath -ResultPath $resultPath).semantic_review_complete) 'stale annotation cannot certify changed diagnosis'
    $review.artifact_sha256=(Get-FileHash $artifact).Hash.ToLowerInvariant();Write-E2EText $reviewPath ($review|ConvertTo-Json -Depth 10)
    $replacement=Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf -ReviewPath $reviewPath -ResultPath $resultPath
    Assert (-not $replacement.collection_complete -and -not $replacement.semantic_review_complete -and $null -eq $replacement.recall) 'new human annotation cannot certify a post-run replacement of captured diagnosis'
    Write-E2EText $artifact $capturedArtifact
    $review.artifact_sha256=(Get-FileHash $artifact).Hash.ToLowerInvariant();$review.criteria[0].finding_index=5;Write-E2EText $reviewPath ($review|ConvertTo-Json -Depth 10)
    Assert (-not (Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf -ReviewPath $reviewPath -ResultPath $resultPath).semantic_review_complete) 'annotation must point to an observed finding'
    $review.criteria[0].finding_index=0;Write-E2EText $reviewPath ($review|ConvertTo-Json -Depth 10)
    Write-E2EText (Join-Path $rf.root $criterion.file) '# changed vulnerable source'
    Assert (-not (Test-E2ECriticalRiskDiagnostics -Case $risk -Fixture $rf -ReviewPath $reviewPath -ResultPath $resultPath).collection_complete) 'read-only diagnostic task must preserve its actual source evidence'
    $validation=& (Join-Path $repo 'evals/run-risk-diagnostics.ps1') -RepoRoot $repo -ValidateOnly -WindowsSandbox unelevated
    Assert (($validation -join "`n") -match 'VALID executable Diagnostics cases: 3') 'diagnostic CLI reuses unpaid validation and forwards Windows sandbox setting'
    $cohorts=@{};$reviewRoot=Join-Path $scratch 'annotations'
    foreach($arm in @('native','v3')){
        $directory=Join-Path $scratch ('cohort-'+$arm);$cohorts[$arm]=$directory
        $rows=[Collections.Generic.List[object]]::new()
        Write-E2EText (Join-Path $directory 'manifest.json') (@{suite='Diagnostics';variant=$arm;trials=1;case_ids=@($diagnosticCases.id);model='test-model';effort='high';host='test-host';cli_version='0.160.0';project_trust='untrusted';sandbox='workspace-write';windows_sandbox='unelevated';approval_policy='never';approvals_reviewer='user';settings=@();max_tokens=1000;max_tool_calls=20;max_wall_seconds=60}|ConvertTo-Json -Depth 10)
        foreach($dc in $diagnosticCases){
            $td=Join-Path $directory ('trials/fixture-'+(Get-E2EHash $dc.id).Substring(0,16)+'/1')
            $df=New-E2EFixture -Case $dc -Directory (Join-Path $td 'repo')
            $dcrit=$dc.diagnostic_criteria[0]
            $finding=@{category=$dcrit.category;file=$dcrit.file;start_line=$dcrit.start_line;end_line=$dcrit.end_line;mechanism='Specific vulnerable operation';consequence='Violation of documented requirement';mitigation='Enforce the requirement before performing the operation'}
            Write-E2EText (Join-Path $df.root 'diagnostics.json') (@{schema_version='1.0.0';findings=@($finding)}|ConvertTo-Json -Depth 10)
            $r=@{case_id=$dc.id;tier=$dc.tier;variant=$arm;trial=1;status='success';false_completion=$false;outcome=(Test-E2EOutcome -Case $dc -Fixture $df);risk_diagnostics=(Test-E2ECriticalRiskDiagnostics -Case $dc -Fixture $df);usage=@{complete=$true;input_tokens=90;output_tokens=10;cached_input_tokens=0;total_tokens=100;tool_calls=0};provenance=@{model='test-model';effort='high';host='test-host';fixture_hash=$df.fixture_hash;settings=@();project_trust='untrusted';sandbox='workspace-write';windows_sandbox='unelevated';approval_policy='never';approvals_reviewer='user';cli_version='0.160.0';budget=@{tokens=1000;tools=20;wall_seconds=60}}}
            $rp=Join-Path $td 'result.json';Write-E2EText $rp ($r|ConvertTo-Json -Depth 40);$rows.Add($r)
            $annotation=@{schema_version='1.0.0';case_id=$dc.id;criteria_sha256=$r.risk_diagnostics.criteria_sha256;artifact_sha256=$r.risk_diagnostics.artifact_sha256;result_sha256=(Get-FileHash $rp).Hash.ToLowerInvariant();sources=$r.risk_diagnostics.source_hashes;reviewer='test-independent-reviewer';reviewer_kind='human';reviewed_at='2026-10-03T00:00:00Z';criteria=@(@{id=$dcrit.id;identified=$arm -eq 'v3';finding_index=0;rationale='Test annotation of whether the specific expected mechanism was diagnosed.'})}
            Write-E2EText (Join-Path $reviewRoot "$arm/$($dc.id)/1.json") ($annotation|ConvertTo-Json -Depth 20)
        }
        Write-E2EText (Join-Path $directory 'summary.json') (@{results=$rows.ToArray()}|ConvertTo-Json -Depth 40)
    }
    $unmeasuredPath=Join-Path $scratch 'unmeasured.json'
    & (Join-Path $repo 'evals/compare-risk-diagnostics.ps1') -NativeDirectory $cohorts.native -V3Directory $cohorts.v3 -OutputPath $unmeasuredPath|Out-Null
    $unmeasured=Get-Content $unmeasuredPath -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    Assert (-not $unmeasured.diagnostic_metrics_complete -and $null -eq $unmeasured.arms.native.recall -and $unmeasured.arms.native.collection_coverage -eq 1 -and $unmeasured.arms.native.semantic_coverage -eq 0) 'collected diagnoses without annotations cannot produce semantic recall'
    $measuredPath=Join-Path $scratch 'measured.json'
    & (Join-Path $repo 'evals/compare-risk-diagnostics.ps1') -NativeDirectory $cohorts.native -V3Directory $cohorts.v3 -ReviewsDirectory $reviewRoot -OutputPath $measuredPath|Out-Null
    $measured=Get-Content $measuredPath -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    Assert ($measured.diagnostic_metrics_complete -and $measured.arms.native.recall -eq 0 -and $measured.arms.v3.recall -eq 1 -and $measured.critical_risk_recall_delta -eq 1 -and -not $measured.production_ready) 'offline comparison measures bounded reviewed recall separately from production readiness'
    $firstId=$diagnosticCases[0].id
    $capturedPath=Join-Path $cohorts.native ('trials/fixture-'+(Get-E2EHash $firstId).Substring(0,16)+'/1/repo/diagnostics.json')
    $originalCaptured=[IO.File]::ReadAllText($capturedPath);Write-E2EText $capturedPath ($originalCaptured+"`n")
    $alteredPath=Join-Path $scratch 'altered-unreviewed.json'
    & (Join-Path $repo 'evals/compare-risk-diagnostics.ps1') -NativeDirectory $cohorts.native -V3Directory $cohorts.v3 -OutputPath $alteredPath|Out-Null
    $altered=Get-Content $alteredPath -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    Assert ($altered.arms.native.collected_criteria -eq 2 -and $altered.arms.native.collection_coverage -lt 1 -and -not $altered.diagnostic_metrics_complete) 'post-run artifact replacement is excluded from collection coverage even without reviews'
    Write-E2EText $capturedPath $originalCaptured
    $partialSummary=Get-Content (Join-Path $cohorts.native 'summary.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    $partialSummary.results=@($partialSummary.results|Select-Object -First 2)
    Write-E2EText (Join-Path $cohorts.native 'summary.json') ($partialSummary|ConvertTo-Json -Depth 40)
    $partialPath=Join-Path $scratch 'partial.json'
    & (Join-Path $repo 'evals/compare-risk-diagnostics.ps1') -NativeDirectory $cohorts.native -V3Directory $cohorts.v3 -ReviewsDirectory $reviewRoot -OutputPath $partialPath|Out-Null
    $partial=Get-Content $partialPath -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    Assert (-not $partial.diagnostic_metrics_complete -and $partial.arms.native.unobserved_criteria -eq 1 -and $partial.arms.native.semantic_coverage -lt 1 -and $null -eq $partial.arms.native.recall) 'unrun diagnosis remains in requested denominator and prevents complete recall'
    $manifestPath=Join-Path $cohorts.native 'manifest.json';$savedManifest=[IO.File]::ReadAllText($manifestPath)
    $wrongManifest=$savedManifest|ConvertFrom-Json -AsHashtable -Depth 100;$wrongManifest.model='different-model';Write-E2EText $manifestPath ($wrongManifest|ConvertTo-Json -Depth 20)
    $mismatch=$false;try{& (Join-Path $repo 'evals/compare-risk-diagnostics.ps1') -NativeDirectory $cohorts.native -V3Directory $cohorts.v3 -OutputPath (Join-Path $scratch 'wrong-model.json')|Out-Null}catch{$mismatch=$true}
    Assert $mismatch 'actual diagnostic model provenance must match declared cohort'
    $wrongManifest.Remove('max_tokens');Write-E2EText $manifestPath ($wrongManifest|ConvertTo-Json -Depth 20)
    $missingProvenance=$false;try{& (Join-Path $repo 'evals/compare-risk-diagnostics.ps1') -NativeDirectory $cohorts.native -V3Directory $cohorts.v3 -OutputPath (Join-Path $scratch 'missing-provenance.json')|Out-Null}catch{$missingProvenance=$true}
    Assert $missingProvenance 'missing declared diagnostic budgets cannot be measured'
    Write-E2EText $manifestPath $savedManifest
    $after=Get-E2EHash ((Get-E2ECases -RepoRoot $repo -Suite Release|ForEach-Object {@{id=$_.id;task=$_.task;files=$_.files;answers=$_.answers}})|ConvertTo-Json -Depth 30 -Compress)
    Assert ($before -ceq $after) 'release graders and diagnostic catalog do not mutate implementation model inputs'
    Write-Output "VALID release E2E grading: $passed assertions"
} finally {
    $resolved=[IO.Path]::GetFullPath($scratch)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside temporary root'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
