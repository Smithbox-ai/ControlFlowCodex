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
function LegacyContract([string]$Root,[string]$Tier='SMALL',[string]$Mode='none',[string]$Command='Write-Output ok',[string]$SessionId=''){
$p=(Get-ControlFlowStoragePaths $Root 'test-task' $SessionId -Create).contract_path;$c=@{schema_version='3.0.0';task_id='test-task';goal='Real fixture';tier=$Tier;baseline=@{commit=(Git $Root @('rev-parse','HEAD'));dirty_paths=@()};scope=@('owned.txt');criteria=@(@{id='C1';text='Check succeeds'});checks=@(@{id='check-1';command=$Command;working_directory='.';criteria=@('C1')});commit=@{mode=$Mode}};[IO.File]::WriteAllText($p,($c|ConvertTo-Json -Depth 20));return $p
}
function New-HistoricalV3RunFixture {
    param([string]$RepoRoot,[string]$ContractPath,[string]$SessionId,[switch]$ManualFallback)
    # Arrange historical data only. This is not a production legacy-start switch,
    # and never constructs a V4 approval or changes the public creation API.
    & (Get-Module ControlFlow.Core) {
        param($RepoRoot,$ContractPath,$SessionId,$ManualFallback)
        if(-not $SessionId -and -not $ManualFallback){throw 'TRUSTED_SESSION_REQUIRED'}
        $identity=Get-CFIdentity $RepoRoot;$RepoRoot=$identity.worktree_realpath
        if(-not $RepoRoot.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($RepoRoot).StartsWith('cf-core-')){throw 'HISTORICAL_FIXTURE_REQUIRES_OWN_TEMP_REPO'}
        $read=Read-ControlFlowContract $ContractPath;$contract=$read.contract
        if($contract.schema_version -cne '3.0.0'){throw 'HISTORICAL_FIXTURE_REQUIRES_V3'}
        $paths=Get-ControlFlowStoragePaths $RepoRoot $contract.task_id $SessionId
        if([IO.Path]::GetFullPath($ContractPath) -cne [IO.Path]::GetFullPath($paths.contract_path)){throw 'CONTRACT_PATH_BINDING_MISMATCH'}
        Assert-CFBaseline $RepoRoot $contract.baseline.commit|Out-Null
        $id=[guid]::NewGuid().ToString('N');$runPath=[IO.Path]::Combine($paths.task_path,'runs',$id)
        $initial=Get-ControlFlowGitSnapshot $RepoRoot;$initial.source=Get-ControlFlowSourceDigest $RepoRoot $contract.baseline.commit $runPath $SessionId
        [void][IO.Directory]::CreateDirectory($runPath);$identity.session_id=$SessionId
        $state=@{schema_version='3.0.0';task_id=$contract.task_id;run_id=$id;binding=$identity;revision=0;status='ACTIVE';contract_path=$paths.contract_path;initial_contract_digest=$read.digest;baseline_commit=$contract.baseline.commit;manual_fallback=[bool]$ManualFallback;continuations=@{total=0;signature='';repeated=0};structured_reason=$null;acknowledged_interrupt_id=$null;initial_ref=(Write-CFImmutable $runPath 'initial' $script:Utf8.GetBytes(($initial|ConvertTo-Json -Depth 80 -Compress)));evidence_ref=$null}
        Publish-CFState $runPath $state @{events=@();checks=@();candidate=$null}
        if($SessionId){
            $active=Get-CFActivePath $RepoRoot $SessionId;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($active))
            if([IO.File]::Exists($active)){$prior=Get-ControlFlowActiveRun $RepoRoot $SessionId;if($prior.state.status -notin @('COMPLETED','CANCELLED')){throw 'SESSION_ALREADY_ACTIVE'}}
            $pointer=@{schema_version='3.0.0';run_path=$runPath;run_id=$id;task_id=$contract.task_id;binding=$identity}
            [IO.File]::WriteAllText($active,($pointer|ConvertTo-Json -Depth 20 -Compress),$script:Utf8)
        }
        return @{run_path=$runPath;run_id=$id;state=$state;legacy_semantics=$true}
    } $RepoRoot $ContractPath $SessionId ([bool]$ManualFallback)
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
