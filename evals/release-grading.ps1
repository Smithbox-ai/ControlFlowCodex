# Development-only outcome/diagnostic graders. None of these definitions enter
# the model fixture or the product runtime. Diagnosis is never judged by regex.
function Get-E2EReleaseCliProbes {
    param([hashtable]$Case)
    if($Case.tier -ne 'LARGE'){return @()}
    $probes=@{
        'order-pipeline'=@{input='[{"customer":"b","quantity":2,"price":3,"cancelled":false},{"customer":"a","quantity":1,"price":9,"cancelled":true},{"customer":"b","quantity":1,"price":4,"cancelled":false},{"customer":"a","quantity":2,"price":4,"cancelled":false}]';expected='["a:8","b:10"]'}
        'inventory-ledger'=@{input='[{"sku":"x","delta":5},{"sku":"x","delta":-2},{"sku":"y","delta":2}]';expected='{"x":3,"y":2}'}
        'event-deduplication'=@{input='[{"id":"a","revision":1},{"id":"b","revision":1},{"id":"a","revision":3}]';expected='[{"id":"a","revision":3},{"id":"b","revision":1}]'}
        'batch-validation'=@{input='[{"id":"","amount":-1},{"id":"a","amount":2},{"id":"b","amount":-1}]';expected='[0,2]'}
        'tenant-routing'=@{input='{"routes":{"a":"one","b":"two"},"requests":["b","a"]}';expected='["two","one"]'}
        'dependency-order'=@{input='{"a":[],"b":["a"],"c":["b"]}';expected='["a","b","c"]'}
        'window-aggregation'=@{input='[{"time":"2026-01-02T01:00:00+03:00","value":2},{"time":"2026-01-01T23:00:00Z","value":3},{"time":"2026-01-02T12:00:00Z","value":7}]';expected='["2026-01-01:5","2026-01-02:7"]'}
        'config-migration'=@{input='{"version":1,"timeoutSeconds":3,"enabled":false}';expected='{"version":2,"timeoutMs":3000,"enabled":false}'}
        'permission-matrix'=@{input='{"role":"editor","action":"write"}';expected='true'}
        'atomic-batch'=@{input='{"balance":5,"deltas":[-2,3]}';expected='6'}
    }
    if(-not $probes.ContainsKey($Case.id)){throw "LARGE case has no predeclared CLI probe: $($Case.id)"}
    return @($probes[$Case.id])
}

function Test-E2EJsonValueEqual {
    param($Actual,$Expected)
    if($null -eq $Actual -or $null -eq $Expected){return $null -eq $Actual -and $null -eq $Expected}
    if($Expected -is [Collections.IDictionary]){
        if($Actual -isnot [Collections.IDictionary] -or $Actual.Count -ne $Expected.Count){return $false}
        foreach($key in $Expected.Keys){
            if($key -cnotin $Actual.Keys -or -not (Test-E2EJsonValueEqual $Actual[$key] $Expected[$key])){return $false}
        }
        return $true
    }
    if($Expected -is [array]){
        if($Actual -isnot [array] -or $Actual.Count -ne $Expected.Count){return $false}
        for($i=0;$i -lt $Expected.Count;$i++){if(-not (Test-E2EJsonValueEqual $Actual[$i] $Expected[$i])){return $false}}
        return $true
    }
    if($Expected -is [bool]){return $Actual -is [bool] -and $Actual -eq $Expected}
    if($Expected -is [string]){return $Actual -is [string] -and $Actual -ceq $Expected}
    if($Actual -is [bool] -or $Actual -is [string] -or $Actual -is [Collections.IDictionary] -or $Actual -is [array]){return $false}
    return $Actual -eq $Expected
}

function Test-E2EReleaseCli {
    param([hashtable]$Case,[hashtable]$Fixture)
    $probes=@(Get-E2EReleaseCliProbes -Case $Case)
    $fail=[Collections.Generic.List[string]]::new();$observations=[Collections.Generic.List[object]]::new()
    $complete=$true;$completed=0
    for($i=0;$i -lt $probes.Count;$i++){
        $probe=$probes[$i];$nonce=[guid]::NewGuid().ToString('N')
        $input=Join-Path (Split-Path $Fixture.root -Parent) ("$nonce-cli-input.json")
        $output=Join-Path (Split-Path $Fixture.root -Parent) ("$nonce-cli-output.json")
        Write-E2EText $input $probe.input
        $capture=Invoke-E2EProcess -Executable (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',(Join-Path $Fixture.root 'cli.ps1'),'-InputFile',$input,'-OutputFile',$output) -WorkingDirectory $Fixture.root -TimeoutSeconds 15
        $collected=$capture.exit_code -eq 0 -and -not $capture.timed_out -and $capture.streams_complete -and $capture.cleanup_verified -and (Test-Path -LiteralPath $output -PathType Leaf)
        $matches=$false;$outputHash=$null
        if($collected){
            try{
                $actual=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($output)) -AsHashtable -NoEnumerate -ErrorAction Stop
                $expected=ConvertFrom-Json -InputObject $probe.expected -AsHashtable -NoEnumerate -ErrorAction Stop
                $matches=Test-E2EJsonValueEqual $actual $expected
                $outputHash=(Get-FileHash -LiteralPath $output).Hash.ToLowerInvariant()
            }catch{$collected=$false}
        }
        if(-not $collected){$complete=$false;$fail.Add("cli-collection:$i")}
        elseif(-not $matches){$completed++;$fail.Add("cli-behavior:$i")}
        else{$completed++}
        $observations.Add(@{probe=$i;nonce=$nonce;collected=$collected;matches=$matches;input_sha256=Get-E2EHash $probe.input;output_sha256=$outputHash;expected_sha256=Get-E2EHash $probe.expected;exit_code=$capture.exit_code;timed_out=$capture.timed_out;streams_complete=$capture.streams_complete;cleanup_verified=$capture.cleanup_verified;wall_ms=$capture.wall_ms})
    }
    return @{applicable=$probes.Count -gt 0;pass=$complete -and $fail.Count -eq 0;collection_complete=$complete;planned_checks=$probes.Count;completed_checks=$completed;failures=$fail.ToArray();observations=$observations.ToArray()}
}

function Get-E2EReleaseDiagnosticCases {
    # Separate protocol: no changes to the frozen Pilot/Release model inputs.
    $specs=@(
        @{id='diagnostic-auth';category='access_control';file='src/authorize.ps1';source="function Test-DeleteAccess { param(`$Role) `n    return `$true`n}`n";line=2;criterion='AUTH-1';diagnosis='Delete access is granted without checking the caller role. Unknown or missing roles can perform deletion; allow only explicit admin.'},
        @{id='diagnostic-path';category='path_traversal';file='src/export.ps1';source="function Get-ExportPath { param(`$Root,`$Name) `n    return Join-Path `$Root `$Name`n}`n";line=2;criterion='PATH-1';diagnosis='An untrusted name is combined with an export directory without rejecting traversal or checking canonical containment; writes can escape the directory.'},
        @{id='diagnostic-migration';category='data_loss';file='src/migrate.ps1';source="function Invoke-Migration { param(`$OldFile,`$NewFile) `n    Remove-Item -LiteralPath `$OldFile -Force`n    Get-Content -LiteralPath `$NewFile -Raw | ConvertFrom-Json | Out-Null`n}`n";line=2;criterion='DATA-1';diagnosis='The previous persisted file is deleted before the replacement is parsed or validated. Invalid input loses the original data; validate first and preserve recoverable prior state.'}
    )
    $task='Audit the repository source for concrete critical defects. Keep source files unchanged. Write diagnostics.json as {"schema_version":"1.0.0","findings":[{"category":"access_control|path_traversal|data_loss","file":"repository relative path","start_line":1,"end_line":1,"mechanism":"specific cause","consequence":"specific impact","mitigation":"relevant remedy"}]}. Use one category value per finding. Include only supported findings, or an empty findings array. Do not commit.'
    foreach($s in $specs){
        $files=@{};$files[$s.file]=$s.source
        $files['README.md']='Audit contract: deletion requires explicit admin; export names are untrusted and must stay inside the export root; migration must retain prior persisted data when replacement validation fails.'
        $expected=@{};foreach($key in $files.Keys){$expected[$key]=$files[$key]}
        @{id=$s.id;tier='CRITICAL_DIAGNOSTIC';task=$task;factory='declarative';files=$files;expected=$expected;reference=@{};oracle='';commit='none';answers=@{};diagnostic_protocol='1.0.0';diagnostic_criteria=@(@{id=$s.criterion;severity='HIGH';category=$s.category;file=$s.file;start_line=$s.line;end_line=$s.line;expected_diagnosis=$s.diagnosis;source_sha256=Get-E2EHash $s.source})}
    }
}

function Get-E2EDiagnosticCriteriaHash {
    param([hashtable]$Case)
    $canonical=@($Case.diagnostic_criteria|Sort-Object id|ForEach-Object {
        [ordered]@{id=[string]$_.id;severity=[string]$_.severity;category=[string]$_.category;file=[string]$_.file;start_line=[int]$_.start_line;end_line=[int]$_.end_line;expected_diagnosis=[string]$_.expected_diagnosis;source_sha256=[string]$_.source_sha256}
    })
    return Get-E2EHash (ConvertTo-Json -InputObject $canonical -Depth 10 -Compress)
}

function Test-E2ECriticalRiskDiagnostics {
    param([hashtable]$Case,[hashtable]$Fixture,[string]$ReviewPath='', [string]$ResultPath='')
    if($Case.diagnostic_protocol -cne '1.0.0' -or -not $Case.diagnostic_criteria.Count){throw 'Diagnostic grading requires predeclared release protocol criteria'}
    $criteriaHash=Get-E2EDiagnosticCriteriaHash -Case $Case
    $artifact=Join-Path $Fixture.root 'diagnostics.json'
    $fail=[Collections.Generic.List[string]]::new();$sourceHashes=@{};$collection=$true;$report=$null;$hash=$null
    foreach($criterion in $Case.diagnostic_criteria){
        $source=Join-Path $Fixture.root $criterion.file
        if(Test-Path -LiteralPath $source -PathType Leaf){$sourceHashes[$criterion.file]=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant()}
        if($sourceHashes[$criterion.file] -cne $criterion.source_sha256){$collection=$false;$fail.Add('source-evidence-changed:'+ $criterion.file)}
    }
    if(Test-Path -LiteralPath $artifact -PathType Leaf){
        try{
            $report=[IO.File]::ReadAllText($artifact)|ConvertFrom-Json -AsHashtable -Depth 30 -ErrorAction Stop
            $hash=(Get-FileHash -LiteralPath $artifact).Hash.ToLowerInvariant()
            if($report.schema_version -cne '1.0.0' -or $report.findings -isnot [array]){throw 'invalid diagnostic protocol'}
            foreach($finding in $report.findings){
                foreach($field in @('category','file','mechanism','consequence','mitigation')){if($finding[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($finding[$field])){throw 'invalid diagnostic finding'}}
                if($finding.category -cnotin @('access_control','path_traversal','data_loss') -or $finding.start_line -isnot [long] -and $finding.start_line -isnot [int] -or $finding.end_line -isnot [long] -and $finding.end_line -isnot [int]){throw 'invalid diagnostic category/location'}
                if($finding.start_line -le 0 -or $finding.end_line -lt $finding.start_line -or $finding.file -cnotin $Case.files.Keys){throw 'invalid diagnostic source location'}
                $lines=($Case.files[$finding.file] -split '\r?\n').Count
                if($finding.end_line -gt $lines){throw 'diagnostic location outside source'}
            }
        }catch{$collection=$false;$fail.Add('diagnostic-artifact-invalid')}
    }else{$collection=$false;$fail.Add('diagnostic-artifact-missing')}
    $review=$null;$reviewComplete=$false;$identified=0;$observations=[Collections.Generic.List[object]]::new();$resultHash=$null;$savedResult=$null
    if($ResultPath){
        try{
            $resultHash=(Get-FileHash -LiteralPath $ResultPath -ErrorAction Stop).Hash.ToLowerInvariant()
            $savedResult=[IO.File]::ReadAllText($ResultPath)|ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop
            $saved=$savedResult.risk_diagnostics
            if($savedResult.case_id -cne $Case.id -or $saved.criteria_sha256 -cne $criteriaHash -or $saved.artifact_sha256 -cne $hash -or -not $saved.collection_complete){throw 'saved native observation binding mismatch'}
            foreach($criterion in $Case.diagnostic_criteria){if($saved.source_hashes[$criterion.file] -cne $sourceHashes[$criterion.file]){throw 'saved source observation changed'}}
        }catch{$collection=$false;$fail.Add('native-capture-binding-invalid')}
    }
    if($ReviewPath -and $collection){
        try{
            $reviewFull=[IO.Path]::GetFullPath($ReviewPath)
            $fixturePrefix=[IO.Path]::GetFullPath($Fixture.root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
            if($reviewFull.StartsWith($fixturePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'review cannot be supplied inside model fixture'}
            $review=[IO.File]::ReadAllText($reviewFull)|ConvertFrom-Json -AsHashtable -Depth 30 -ErrorAction Stop
            $date=[DateTimeOffset]::MinValue
            if($savedResult.case_id -cne $Case.id -or $savedResult.risk_diagnostics.criteria_sha256 -cne $criteriaHash){throw 'result criterion binding mismatch'}
            if($review.schema_version -cne '1.0.0' -or $review.case_id -cne $Case.id -or $review.criteria_sha256 -cne $criteriaHash -or $review.artifact_sha256 -cne $hash -or -not $resultHash -or $review.result_sha256 -cne $resultHash -or $review.reviewer_kind -cne 'human' -or [string]::IsNullOrWhiteSpace($review.reviewer) -or -not [DateTimeOffset]::TryParse($review.reviewed_at,[ref]$date)){throw 'review binding/provenance incomplete'}
            if($review.criteria -isnot [array] -or $review.criteria.Count -ne $Case.diagnostic_criteria.Count){throw 'review criterion coverage incomplete'}
            foreach($criterion in $Case.diagnostic_criteria){
                if($review.sources[$criterion.file] -cne $sourceHashes[$criterion.file]){throw 'review source binding mismatch'}
                $rows=@($review.criteria|Where-Object id -CEQ $criterion.id)
                if($rows.Count -ne 1 -or $rows[0].identified -isnot [bool] -or [string]::IsNullOrWhiteSpace($rows[0].rationale)){throw 'invalid criterion annotation'}
                $row=$rows[0]
                if($row.identified){
                    if($row.finding_index -isnot [long] -and $row.finding_index -isnot [int] -or $row.finding_index -lt 0 -or $row.finding_index -ge $report.findings.Count){throw 'review finding missing'}
                    $finding=$report.findings[$row.finding_index]
                    if($finding.file -cne $criterion.file -or $finding.category -cne $criterion.category -or $finding.start_line -gt $criterion.end_line -or $finding.end_line -lt $criterion.start_line){throw 'review finding does not cite criterion source'}
                    $identified++
                }
            }
            $reviewComplete=$true
        }catch{$reviewComplete=$false;$identified=0;$fail.Add('independent-review-invalid')}
    }
    # Empty reports are collected observations, but the independent protocol
    # still requires explicit annotations of every miss before complete recall.
    foreach($criterion in $Case.diagnostic_criteria){$observations.Add(@{id=$criterion.id;severity=$criterion.severity;file=$criterion.file;source_sha256=$sourceHashes[$criterion.file];collected=$collection;semantic_reviewed=$reviewComplete;identified=if($reviewComplete){$identified -gt 0 -and @($review.criteria|Where-Object { $_.id -ceq $criterion.id -and $_.identified }).Count -eq 1}else{$null}})}
    return @{protocol='1.0.0';case_id=$Case.id;criteria_sha256=$criteriaHash;criterion_count=$Case.diagnostic_criteria.Count;collection_complete=$collection;missing_collection_count=if($collection){0}else{$Case.diagnostic_criteria.Count};semantic_review_complete=$collection -and $reviewComplete;coverage=if($collection -and $reviewComplete){1.0}else{0.0};identified_count=if($collection -and $reviewComplete){$identified}else{$null};recall=if($collection -and $reviewComplete){$identified/$Case.diagnostic_criteria.Count}else{$null};finding_count=if($report){$report.findings.Count}else{$null};artifact_sha256=$hash;result_sha256=$resultHash;source_hashes=$sourceHashes;reviewer=if($reviewComplete -and $review){$review.reviewer}else{$null};review_sha256=if($reviewComplete -and $ReviewPath){(Get-FileHash -LiteralPath $ReviewPath).Hash.ToLowerInvariant()}else{$null};observations=$observations.ToArray();failures=$fail.ToArray();production_ready=$false}
}
