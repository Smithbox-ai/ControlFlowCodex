. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$r=NewFixture
try {
$p=V4Contract $r;$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.review_policy.requirements[0].judges=@('code','human','agent');$v.review_policy.human_final=$true
[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
$run=Start-ControlFlowRun $r $p -ManualFallback;$rp=$run.run_path
$context=Artifact $r $rp context;$d=Artifact $r $rp design @($context)
ReviewArtifact $r $rp $d human REJECTED|Out-Null
$decision=ReviewArtifact $r $rp $d human APPROVED;$receipt=$decision.evidence.events[-1].receipt_id
$d2=Artifact $r $rp design @($context) -Revision 2
Throws {Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:old';decision_receipt_id=$receipt}} 'ApprovedOldRevisionCannotResume'
$decision=ReviewArtifact $r $rp $d2 human APPROVED;$receipt=$decision.evidence.events[-1].receipt_id
Update-ControlFlowRun $r $rp @{type='resume';user_decision_ref='user:current';decision_receipt_id=$receipt}|Out-Null
$bad=@{scenarios=@(@{id='S1';inputs='fixture';expected='External requested behavior';expectation_source='user:implement';criterion_refs=@('C1');check_refs=@('imaginary');negative='Invalid';boundary='Empty'})}
Throws {Artifact $r $rp qa-plan @($d2) $bad} 'ImaginaryQACheckRejected'
$qa=Artifact $r $rp qa-plan @($d2);$impl=Artifact $r $rp implementation-plan @($qa)
$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable;$v.contract_status='final';[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
Update-ControlFlowRun $r $rp @{type='preflight';status='APPROVED'}|Out-Null
Throws {Artifact $r $rp qa-recheck @($qa,$impl)} 'QARecheckNeedsActualCapture'
Capture-ControlFlowCheck $r $rp check-1|Out-Null
$changed=@{baseline_ref=$qa;dispositions=@(@{scenario_id='S1';status='PASS';expected='Changed to fit defect';evidence_refs=@('check-1');drift='none'})}
Throws {Artifact $r $rp qa-recheck @($qa,$impl) $changed} 'RecheckCannotLowerExpectation'
$re=Artifact $r $rp qa-recheck @($qa,$impl);$packet=Artifact $r $rp review-packet @($re)
Update-ControlFlowRun $r $rp @{type='coverage';criterion_id='C1';check_ids=@('check-1')}|Out-Null
Assert ((Test-ControlFlowGate $r $rp Completion).status -cne 'PASS') 'AllRequiredJudgesMustPass'
ReviewArtifact $r $rp $packet human APPROVED manual C1|Out-Null
Assert ((Test-ControlFlowGate $r $rp Completion).status -cne 'PASS') 'HumanCannotReplaceAgentJudge'
ReviewArtifact $r $rp $packet agent APPROVED manual C1|Out-Null
Assert ('HUMAN_FINAL_REQUIRED' -cin (Test-ControlFlowGate $r $rp Completion).reasons) 'HumanFinalOverrideCannotBeSkippedByProfile'
ReviewArtifact $r $rp $packet human APPROVED manual final|Out-Null
Assert ((Test-ControlFlowGate $r $rp Completion).status -ceq 'PASS') 'IntegrityPathPasses'
Add-Content -LiteralPath $p -Value ' '
Assert ((Test-ControlFlowGate $r $rp Completion).status -cne 'PASS') 'RawContractBytesInvalidatePromotion'
$ap=Join-Path $rp $packet.path;$saved=[IO.File]::ReadAllText($ap);[IO.File]::WriteAllText($ap,'{}')
Throws {Read-ControlFlowRun $r $rp} 'TamperedArtifactRejected';[IO.File]::WriteAllText($ap,$saved)
Write-Output "v4-integrity: $script:Count assertions passed"
}finally{RemoveFixture $r}
$global:LASTEXITCODE=0
