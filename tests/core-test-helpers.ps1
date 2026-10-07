$ErrorActionPreference='Stop'
$script:CoreRoot=Split-Path $PSScriptRoot -Parent
$script:Count=0
function Assert($Condition,[string]$Message) { if(-not $Condition){throw "ASSERT: $Message"}; $script:Count++ }
function Throws([scriptblock]$Body,[string]$Message) { $thrown=$false;try { & $Body | Out-Null }catch{$thrown=$true};Assert $thrown $Message }
function Git([string]$Root,[string[]]$Arguments){ $v=& (@(Get-Command git -CommandType Application)[0]).Source -C $Root @Arguments 2>&1; if($LASTEXITCODE -ne 0){throw "git failed: $v"};return ($v -join "`n") }
function File([string]$Root,[string]$Path,[string]$Text){$p=[IO.Path]::Combine($Root,$Path);[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))|Out-Null;[IO.File]::WriteAllText($p,$Text)}
function NewFixture { $r=Join-Path ([IO.Path]::GetTempPath()) ('cf-core-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($r)|Out-Null;Git $r @('init','-q')|Out-Null;Git $r @('config','user.email','test@example.invalid')|Out-Null;Git $r @('config','user.name','Fixture')|Out-Null;File $r 'owned.txt' 'initial';File $r 'foreign.txt' 'initial';Git $r @('add','.')|Out-Null;Git $r @('commit','-qm','initial')|Out-Null;return $r }
function Contract([string]$Root,[string]$Tier='SMALL',[string]$Mode='none',[string]$Command='Write-Output ok'){
$p=Join-Path $Root 'plans/artifacts/test-task/plan.meta.json';$c=@{schema_version='3.0.0';task_id='test-task';goal='Real fixture';tier=$Tier;baseline=@{commit=(Git $Root @('rev-parse','HEAD'));dirty_paths=@()};scope=@('owned.txt');criteria=@(@{id='C1';text='Check succeeds'});checks=@(@{id='check-1';command=$Command;working_directory='.';criteria=@('C1')});commit=@{mode=$Mode}};File $Root 'plans/artifacts/test-task/plan.meta.json' ($c|ConvertTo-Json -Depth 20);return $p
}
function LoadCore { $p=Join-Path $script:CoreRoot 'scripts/ControlFlow.Core.psm1';Assert (Test-Path $p) 'deterministic core module exists';Import-Module $p -Force -DisableNameChecking }
