. "$PSScriptRoot/v4-test-helpers.ps1"
LoadCore
$module=Get-TestControlFlowModule
$r=NewFixture
try {
    $p=V4Contract $r final
    $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -AsHashtable
    Assert ((Read-ControlFlowContract $p).contract.schema_version -ceq '4.0.0') 'OrdinaryV4TargetAccepted'
    $v.criteria[0].id='design';$v.checks[0].criteria=@('design');$v.review_policy.requirements[0].target_id='design'
    [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
    $errorText=$null;try {Read-ControlFlowContract $p|Out-Null}catch{$errorText=$_.Exception.Message}
    Assert ($null -ne $errorText) 'ReservedDesignCriterionRejectedBeforeRun'
    Assert (-not (Test-Json -Json ($v|ConvertTo-Json -Depth 40) -SchemaFile "$script:CoreRoot/schemas/plan-meta-v4.schema.json" -ErrorAction SilentlyContinue)) 'SchemaReservesDesignCriterion'
    $failure=$null;try {& $module {param($C) Assert-CFV4Contract $C} $v}catch{$failure=$_.Exception.Message}
    Assert ($failure -ceq 'RESERVED_REVIEW_TARGET_ID:design') 'RuntimeExplainsReservedDesignCriterion'
    $v.criteria[0].id='C1';$v.checks[0].criteria=@('C1');$v.review_policy.requirements[0].target_id='C1'
    $v.phases=@(@{id='design';depends_on=@();criteria=@('C1')})
    Assert (-not (Test-Json -Json ($v|ConvertTo-Json -Depth 40) -SchemaFile "$script:CoreRoot/schemas/plan-meta-v4.schema.json" -ErrorAction SilentlyContinue)) 'SchemaReservesDesignPhase'
    $failure=$null;try {& $module {param($C) Assert-CFV4Contract $C} $v}catch{$failure=$_.Exception.Message}
    Assert ($failure -ceq 'RESERVED_REVIEW_TARGET_ID:design') 'ReservedDesignPhaseRejected'
    $v.phases[0].id='phase-design'
    [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 40))
    Assert ((Read-ControlFlowContract $p).contract.phases[0].id -ceq 'phase-design') 'NamespacedDesignPhaseAccepted'
    Write-Output "review-targets: $script:Count assertions passed"
} finally {RemoveFixture $r}
$global:LASTEXITCODE=0
