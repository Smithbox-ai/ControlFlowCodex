$ErrorActionPreference='Stop'
if(-not $IsMacOS -or $env:GITHUB_REPOSITORY -cne 'Smithbox-ai/ControlFlowCodex' -or $env:GITHUB_REF -cne 'refs/heads/validation/v4-macos'){throw 'WRONG_VALIDATION_HOST_OR_REF'}
. (Join-Path $PSScriptRoot 'Test-SourceSnapshot.ps1')
$sourceZip=Join-Path $PSScriptRoot 'source.zip'
$manifestPath=Join-Path $PSScriptRoot 'source-manifest.json'
$zipHash=(Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash.ToLowerInvariant()
if($zipHash -cne '7d65533e1e7aeca13644458fb56156397e7782dd7a9211d4011b458a60fa6252'){throw 'SOURCE_ARCHIVE_HASH_MISMATCH'}
$physicalTemp=(& /bin/sh -c 'cd "$1" && pwd -P' sh $env:RUNNER_TEMP)
if($LASTEXITCODE -or -not [IO.Path]::IsPathFullyQualified($physicalTemp)){throw 'PHYSICAL_TEMP_UNAVAILABLE'}
$root=[IO.Path]::GetFullPath($env:CF_VALIDATION_ROOT)
if([IO.Path]::GetDirectoryName($root) -cne $physicalTemp -or -not [IO.Path]::GetFileName($root).StartsWith('cf',[StringComparison]::Ordinal) -or -not [IO.Directory]::Exists($root)){throw 'OWNED_VALIDATION_ROOT_REQUIRED'}
$expectedTemp=Join-Path $root 'tmp'
if($env:TMPDIR -cne $expectedTemp -or [IO.Path]::GetTempPath().TrimEnd('/') -cne $expectedTemp){throw 'TMPDIR_MUST_BE_SET_BEFORE_POWERSHELL_START'}
$repo=Join-Path $root 'repo'
git clone --no-hardlinks --no-checkout $env:GITHUB_WORKSPACE $repo
if($LASTEXITCODE){throw 'VALIDATION_GIT_CLONE_FAILED'}
$baseline='cb877cd5657ff216d8ba496dc1209a69fd99fa3c'
git -C $repo update-ref HEAD $baseline
if($LASTEXITCODE){throw 'VALIDATION_BASELINE_FAILED'}
git -C $repo read-tree $baseline
if($LASTEXITCODE){throw 'VALIDATION_INDEX_FAILED'}
[IO.Compression.ZipFile]::ExtractToDirectory($sourceZip,$repo)
Test-SourceSnapshot -Root $repo -ManifestPath $manifestPath
$pesterPackage=Join-Path $root 'Pester.5.9.1.nupkg'
Invoke-WebRequest -Uri 'https://www.powershellgallery.com/api/v2/package/Pester/5.9.1' -OutFile $pesterPackage
if((Get-FileHash -LiteralPath $pesterPackage).Hash.ToLowerInvariant() -cne '8dd4060fc3bc895f05bd655e4ab82abe346de54a4e6415dfb727cc8378672b69'){throw 'PESTER_PACKAGE_HASH_MISMATCH'}
$pesterRoot=Join-Path $root 'Pester';[IO.Compression.ZipFile]::ExtractToDirectory($pesterPackage,$pesterRoot)
Import-Module (Join-Path $pesterRoot 'Pester.psd1') -Force
if((Get-Module Pester).Version.ToString() -cne '5.9.1'){throw 'WRONG_PESTER_VERSION'}
$os=& /usr/bin/sw_vers
$summary=[ordered]@{status='RUNNING';started_at=[datetime]::UtcNow.ToString('o');commit=$env:GITHUB_SHA;repository=$env:GITHUB_REPOSITORY;source_zip_sha256=$zipHash;source_files=121;baseline=$baseline;macos=@($os);architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();image_os=$env:ImageOS;image_version=$env:ImageVersion;pwsh=$PSVersionTable.PSVersion.ToString();git=(& git --version);pester='5.9.1';pester_nupkg_sha256='8dd4060fc3bc895f05bd655e4ab82abe346de54a4e6415dfb727cc8378672b69';models=0;artifact_uploads=0;cache_uploads=0;packages=@();corpora=@();native_callbacks='NOT_RUN'}
Write-Output ('ENVIRONMENT_JSON '+($summary|ConvertTo-Json -Depth 5 -Compress))
$progress=Join-Path $root 'suites.txt';$env:CF_MACOS_PROGRESS=$progress
$runner=Join-Path $repo 'tests/run-contract-tests.ps1';$lines=[IO.File]::ReadAllLines($runner);$line=0
for($n=0;$n -lt $lines.Length;$n++){if($lines[$n].Trim() -ceq '$path = Join-Path $testRoot $Name'){$line=$n+1;break}}
if(-not $line){throw 'SUITE_OBSERVATION_POINT_MISSING'}
$expected=@([regex]::Matches([IO.File]::ReadAllText($runner),'(?m)^Invoke-ContractScript "([^"]+)"')|ForEach-Object{$_.Groups[1].Value})
if($expected.Count -ne 35){throw 'WRONG_EXPECTED_SUITE_COUNT'}
try {
    $bp=Set-PSBreakpoint -Script $runner -Line $line -Action {[IO.File]::AppendAllText($env:CF_MACOS_PROGRESS,$Name+[Environment]::NewLine);[Console]::WriteLine([datetime]::UtcNow.ToString('o')+' SUITE '+$Name)}
    $storageBp=Set-PSBreakpoint -Script (Join-Path $repo 'tests/storage.tests.ps1') -Line 17 -Action {
        try {
            $read=Read-ControlFlowRun $r $run.run_path;$capture=@($read.evidence.checks)[-1];$gate=Test-ControlFlowGate $r $run.run_path Completion
            $diagnostic=[ordered]@{capture_status=$capture.status;timed_out=$capture.timed_out;exit_code=$capture.exit_code;process_incomplete=$capture.process_incomplete;gate_status=$gate.status;gate_reasons=$gate.reasons;tmpdir=$env:TMPDIR;runtime_temp=[IO.Path]::GetTempPath()}
            foreach($name in @('stdout','stderr')){$ref=$capture[$name+'_ref'];$value=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $run.run_path $ref.path)));$diagnostic[$name]=$value.Substring(0,[Math]::Min(2048,$value.Length))}
            [Console]::WriteLine('STORAGE_DIAGNOSTIC_JSON '+($diagnostic|ConvertTo-Json -Depth 5 -Compress))
        }catch{[Console]::WriteLine('STORAGE_DIAGNOSTIC_ERROR '+$_.Exception.Message)}
    }
    try {$r=Invoke-Pester -Path (Join-Path $repo 'tests/controlflow-contract.Tests.ps1') -Output Detailed -PassThru} finally {Remove-PSBreakpoint -Breakpoint $bp,$storageBp}
    $actual=@(Get-Content -LiteralPath $progress)
    $summary.pester_result=@{status=$r.Result;passed=$r.PassedCount;failed=$r.FailedCount;skipped=$r.SkippedCount;not_run=$r.NotRunCount;suites=$actual}
    if($r.Result -cne 'Passed' -or $r.PassedCount -ne 1 -or $r.FailedCount -ne 0 -or $r.SkippedCount -ne 0 -or $r.NotRunCount -ne 0 -or $actual.Count -ne 35 -or @(Compare-Object $expected $actual -SyncWindow 0).Count){throw 'ORIGINAL_PESTER_WRAPPER_FAILED_OR_INCOMPLETE'}
    foreach($suite in @('Pilot','Release')){
        $global:LASTEXITCODE=0
        & (Join-Path $repo 'evals/run-e2e.ps1') -RepoRoot $repo -Suite $suite -ValidateOnly
        if($LASTEXITCODE){throw "CORPUS_FAILED:$suite"};$summary.corpora+=@{name=$suite;status='PASS_VALIDATE_ONLY'}
    }
    $global:LASTEXITCODE=0
    & (Join-Path $repo 'evals/run-risk-diagnostics.ps1') -RepoRoot $repo -ValidateOnly
    if($LASTEXITCODE){throw 'DIAGNOSTICS_CORPUS_FAILED'};$summary.corpora+=@{name='Diagnostics';status='PASS_VALIDATE_ONLY'}
    foreach($flavor in @('Universal','NativeLegacy')){
        $out=Join-Path $root ('packages-'+$flavor);$global:LASTEXITCODE=0
        & (Join-Path $repo 'scripts/package.ps1') -OutputDirectory $out -Version '4.0.0-rc.1' -Flavor $flavor
        if($LASTEXITCODE){throw "PACKAGE_FAILED:$flavor"}
        $zip=@(Get-ChildItem -LiteralPath $out -Filter '*.zip' -File)
        if($zip.Count -ne 1){throw 'PACKAGE_OUTPUT_COUNT'}
        $inventory=Get-Content -LiteralPath ($zip[0].FullName+'.inventory.json') -Raw|ConvertFrom-Json -AsHashtable
        $packageHash=(Get-FileHash -LiteralPath $zip[0].FullName).Hash.ToLowerInvariant()
        if($inventory.flavor -cne $flavor -or $inventory.archive_sha256 -cne $packageHash){throw 'PACKAGE_RECEIPT_BINDING_MISMATCH'}
        $source=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -AsHashtable
        $lookup=@{};foreach($f in $source.files){$lookup[$f.path]=$f.sha256}
        $archive=[IO.Compression.ZipFile]::OpenRead($zip[0].FullName)
        try {
            $entries=@($archive.Entries|Where-Object{-not $_.FullName.EndsWith('/')})
            $count=if($flavor -ceq 'Universal'){116}else{115}
            if($entries.Count -ne $count -or $inventory.files.Count -ne $count){throw 'PACKAGE_FILE_COUNT'}
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($entry in $entries){
                $rel=$entry.FullName.Substring('controlflow-codex/'.Length)
                if(-not $entry.FullName.StartsWith('controlflow-codex/',[StringComparison]::Ordinal) -or -not $lookup.ContainsKey($rel) -or -not $seen.Add($rel)){throw 'UNEXPECTED_PACKAGE_ENTRY'}
                $stream=$entry.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()}finally{$stream.Dispose()}
                if($hash -cne $lookup[$rel]){throw "PACKAGE_SOURCE_MISMATCH:$rel"}
            }
            foreach($f in $inventory.files){if(-not $seen.Contains($f.path) -or $f.sha256 -cne $lookup[$f.path]){throw 'PACKAGE_INVENTORY_MISMATCH'}}
        } finally {$archive.Dispose()}
        $summary.packages+=@{flavor=$flavor;files=$count;sha256=$packageHash;entry_bytes_match=$true;inventory=$inventory}
    }
    Test-SourceSnapshot -Root $repo -ManifestPath $manifestPath
    $summary.status='PASS';$summary.source_unchanged=$true
} catch {$summary.status='FAIL';$summary.error=$_.Exception.Message;throw}
finally {$summary.finished_at=[datetime]::UtcNow.ToString('o');Write-Output ('FINAL_RESULT_JSON '+($summary|ConvertTo-Json -Depth 12 -Compress))}
