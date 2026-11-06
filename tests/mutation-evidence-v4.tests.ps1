. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
foreach($case in @('matching','unrelated','threshold')) {
    $r=NewFixture
    try {
        $p=V4Contract $r final
        $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -AsHashtable
        $v.work_type='docs';$v.workflow=@{profile='light';required_artifacts=@('review-packet')};$v.review_policy.human_design=$false
        $v.quality_profiles=@(@{id='sensitivity';kind='mutation';required=$true;capability='available';check_ids=@('check-1')})
        $v.checks[0].report=@{format='stryker-json';path='.cache/mutation.json';tool='fixture';version='1';scope=@('owned.txt');config='inline';baseline='initial';exclusions=@();minimum_score=80}
        $v.checks[0].command=@'
[IO.Directory]::CreateDirectory('.cache')|Out-Null
$report=@{schemaVersion='1';files=@{'owned.txt'=@{source='initial';language='text';mutants=@(@{id='1';status='Killed'})}}}
[IO.File]::WriteAllText('.cache/mutation.json',($report|ConvertTo-Json -Depth 20))
'@
        if($case -ceq 'unrelated'){$v.checks[0].command=$v.checks[0].command.Replace("'owned.txt'","'foreign.txt'")}
        if($case -ceq 'threshold'){$v.checks[0].command=$v.checks[0].command.Replace("status='Killed'","status='Survived'")}
        [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
        $run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
        Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
        $capture=Capture-ControlFlowCheck $r $rp check-1
        Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
        $packet=Artifact $r $rp review-packet
        $saved=Get-Content -LiteralPath (Join-Path $rp $packet.path) -Raw|ConvertFrom-Json -AsHashtable
        $gate=Test-ControlFlowGate $r $rp Completion
        if($case -ceq 'matching'){
            Assert ($capture.status -ceq 'PASS' -and $capture.quality.scope_verified -and $gate.status -ceq 'PASS') 'BoundMutationCaptureCompletes'
            Assert ($saved.profile_summary[0].observations[0].quality.acceptance_status -ceq 'PASS') 'PacketIncludesAcceptanceEvidence'
            $read=Read-ControlFlowRun $r $rp
            $legacyRead=$read|ConvertTo-Json -Depth 80|ConvertFrom-Json -AsHashtable
            $legacyRead.evidence.checks[0].quality.Remove('scope_verified')
            $legacyRead.evidence.checks[0].quality.Remove('verified_scope')
            $module=Get-TestControlFlowModule
            $accepted=& $module {param($read,$p,$source) Test-CFV4Capture $read (Read-ControlFlowContract $p) @{digest=$source} check-1} $legacyRead $p $capture.source_after
            Assert (-not $accepted) 'HistoricalUnboundCaptureNeedsRecapture'
            File $r 'owned.txt' 'changed source'
            $packet=Artifact $r $rp review-packet -Revision 2
            $saved=Get-Content -LiteralPath (Join-Path $rp $packet.path) -Raw|ConvertFrom-Json -AsHashtable
            Assert ($saved.profile_summary[0].status -ceq 'STALE') 'PacketPreservesStaleMutationOutcome'
        } elseif($case -ceq 'unrelated') {
            Assert ($capture.status -ceq 'FAIL' -and $capture.quality.error -like 'MUTATION_REPORT_OUTSIDE_SCOPE:*' -and $gate.status -ceq 'FAIL') 'UnrelatedMutationReportCannotComplete'
            Assert ($saved.profile_summary[0].status -ceq 'ERROR') 'PacketPreservesInvalidReportError'
        } else {
            Assert ($capture.status -ceq 'FAIL' -and $gate.status -ceq 'FAIL') 'BelowThresholdMutationCannotComplete'
            Assert ($saved.profile_summary[0].status -ceq 'FAIL') 'PacketPreservesFailedThreshold'
        }
    } finally {RemoveFixture $r}
}
$r=NewFixture
try {
    $p=V4Contract $r final;$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
    $context=Artifact $r $rp context;$design=Artifact $r $rp design @($context)
    ReviewArtifact $r $rp $design|Out-Null
    $payload=@{scenarios=@(@{id='S1';inputs='fixture';expected='External behavior';expectation_source='request';criterion_refs=@('C1');check_refs=@('check-1');negative='Invalid input fails';boundary='Empty input'})}
    Throws {Artifact $r $rp qa-plan @($design) $payload} 'NewQASaveRequiresSensitivityDecision'
    $payload.mutation_assessment=@{decision='skip';method='none';rationale='No changed executable behavior in fixture';scope=@();criterion_refs=@('C1');check_refs=@()}
    $qa=Artifact $r $rp qa-plan @($design) $payload
    Assert ($qa.path -like 'artifacts/*') 'ExplicitSensitivitySkipCanBeSaved'
} finally {RemoveFixture $r}
Write-Output "mutation-evidence-v4: $script:Count assertions passed"
$global:LASTEXITCODE=0
