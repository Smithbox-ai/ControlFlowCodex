param([ValidateSet('source','contract','input','interrupt')][string]$ChangeOnly,[ValidateSet('snapshot','publication')][string]$BoundaryOnly)
. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$module=Get-TestControlFlowModule
$r=NewFixture
try {
    $session='completion-race-session'
    $p=V4Contract $r final $session
    File $r '.cache/guard.cs' 'initial guard'
    $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -AsHashtable
    $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
    $v.quality_profiles=@(@{id='mutation';kind='mutation';required=$true;capability='available';check_ids=@('check-1')})
    $v.checks[0].report=@{format='stryker-json';path='.cache/mutation.json';tool='fixture';version='1';scope=@('.cache/guard.cs');config='inline';baseline='initial';exclusions=@();minimum_score=80}
    $v.checks[0].command=@'
$report=@{schemaVersion='1';files=@{'.cache/guard.cs'=@{source='initial guard';language='cs';mutants=@(@{id='1';status='Killed'})}}}
[IO.File]::WriteAllText('.cache/mutation.json',($report|ConvertTo-Json -Depth 20))
'@
    [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
    $contractBytes=[IO.File]::ReadAllBytes($p)
    $run=Start-ControlFlowRun $r $p -SessionId $session;$rp=$run.run_path
    Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
    Capture-ControlFlowCheck $r $rp check-1|Out-Null
    Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
    Artifact $r $rp review-packet|Out-Null
    Assert ((Test-ControlFlowGate $r $rp Completion).status -ceq 'PASS') 'UnchangedCompletionBaselinePasses'
    foreach($boundary in @('snapshot','publication')) {
        if($BoundaryOnly -and $boundary -cne $BoundaryOnly){continue}
        foreach($change in @('source','contract','input','interrupt')) {
            if($ChangeOnly -and $change -cne $ChangeOnly){continue}
            & $module {
                param($Root,$ContractPath,$Boundary,$Change)
                $script:AuditRaceRoot=$Root;$script:AuditRaceContract=$ContractPath;$script:AuditRaceChange=$Change;$script:AuditRaceFired=$false
                $script:AuditOriginalSnapshot=(Get-Item Function:Get-ControlFlowGitSnapshot).ScriptBlock
                $script:AuditOriginalGate=(Get-Item Function:Test-ControlFlowGate).ScriptBlock
                function script:Invoke-CFAuditEdit {
                    $script:AuditRaceFired=$true
                    if($script:AuditRaceChange -ceq 'source'){[IO.File]::WriteAllText((Join-Path $script:AuditRaceRoot 'owned.txt'),'changed during completion')}
                    elseif($script:AuditRaceChange -ceq 'input'){[IO.File]::WriteAllText((Join-Path $script:AuditRaceRoot '.cache/guard.cs'),'changed ignored target')}
                    elseif($script:AuditRaceChange -ceq 'interrupt'){Request-ControlFlowInterrupt $script:AuditRaceRoot 'completion-race-session'|Out-Null}
                    else {
                        $c=Get-Content -LiteralPath $script:AuditRaceContract -Raw|ConvertFrom-Json -AsHashtable
                        $c.goal+=' changed during completion'
                        [IO.File]::WriteAllText($script:AuditRaceContract,($c|ConvertTo-Json -Depth 40))
                    }
                }
                if($Boundary -ceq 'snapshot') {
                    function script:Get-ControlFlowGitSnapshot {
                        param([string]$RepoRoot,[string]$ArtifactRoot,[string]$SessionId)
                        if(-not $script:AuditRaceFired -and (Get-PSCallStack)[1].Command -ceq 'Test-ControlFlowGate'){Invoke-CFAuditEdit}
                        & $script:AuditOriginalSnapshot @PSBoundParameters
                    }
                } else {
                    function script:Test-ControlFlowGate {
                        param([string]$RepoRoot,[string]$RunPath,[string]$Kind,[string]$CommitSha)
                        $gate=& $script:AuditOriginalGate @PSBoundParameters
                        if($Kind -ceq 'Completion' -and $gate.status -ceq 'PASS' -and -not $script:AuditRaceFired){Invoke-CFAuditEdit}
                        return $gate
                    }
                }
            } $r $p $boundary $change
            try {
                $errorText=$null
                try {Update-ControlFlowRun $r $rp @{type='complete'}|Out-Null}catch{$errorText=$_.Exception.Message}
                $fired=& $module {$script:AuditRaceFired}
                $read=Read-ControlFlowRun $r $rp
                $expectedStatus=if($change -ceq 'interrupt'){'INTERRUPTED'}else{'ACTIVE'}
                Assert ($fired -and $errorText -and $read.state.status -ceq $expectedStatus) ('ConcurrentChangeCannotComplete:'+ $boundary+':'+$change)
                Assert (@($read.evidence.events|Where-Object {$_.type -ceq 'complete'}).Count -eq 0) ('FailedCompletionNotPublished:'+ $boundary+':'+$change)
            } finally {
                & $module {
                    Set-Item Function:script:Get-ControlFlowGitSnapshot $script:AuditOriginalSnapshot
                    Set-Item Function:script:Test-ControlFlowGate $script:AuditOriginalGate
                    Remove-Item Function:script:Invoke-CFAuditEdit
                }
                File $r 'owned.txt' 'initial'
                File $r '.cache/guard.cs' 'initial guard'
                [IO.File]::WriteAllBytes($p,$contractBytes)
                if($change -ceq 'interrupt'){
                    $current=Read-ControlFlowRun $r $rp
                    if($current.state.status -ceq 'INTERRUPTED' -and -not ($current.state.ContainsKey('lifecycle_closed') -and $current.state.lifecycle_closed)){Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:fixture-resume'}|Out-Null}
                }
            }
        }
    }
    Update-ControlFlowRun $r $rp @{type='complete'}|Out-Null
    Assert ((Read-ControlFlowRun $r $rp).state.status -ceq 'COMPLETED') 'StableCompletionStillPublishes'
    Write-Output "completion-race: $script:Count assertions passed"
} finally {RemoveFixture $r}
$global:LASTEXITCODE=0
