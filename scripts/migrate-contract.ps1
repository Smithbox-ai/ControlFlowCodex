param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$TaskId,[string]$BaselineCommit)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
$tempPath=$null
try {
$r=Read-ControlFlowContract -Path $Path -AllowV2
if(-not $r.legacy){throw 'MIGRATION_REQUIRES_V2'}
if(Test-Path -LiteralPath $OutputPath){throw 'MIGRATION_OUTPUT_EXISTS'}
$c=$r.contract;$criteria=[Collections.Generic.List[object]]::new();$checks=[Collections.Generic.List[object]]::new()
$criterionMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
$checkMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
function AddCriterion([string]$Text){if(-not $criterionMap.ContainsKey($Text)){$id='C'+($criteria.Count+1);$criterionMap.Add($Text,$id);$criteria.Add(@{id=$id;text=$Text})};return $criterionMap[$Text]}
function AddCheck([string]$Command){if(-not $checkMap.ContainsKey($Command)){$id='check-'+($checks.Count+1);$checkMap.Add($Command,$id);$checks.Add(@{id=$id;command=$Command;working_directory='.';criteria=@()})};return $checkMap[$Command]}
foreach($text in $c.criteria){AddCriterion $text|Out-Null};foreach($command in $c.checks){AddCheck $command|Out-Null}
$risks=@();if($c.ContainsKey('risks')){foreach($key in $c.risks.Keys){$old=$c.risks[$key];$risk=@{id=('R'+($risks.Count+1));text=$key;impact=$old.impact;resolved=$false};if($old.ContainsKey('mitigation')){$risk.mitigation=$old.mitigation};$risks+=,$risk}}
$phases=@();if($c.ContainsKey('phases')){
$phaseMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);foreach($phase in $c.phases){$phaseMap.Add($phase.id,'P'+($phaseMap.Count+1))}
foreach($phase in $c.phases){$next=@{id=$phaseMap[$phase.id];text=$phase.objective;depends_on=@();criteria=@($phase.criteria|ForEach-Object {AddCriterion $_})}
if($phase.ContainsKey('depends_on')){foreach($id in $phase.depends_on){if(-not $phaseMap.ContainsKey($id)){throw 'INVALID_PHASE_REFERENCE'};$next.depends_on+=,$phaseMap[$id]}}
if($phase.ContainsKey('scope')){$next.scope=$phase.scope}
if($phase.ContainsKey('checks')){$next.checks=@($phase.checks|ForEach-Object {AddCheck $_})}
$phases+=,$next}}
$tier=if(@($risks|Where-Object {$_.impact -eq 'HIGH'}).Count -gt 0){'LARGE'}elseif($c.tier -eq 'TRIVIAL'){'SMALL'}else{$c.tier}
$baseline=$c.baseline;if($BaselineCommit){$baseline.commit=$BaselineCommit}
$v3=[ordered]@{schema_version='3.0.0';task_id=$TaskId;goal=$c.goal;tier=$tier;baseline=$baseline;scope=$c.scope;criteria=$criteria.ToArray();checks=$checks.ToArray();risks=$risks;phases=$phases;commit=@{mode='none'}}
$full=[IO.Path]::GetFullPath($OutputPath);$tempPath=$full+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($v3|ConvertTo-Json -Depth 40));$stream=[IO.File]::Open($tempPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
Read-ControlFlowContract $tempPath|Out-Null
[IO.File]::Move($tempPath,$full)
@{status='PASS';output_path=$full;approvals_reused=$false;review_required=$true;coverage_review_required=$true;message='Assign each check to criterion IDs after manual review; gates reject uncovered criteria.'}|ConvertTo-Json;exit 0
}catch{@{status='ERROR';error=$_.Exception.Message}|ConvertTo-Json;exit 2}
finally{if($tempPath -and [IO.File]::Exists($tempPath)){[IO.File]::Delete($tempPath)}}
