param([ValidateSet('All','Overflow','Streams','Reports','Snapshot','Legacy')][string]$Case='All')
. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$module=Get-TestControlFlowModule
$limit=33554432
function CaptureFixture([string]$Command,[bool]$Report=$false,[bool]$Legacy=$false){
 $r=NewFixture
 try{
  if($Legacy){$p=LegacyContract $r -Command $Command;$run=New-HistoricalV3RunFixture $r $p -ManualFallback}
  else{
   $p=V4Contract $r final;$v=Get-Content -Raw -LiteralPath $p|ConvertFrom-Json -AsHashtable
   $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
   $v.checks[0].command=$Command;$v.checks[0].timeout_seconds=60
   if(-not $Report){$v.checks[0].Remove('report')}
   [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
   $run=Start-ControlFlowRun $r $p -ManualFallback
   Update-ControlFlowRun $r $run.run_path @{type='preflight';status='APPROVED'}|Out-Null
  }
  return @{root=$r;run=$run.run_path}
 }catch{RemoveFixture $r;throw}
}
function BinaryCommand([long]$Bytes,[string]$Streams='out'){
 return @'
$bytes=__BYTES__L
$block=[byte[]]::new(65536)
$out=[Console]::OpenStandardOutput();$err=[Console]::OpenStandardError()
while($bytes -gt 0){
 $n=[int][Math]::Min($bytes,$block.Length)
 if('__STREAMS__' -in @('out','both')){$out.Write($block,0,$n)}
 if('__STREAMS__' -in @('err','both')){$err.Write($block,0,$n)}
 $bytes-=$n
}
'@.Replace('__BYTES__',[string]$Bytes).Replace('__STREAMS__',$Streams)
}
if($Case -in @('All','Overflow','Streams')){
 foreach($stream in @('out','err')){
  $f=CaptureFixture (BinaryCommand ($limit+1) $stream)
  try{
   $capture=Capture-ControlFlowCheck $f.root $f.run check-1
   Assert ($capture.status -ceq 'FAIL' -and $capture.ContainsKey('error') -and $capture.error -ceq 'OUTPUT_LIMIT_EXCEEDED') ('OverflowFails:'+ $stream)
   $ref=if($stream -ceq 'out'){$capture.stdout_ref}else{$capture.stderr_ref}
   Assert ([IO.FileInfo]::new((Join-Path $f.run $ref.path)).Length -eq $limit) ('OverflowRetainsBoundedPrefix:'+ $stream)
   Assert ($capture.output_limit_bytes -eq $limit -and $capture.output_limit_exceeded) 'V4LimitMetadata'
  }finally{RemoveFixture $f.root}
 }
}
if($Case -in @('All','Streams')){
 $f=CaptureFixture (BinaryCommand $limit both)
 try{
  $capture=Capture-ControlFlowCheck $f.root $f.run check-1
  Assert ($capture.status -ceq 'PASS' -and -not $capture.output_limit_exceeded) 'IndependentExactStreamLimitsPass'
  foreach($ref in @($capture.stdout_ref,$capture.stderr_ref)){Assert ([IO.FileInfo]::new((Join-Path $f.run $ref.path)).Length -eq $limit) 'ExactStreamRetained'}
 }finally{RemoveFixture $f.root}
 # A silent inherited descendant must not outlive output-limit cleanup.
 $childCode="[Threading.Thread]::Sleep(20000);[IO.File]::WriteAllText('.cache/survivor.txt','survived')"
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
  $command=@'
[IO.Directory]::CreateDirectory('.cache')|Out-Null
$start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'});$start.UseShellExecute=$false;$start.CreateNoWindow=$true
foreach($arg in @('-NoProfile','-EncodedCommand','__ENCODED__')){[void]$start.ArgumentList.Add($arg)}
$child=[Diagnostics.Process]::Start($start);[IO.File]::WriteAllText('.cache/child.pid',[string]$child.Id)
'@.Replace('__ENCODED__',$encoded)+[Environment]::NewLine+(BinaryCommand ($limit+1))
 $f=CaptureFixture $command
 try{
  $capture=Capture-ControlFlowCheck $f.root $f.run check-1
  Assert ($capture.status -ceq 'FAIL' -and $capture.error -ceq 'OUTPUT_LIMIT_EXCEEDED') 'OverflowDescendantCaptureFails'
  $childId=[int][IO.File]::ReadAllText((Join-Path $f.root '.cache/child.pid'))
  Assert ($null -eq (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'OverflowKillsOwnedDescendant'
  Assert (-not [IO.File]::Exists((Join-Path $f.root '.cache/survivor.txt'))) 'OverflowDescendantDidNotPublish'
 }finally{if([IO.Directory]::Exists($f.root)){RemoveFixture $f.root}}
}
if($Case -in @('All','Reports')){
 $f=CaptureFixture "[IO.Directory]::CreateDirectory('.cache')|Out-Null; `$s=[IO.File]::Create('.cache/report.xml');try{`$s.SetLength(33554433)}finally{`$s.Dispose()}" $true
 try{
  $capture=Capture-ControlFlowCheck $f.root $f.run check-1
  Assert ($capture.status -ceq 'FAIL' -and $capture.quality.error -ceq 'REPORT_TOO_LARGE') 'OversizedReportFails'
  Assert (-not $capture.quality.ContainsKey('raw_report_ref')) 'OversizedReportNeverArchived'
 }finally{RemoveFixture $f.root}
 $valid='<test-run total="1" passed="1" failed="0" skipped="0" inconclusive="0" asserts="1" result="Passed"><test-case name="exists" result="Passed" asserts="1"/></test-run>'
 foreach($encoding in @([Text.Encoding]::Unicode,[Text.Encoding]::BigEndianUnicode)){
  $p=Join-Path ([IO.Path]::GetTempPath()) ('cf-report-'+[guid]::NewGuid().ToString('N')+'.xml')
  try{
   [IO.File]::WriteAllText($p,$valid,$encoding)
   $quality=Read-ControlFlowQualityReport -Path $p -Format nunit3
   Assert ($quality.status -ceq 'PASS' -and $quality.executed_tests -eq 1) 'Utf16XmlEncodingPreserved'
  }finally{[IO.File]::Delete($p)}
 }
 # Valid XML at the exact existing report limit remains accepted.
 $command=@'
[IO.Directory]::CreateDirectory('.cache')|Out-Null
$prefix='<test-run total="1" passed="1" failed="0" skipped="0" inconclusive="0" asserts="1" result="Passed"><test-case name="exists" result="Passed" asserts="1"/><!--'
$suffix='--></test-run>'
[IO.File]::WriteAllText('.cache/report.xml',$prefix+(' '*(33554432-$prefix.Length-$suffix.Length))+$suffix,[Text.UTF8Encoding]::new($false))
'@
 $f=CaptureFixture $command $true
 try{
  $capture=Capture-ControlFlowCheck $f.root $f.run check-1
  Assert ($capture.status -ceq 'PASS') 'ExactReportLimitPasses'
  Assert ([IO.FileInfo]::new((Join-Path $f.run $capture.quality.raw_report_ref.path)).Length -eq $limit) 'ExactReportBytesRetained'
 }finally{RemoveFixture $f.root}
}
if($Case -in @('All','Snapshot')){
 $f=CaptureFixture "[IO.Directory]::CreateDirectory('.cache')|Out-Null;[IO.File]::WriteAllText('.cache/report.xml','<test-run total=""1"" passed=""1"" failed=""0"" skipped=""0"" inconclusive=""0"" asserts=""1"" result=""Passed""><test-case name=""exists"" result=""Passed"" asserts=""1""/></test-run>')" $true
 try{
  & $module {
   param($Path)
   $script:AuditReportPath=$Path;$script:AuditReportSwapped=$false
   $script:AuditReportOriginal=(Get-Item Function:Read-CFQualityReportBytes).ScriptBlock
   function script:Read-CFQualityReportBytes {
    param([byte[]]$Bytes,[string]$Format,[int]$MinimumTests=1,[Nullable[double]]$MinimumScore,[string]$RepoRoot,[string[]]$Scope,[string]$WorkingDirectory='.')
    if(-not $script:AuditReportSwapped){$script:AuditReportSwapped=$true;[IO.File]::WriteAllText($script:AuditReportPath,'<broken>')}
    & $script:AuditReportOriginal @PSBoundParameters
   }
  } (Join-Path $f.root '.cache/report.xml')
  try{$capture=Capture-ControlFlowCheck $f.root $f.run check-1}
  finally{& $module {Set-Item Function:script:Read-CFQualityReportBytes $script:AuditReportOriginal}}
  Assert ($capture.status -ceq 'PASS' -and $capture.quality.executed_tests -eq 1) 'SnapshotParsingUnaffectedByPathReplacement'
  $raw=[IO.File]::ReadAllText((Join-Path $f.run $capture.quality.raw_report_ref.path))
  Assert ($raw -like '<test-run*' -and [IO.File]::ReadAllText((Join-Path $f.root '.cache/report.xml')) -ceq '<broken>') 'ParsedAndArchivedSameReportGeneration'
 }finally{RemoveFixture $f.root}
}
if($Case -in @('All','Legacy')){
 $f=CaptureFixture (BinaryCommand ($limit+1)) $false $true
 try{
  $capture=Capture-ControlFlowCheck $f.root $f.run check-1
  Assert ($capture.status -ceq 'PASS') 'LegacyV3OutputDefaultUnchanged'
  Assert ([IO.FileInfo]::new((Join-Path $f.run $capture.stdout_ref.path)).Length -eq ($limit+1)) 'LegacyRetainsCompleteOutput'
 }finally{RemoveFixture $f.root}
}
Write-Output "capture-limits $Case : $script:Count assertions passed"
$global:LASTEXITCODE=0
