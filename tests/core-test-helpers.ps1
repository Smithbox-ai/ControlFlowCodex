$ErrorActionPreference='Stop'
$script:CoreRoot=Split-Path $PSScriptRoot -Parent
$script:Count=0
$script:TestStateRoot=Join-Path ([IO.Path]::GetTempPath()) ('cf-state-tests-'+[guid]::NewGuid().ToString('N'))
$env:CONTROLFLOW_STATE_ROOT=$script:TestStateRoot
function Assert($Condition,[string]$Message) { if(-not $Condition){throw "ASSERT: $Message"}; $script:Count++ }
function Throws([scriptblock]$Body,[string]$Message) { $thrown=$false;try { & $Body | Out-Null }catch{$thrown=$true};Assert $thrown $Message }
function Git([string]$Root,[string[]]$Arguments){ $v=& (@(Get-Command git -CommandType Application)[0]).Source -C $Root @Arguments 2>&1; if($LASTEXITCODE -ne 0){throw "git failed: $v"};return ($v -join "`n") }
function File([string]$Root,[string]$Path,[string]$Text){$p=[IO.Path]::Combine($Root,$Path);[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))|Out-Null;[IO.File]::WriteAllText($p,$Text)}
function NewFixture { $r=Join-Path ([IO.Path]::GetTempPath()) ('cf-core-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($r)|Out-Null;Git $r @('init','-q')|Out-Null;Git $r @('config','user.email','test@example.invalid')|Out-Null;Git $r @('config','user.name','Fixture')|Out-Null;File $r 'owned.txt' 'initial';File $r 'foreign.txt' 'initial';Git $r @('add','.')|Out-Null;Git $r @('commit','-qm','initial')|Out-Null;return $r }
function Contract([string]$Root,[string]$Tier='SMALL',[string]$Mode='none',[string]$Command='Write-Output ok',[string]$SessionId=''){
$p=(Get-ControlFlowStoragePaths $Root 'test-task' $SessionId -Create).contract_path;$c=@{schema_version='3.0.0';task_id='test-task';goal='Real fixture';tier=$Tier;baseline=@{commit=(Git $Root @('rev-parse','HEAD'));dirty_paths=@()};scope=@('owned.txt');criteria=@(@{id='C1';text='Check succeeds'});checks=@(@{id='check-1';command=$Command;working_directory='.';criteria=@('C1')});commit=@{mode=$Mode}};[IO.File]::WriteAllText($p,($c|ConvertTo-Json -Depth 20));return $p
}
function RemoveFixture([string]$Root) {
    $resolved=[IO.Path]::GetFullPath($Root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('cf-core-')){throw 'Unsafe fixture cleanup'}
    $worktree=(Get-ControlFlowStoragePaths $Root 'test-task').worktree_path
    if(-not $worktree.StartsWith($script:TestStateRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe state cleanup'}
    if([IO.Directory]::Exists($worktree)){Remove-Item -LiteralPath $worktree -Recurse -Force}
    foreach($empty in @((Join-Path $script:TestStateRoot 'worktrees'),$script:TestStateRoot)){if([IO.Directory]::Exists($empty) -and [IO.Directory]::GetFileSystemEntries($empty).Length -eq 0){[IO.Directory]::Delete($empty)}}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
function LoadCore { $p=Join-Path $script:CoreRoot 'scripts/ControlFlow.Core.psm1';Assert (Test-Path $p) 'deterministic core module exists';Import-Module $p -Force -DisableNameChecking }
