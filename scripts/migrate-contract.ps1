param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$TaskId,[string]$BaselineCommit,[string]$TargetVersion='4.0.0')
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ControlFlow.Core.psm1" -Force -DisableNameChecking
$tempPath=$null
try {
 if($TargetVersion -cne '4.0.0'){throw 'MIGRATION_TARGET_MUST_BE_V4'}
 $read=Read-ControlFlowContract -Path $Path -AllowV2
 if($read.contract.schema_version -cnotin @('2.0.0','3.0.0')){throw 'MIGRATION_REQUIRES_LEGACY_CONTRACT'}
 if(Test-Path -LiteralPath $OutputPath){throw 'MIGRATION_OUTPUT_EXISTS'}
 $c=$read.contract
 if($c.schema_version -ceq '2.0.0'){
  $criteria=[Collections.Generic.List[object]]::new();$checks=[Collections.Generic.List[object]]::new()
  $criterionMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  $checkMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  function AddCriterion([string]$Text){if(-not$criterionMap.ContainsKey($Text)){$id='C'+($criteria.Count+1);$criterionMap.Add($Text,$id);$criteria.Add(@{id=$id;text=$Text})};return $criterionMap[$Text]}
  function AddCheck([string]$Command){if(-not$checkMap.ContainsKey($Command)){$id='check-'+($checks.Count+1);$checkMap.Add($Command,$id);$checks.Add(@{id=$id;command=$Command;working_directory='.';criteria=@()})};return $checkMap[$Command]}
  foreach($text in $c.criteria){AddCriterion $text|Out-Null};foreach($command in $c.checks){AddCheck $command|Out-Null}
  $risks=@();if($c.ContainsKey('risks')){foreach($key in $c.risks.Keys){$old=$c.risks[$key];$risk=@{id=('R'+($risks.Count+1));text=$key;impact=$old.impact;resolved=$false};if($old.ContainsKey('mitigation')){$risk.mitigation=$old.mitigation};$risks+=,$risk}}
  $phases=@();if($c.ContainsKey('phases')){
   $phaseMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);foreach($phase in $c.phases){$phaseMap.Add($phase.id,'P'+($phaseMap.Count+1))}
   foreach($phase in $c.phases){$next=@{id=$phaseMap[$phase.id];text=$phase.objective;depends_on=@();criteria=@($phase.criteria|ForEach-Object{AddCriterion $_})}
    if($phase.ContainsKey('depends_on')){foreach($id in $phase.depends_on){if(-not$phaseMap.ContainsKey($id)){throw 'INVALID_PHASE_REFERENCE'};$next.depends_on+=,$phaseMap[$id]}}
    if($phase.ContainsKey('scope')){$next.scope=$phase.scope};if($phase.ContainsKey('checks')){$next.checks=@($phase.checks|ForEach-Object{AddCheck $_})};$phases+=,$next
   }
  }
  $tier=if(@($risks|Where-Object{$_.impact-ceq'HIGH'}).Count){'LARGE'}elseif($c.tier-ceq'TRIVIAL'){'SMALL'}else{$c.tier}
  $base=@{goal=$c.goal;tier=$tier;baseline=$c.baseline;scope=$c.scope;criteria=$criteria.ToArray();checks=$checks.ToArray();risks=$risks;phases=$phases}
 }else{$base=$c}
 $v4=Get-Content (Join-Path $PSScriptRoot '../plans/templates/plan.meta.v4.json') -Raw|ConvertFrom-Json -AsHashtable
 foreach($key in @('goal','tier','baseline','scope','criteria','checks','risks','phases','assumptions')){if($base.ContainsKey($key)){$v4[$key]=$base[$key]}}
 $v4.task_id=$TaskId;$v4.contract_status='draft';$v4.commit=@{mode='none'}
 $v4.review_policy.requirements=@($v4.criteria|ForEach-Object{@{target_id=$_.id;judges=@('code')}})
 if($BaselineCommit){$v4.baseline.commit=$BaselineCommit}
 $full=[IO.Path]::GetFullPath($OutputPath);$tempPath=$full+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($v4|ConvertTo-Json -Depth 40));$stream=[IO.File]::Open($tempPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
 Read-ControlFlowContract $tempPath|Out-Null
 [IO.File]::Move($tempPath,$full)
 @{status='PASS';output_path=$full;schema_version='4.0.0';contract_status='draft';approvals_reused=$false;review_required=$true;coverage_review_required=$true;message='New V4 task only. Review intent, risk, QA and check coverage before finalization; existing runs and approvals are untouched.'}|ConvertTo-Json;exit 0
}catch{@{status='ERROR';error=$_.Exception.Message}|ConvertTo-Json;exit 2}
finally{if($tempPath-and[IO.File]::Exists($tempPath)){[IO.File]::Delete($tempPath)}}