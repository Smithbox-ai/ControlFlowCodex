function Assert-CFMigrationInput {
    param([object]$Contract)
    # This validates imported data for the V4 converter, not an executable legacy
    # contract. It has no dependency on an installed legacy runtime or schema.
    function Assert-CFMigrationObject($Value,[string[]]$Required,[string[]]$Optional=@()) {
        if($Value -isnot [Collections.IDictionary]){throw 'INVALID_MIGRATION_INPUT: object required'}
        foreach($name in $Required){if($name -cnotin @($Value.Keys)){throw "INVALID_MIGRATION_INPUT: missing $name"}}
        foreach($name in $Value.Keys){if($name -cnotin ($Required+$Optional)){throw "INVALID_MIGRATION_INPUT: unknown $name"}}
    }
    function Assert-CFMigrationText($Value) {
        if($Value -isnot [string] -or $Value.Length -eq 0){throw 'INVALID_MIGRATION_INPUT: nonempty string required'}
    }
    function Assert-CFMigrationTexts($Value,[bool]$RequireItem=$false) {
        if($Value -isnot [Collections.IList] -or ($RequireItem -and $Value.Count -eq 0)){throw 'INVALID_MIGRATION_INPUT: string array required'}
        foreach($item in $Value){Assert-CFMigrationText $item}
    }
    Assert-CFMigrationObject $Contract @('schema_version','goal','tier','baseline','scope','criteria','checks') @('risks','phases')
    if($Contract.schema_version -cne '2.0.0'){throw 'INVALID_MIGRATION_INPUT: unsupported input version'}
    Assert-CFMigrationText $Contract.goal
    if($Contract.tier -isnot [string] -or $Contract.tier -cnotin @('TRIVIAL','SMALL','MEDIUM','LARGE')){throw 'INVALID_MIGRATION_INPUT: invalid tier'}
    Assert-CFMigrationObject $Contract.baseline @('commit','dirty_paths')
    Assert-CFMigrationText $Contract.baseline.commit
    Assert-CFMigrationTexts $Contract.baseline.dirty_paths
    foreach($name in @('scope','criteria','checks')){Assert-CFMigrationTexts $Contract[$name] $true}
    if($Contract.ContainsKey('risks')){
        if($Contract.risks -isnot [Collections.IDictionary]){throw 'INVALID_MIGRATION_INPUT: risk map required'}
        foreach($risk in $Contract.risks.Values){
            Assert-CFMigrationObject $risk @('impact') @('mitigation')
            if($risk.impact -isnot [string] -or $risk.impact -cnotin @('LOW','MEDIUM','HIGH')){throw 'INVALID_MIGRATION_INPUT: invalid risk impact'}
            if($risk.ContainsKey('mitigation')){Assert-CFMigrationText $risk.mitigation}
        }
    }
    if($Contract.ContainsKey('phases')){
        if($Contract.phases -isnot [Collections.IList]){throw 'INVALID_MIGRATION_INPUT: phase array required'}
        $phases=Get-CFMap
        foreach($phase in $Contract.phases){
            Assert-CFMigrationObject $phase @('id','objective','criteria') @('depends_on','scope','checks')
            Assert-CFMigrationText $phase.id;Assert-CFMigrationText $phase.objective
            Assert-CFMigrationTexts $phase.criteria $true
            foreach($name in @('depends_on','scope','checks')){if($phase.ContainsKey($name)){Assert-CFMigrationTexts $phase[$name]}}
            if($phases.ContainsKey($phase.id)){throw 'INVALID_MIGRATION_INPUT: duplicate phase ID'}
            $phases.Add($phase.id,$phase)
        }
        $visiting=Get-CFMap;$done=Get-CFMap
        function Visit-CFMigrationPhase([string]$Id) {
            if($done.ContainsKey($Id)){return}
            if($visiting.ContainsKey($Id)){throw 'INVALID_MIGRATION_INPUT: phase dependency cycle'}
            if(-not $phases.ContainsKey($Id)){throw 'INVALID_MIGRATION_INPUT: unknown phase dependency'}
            $visiting[$Id]=$true;$phase=$phases[$Id]
            if($phase.ContainsKey('depends_on')){foreach($dependency in $phase.depends_on){Visit-CFMigrationPhase $dependency}}
            [void]$visiting.Remove($Id);$done[$Id]=$true
        }
        foreach($id in $phases.Keys){Visit-CFMigrationPhase $id}
    }
}
function Read-ControlFlowContract {
    param([Parameter(Mandatory)][string]$Path,[switch]$AllowV2)
    $bytes=[IO.File]::ReadAllBytes((Get-CFFullPath $Path));$text=$script:Utf8.GetString($bytes).TrimStart([char]0xfeff)
    $contract=ConvertFrom-Json -InputObject $text -AsHashtable -Depth 80
    if($AllowV2 -and $contract.schema_version -eq '2.0.0'){
        Assert-CFMigrationInput $contract
        return @{contract=$contract;digest=(Get-CFHash $bytes);legacy=$true}
    }
    if($contract.schema_version -cnotin @('3.0.0','4.0.0')){throw 'UNSUPPORTED_CONTRACT_VERSION'}
    $schema=Join-Path $script:CoreModuleRoot $(if($contract.schema_version -ceq '3.0.0'){'../schemas/compat/plan-meta-v3.schema.json'}else{'../schemas/plan-meta-v4.schema.json'})
    if(-not (Test-Json -Json $text -SchemaFile $schema -ErrorAction Stop)){throw 'INVALID_CONTRACT_SCHEMA'}
    $all=Get-CFMap;$criteria=Get-CFMap
    foreach($kind in @('criteria','checks','phases','risks','assumptions')) {
        if(-not $contract.ContainsKey($kind)){continue}
        foreach($item in $contract[$kind]){if($all.ContainsKey($item.id)){throw "DUPLICATE_ID: $($item.id)"};$all.Add($item.id,$true);if($kind -eq 'criteria'){$criteria.Add($item.id,$true)}}
    }
    foreach($check in $contract.checks){
        foreach($id in $check.criteria){if(-not $criteria.ContainsKey($id)){throw "INVALID_CRITERION_REFERENCE: $id"}}
        if($check.ContainsKey('inputs')){foreach($path in $check.inputs){
            if([IO.Path]::IsPathRooted($path) -or $path.Contains('\') -or $path -match '[:*?]' -or @($path.Split('/') | Where-Object {$_ -in @('','.','..')}).Count -gt 0){throw "INVALID_CHECK_INPUT_PATH: $path"}
        }}
    }
    if($contract.ContainsKey('risks')){foreach($risk in $contract.risks){if($risk.impact -eq 'HIGH' -and -not $risk.resolved -and $contract.tier -ne 'LARGE'){throw 'UNRESOLVED_HIGH_REQUIRES_LARGE'}}}
    if($contract.ContainsKey('phases')) {
        $phases=Get-CFMap;foreach($phase in $contract.phases){$phases.Add($phase.id,$phase)}
        $visiting=Get-CFMap;$done=Get-CFMap
        function Visit-CFPhase([string]$Id) {
            if($done.ContainsKey($Id)){return};if($visiting.ContainsKey($Id)){throw 'PHASE_CYCLE'}
            if(-not $phases.ContainsKey($Id)){throw "INVALID_PHASE_REFERENCE: $Id"};$visiting[$Id]=$true
            foreach($dependency in $phases[$Id].depends_on){Visit-CFPhase $dependency};[void]$visiting.Remove($Id);$done[$Id]=$true
        }
        foreach($id in $phases.Keys){Visit-CFPhase $id}
        foreach($phase in $contract.phases){if($phase.ContainsKey('checks')){foreach($id in $phase.checks){if($id -cnotin @($contract.checks.id)){throw 'INVALID_CHECK_REFERENCE'}}}}
        foreach($phase in $contract.phases){if($phase.ContainsKey('criteria')){foreach($id in $phase.criteria){if(-not $criteria.ContainsKey($id)){throw 'INVALID_CRITERION_REFERENCE'}}}}
    }
    foreach($glob in $contract.scope){if([IO.Path]::IsPathRooted($glob) -or $glob.Split('/') -contains '..' -or $glob.Contains('\')){throw 'INVALID_SCOPE_PATH'}}
    if($contract.schema_version -ceq '4.0.0'){Assert-CFV4Contract $contract}
    return @{contract=$contract;digest=(Get-CFHash $bytes);legacy=($contract.schema_version -ceq '3.0.0');compatibility=$(if($contract.schema_version -ceq '3.0.0'){'migration-or-existing-run-only'}else{'current'})}
}
function Get-ControlFlowClassification {
    param([int]$ChangedFiles=0,[switch]$BehaviorChange,[switch]$HighRisk,[switch]$CrossBoundary,[switch]$ProductQuestion,[ValidateSet('4.0.0')][string]$SchemaVersion='4.0.0',[ValidateSet('feature','bugfix','refactor','docs')][string]$WorkType='feature',[ValidateSet('core','supporting','generic','unknown')][string]$Domain='unknown')
    $tier=if($HighRisk){'LARGE'}elseif($CrossBoundary -or $ProductQuestion -or $ChangedFiles -gt 5){'MEDIUM'}elseif($BehaviorChange -or $ChangedFiles -gt 1){'SMALL'}else{'TRIVIAL'}
    $human=$HighRisk -or $CrossBoundary -or $ProductQuestion -or $Domain -in @('core','unknown')
    $profile=if($tier -eq 'TRIVIAL' -and -not $human -and $WorkType -eq 'docs'){'light'}else{$WorkType}
    return @{schema_version=$SchemaVersion;tier=$(if($tier -ceq 'TRIVIAL'){'SMALL'}else{$tier});workflow=@{profile=$profile;required_artifacts=@(Get-CFWorkflowKinds $profile)};review_policy=@{human_design=[bool]($human -or $WorkType -eq 'feature');human_final=[bool]$human}}
}
function Get-CFWorkflowKinds([string]$Profile) {
    switch -CaseSensitive($Profile){
        'light' {return @('review-packet')}
        {$_ -in @('feature','bugfix','refactor','docs')} {return @('context','design','qa-plan','implementation-plan','qa-recheck','review-packet')}
        default {throw 'UNKNOWN_WORKFLOW'}
    }
}
function Assert-CFV4Contract($Contract) {
    $expected=@(Get-CFWorkflowKinds $Contract.workflow.profile)
    if(($expected -join '|') -cne (@($Contract.workflow.required_artifacts) -join '|')){throw 'FIXED_WORKFLOW_REQUIRED'}
    if($Contract.workflow.profile -cne 'light' -and $Contract.workflow.profile -cne $Contract.work_type){throw 'WORKFLOW_WORK_TYPE_MISMATCH'}
    $risks=if($Contract.ContainsKey('risks')){@($Contract.risks)}else{@()};$high=@($risks|Where-Object {$_.impact -ceq 'HIGH'}).Count -gt 0
    if($Contract.workflow.profile -ceq 'light' -and ($Contract.work_type -cne 'docs' -or $Contract.tier -cne 'SMALL' -or $Contract.domain.classification -notin @('generic','supporting') -or $high)){throw 'LIGHT_ROUTE_UNSAFE'}
    if(($Contract.domain.classification -in @('core','unknown') -or $high) -and (-not $Contract.review_policy.human_design -or -not $Contract.review_policy.human_final)){throw 'DOMAIN_DOES_NOT_LOWER_RISK'}
    if($Contract.work_type -ceq 'feature' -and -not $Contract.review_policy.human_design){throw 'HUMAN_DESIGN_REQUIRED'}
    $targets=@($Contract.criteria|ForEach-Object {$_.id});if($Contract.ContainsKey('phases')){$targets+=@($Contract.phases|ForEach-Object {$_.id})};$seen=Get-CFMap
    if('design' -cin $targets){throw 'RESERVED_REVIEW_TARGET_ID:design'}
    foreach($req in $Contract.review_policy.requirements){
        if($seen.ContainsKey($req.target_id)){throw 'DUPLICATE_REVIEW_TARGET'};$seen[$req.target_id]=$true
        if($Contract.contract_status -ceq 'final' -and $req.target_id -cnotin $targets){throw 'INVALID_REVIEW_TARGET'}
        if($Contract.contract_status -ceq 'final' -and 'code' -cin $req.judges){
            $ids=@(if($req.target_id -cin @($Contract.criteria|ForEach-Object {$_.id})){$req.target_id}else{($Contract.phases|Where-Object {$_.id -ceq $req.target_id}).criteria})
            if($ids.Count -eq 0){throw 'CODE_TARGET_CRITERIA_REQUIRED'}
            foreach($id in $ids){if(@($Contract.checks|Where-Object {$id -cin $_.criteria}).Count -eq 0){throw 'CODE_CRITERION_CHECK_REQUIRED'}}
        }
    }
    if($Contract.contract_status -ceq 'final'){foreach($criterion in $Contract.criteria){if(-not $seen.ContainsKey($criterion.id)){throw 'CRITERION_REVIEW_REQUIREMENT_MISSING'}}}
    $profiles=Get-CFMap
    foreach($profile in $Contract.quality_profiles){
        if($profiles.ContainsKey($profile.id)){throw 'DUPLICATE_QUALITY_PROFILE'};$profiles[$profile.id]=$true
        foreach($id in $profile.check_ids){if($id -cnotin @($Contract.checks|ForEach-Object {$_.id})){throw 'INVALID_PROFILE_CHECK'}}
        if($profile.required -and $profile.check_ids.Count -eq 0 -and $profile.capability -ceq 'available'){throw 'REQUIRED_PROFILE_CHECK_MISSING'}
        if($Contract.contract_status -ceq 'final' -and $profile.kind -ceq 'mutation' -and $profile.required -and $profile.capability -ceq 'available'){
            foreach($check in $Contract.checks|Where-Object {$_.id -cin $profile.check_ids}){
                if($check.ContainsKey('report') -and $check.report.format -ceq 'stryker-json' -and (-not $check.report.ContainsKey('minimum_score') -or $check.report.minimum_score -le 0)){throw 'REQUIRED_MUTATION_MINIMUM_SCORE_REQUIRED'}
            }
        }
    }
}
function Assert-CFV4MutationAssessment($Contract,$Payload) {
    # This is a guard for newly saved QA plans. Historical artifacts remain
    # schema-readable without an assessment and are never retroactively edited.
    if($Contract.schema_version -cne '4.0.0' -or $Contract.workflow.profile -ceq 'light'){return}
    $hasCode=@($Contract.review_policy.requirements|Where-Object {'code' -cin $_.judges}).Count -gt 0
    $mutationProfiles=@($Contract.quality_profiles|Where-Object {$_.kind -ceq 'mutation'})
    if($Payload -isnot [Collections.IDictionary] -or -not $Payload.ContainsKey('mutation_assessment')){
        if(-not $hasCode -and $mutationProfiles.Count -eq 0){return}
        throw 'MUTATION_ASSESSMENT_REQUIRED'
    }
    $assessment=$Payload.mutation_assessment
    if($assessment -isnot [Collections.IDictionary]){throw 'MUTATION_ASSESSMENT_INVALID'}
    $required=@('decision','method','rationale','scope','criterion_refs','check_refs')
    foreach($name in $required){if(-not $assessment.ContainsKey($name)){throw ('MUTATION_ASSESSMENT_FIELD_REQUIRED:'+$name)}}
    foreach($name in $assessment.Keys){if($name -cnotin ($required+@('budget','acceptance'))){throw ('MUTATION_ASSESSMENT_UNKNOWN_FIELD:'+$name)}}
    foreach($name in @('decision','method','rationale','budget','acceptance')){
        if($assessment.ContainsKey($name) -and ($assessment[$name] -isnot [string] -or [string]::IsNullOrWhiteSpace($assessment[$name]))){throw ('MUTATION_ASSESSMENT_TEXT_REQUIRED:'+$name)}
    }
    if($assessment.decision -cnotin @('run','skip','unsupported')){throw 'MUTATION_ASSESSMENT_INVALID_DECISION'}
    foreach($name in @('scope','criterion_refs','check_refs')){
        if($assessment[$name] -isnot [Collections.IList]){throw ('MUTATION_ASSESSMENT_ARRAY_REQUIRED:'+$name)}
        $seen=Get-CFMap
        foreach($value in $assessment[$name]){
            if($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $seen.ContainsKey($value)){throw ('MUTATION_ASSESSMENT_INVALID_ARRAY:'+$name)}
            $seen[$value]=$true
        }
    }
    foreach($path in $assessment.scope){
        if([IO.Path]::IsPathRooted($path) -or $path.Contains('\') -or $path -match '[:*?\[\]\x00-\x1f]' -or @($path.Split('/')|Where-Object {$_ -cin @('','.','..')}).Count -gt 0){throw ('MUTATION_ASSESSMENT_INVALID_SCOPE:'+$path)}
    }
    foreach($id in $assessment.criterion_refs){if($id -cnotin @($Contract.criteria|ForEach-Object {$_.id})){throw ('MUTATION_ASSESSMENT_INVALID_CRITERION:'+$id)}}
    foreach($id in $assessment.check_refs){if($id -cnotin @($Contract.checks|ForEach-Object {$_.id})){throw ('MUTATION_ASSESSMENT_INVALID_CHECK:'+$id)}}
    if($assessment.decision -cne 'run'){
        if($assessment.method -cne 'none' -or $assessment.check_refs.Count -ne 0){throw 'MUTATION_ASSESSMENT_NONRUN_METHOD_OR_CHECKS'}
        return
    }
    if($assessment.method -cnotin @('stryker','controlled')){throw 'MUTATION_ASSESSMENT_RUN_METHOD_REQUIRED'}
    foreach($name in @('scope','criterion_refs','check_refs')){if($assessment[$name].Count -eq 0){throw ('MUTATION_ASSESSMENT_RUN_ARRAY_REQUIRED:'+$name)}}
    foreach($name in @('budget','acceptance')){if(-not $assessment.ContainsKey($name)){throw ('MUTATION_ASSESSMENT_FIELD_REQUIRED:'+$name)}}
    $coveredCriteria=Get-CFMap;$reportedScope=Get-CFMap
    foreach($id in $assessment.check_refs){
        $check=@($Contract.checks|Where-Object {$_.id -ceq $id})[0]
        $assessed=@($check.criteria|Where-Object {$_ -cin $assessment.criterion_refs})
        if($assessed.Count -eq 0){throw ('MUTATION_ASSESSMENT_CHECK_CRITERIA_REQUIRED:'+$id)}
        foreach($criterion in $assessed){$coveredCriteria[$criterion]=$true}
        $scenarios=if($Payload.ContainsKey('scenarios')){@($Payload.scenarios)}else{@()}
        if(@($scenarios|Where-Object {$id -cin $_.check_refs -and @($_.criterion_refs|Where-Object {$_ -cin $assessed}).Count -gt 0}).Count -eq 0){throw ('MUTATION_ASSESSMENT_QA_SCENARIO_REQUIRED:'+$id)}
        if($assessment.method -ceq 'stryker'){
            if(-not $check.ContainsKey('report') -or $check.report.format -cne 'stryker-json' -or @($mutationProfiles|Where-Object {$id -cin $_.check_ids}).Count -eq 0){throw ('MUTATION_ASSESSMENT_STRYKER_PROFILE_REQUIRED:'+$id)}
            foreach($path in $check.report.scope){$reportedScope[$path]=$true}
        }
    }
    foreach($id in $assessment.criterion_refs){if(-not $coveredCriteria.ContainsKey($id)){throw ('MUTATION_ASSESSMENT_CRITERION_CHECK_REQUIRED:'+$id)}}
    if($assessment.method -ceq 'stryker'){
        if($assessment.scope.Count -ne $reportedScope.Count){throw 'MUTATION_ASSESSMENT_STRYKER_SCOPE_MISMATCH'}
        foreach($path in $assessment.scope){if(-not $reportedScope.ContainsKey($path)){throw 'MUTATION_ASSESSMENT_STRYKER_SCOPE_MISMATCH'}}
    }
}
function Get-CFIntentDigest($Contract) {
    Get-CFJsonHash ([ordered]@{task_id=$Contract.task_id;goal=$Contract.goal;baseline=$Contract.baseline;scope=$Contract.scope;intent=$Contract.intent;domain=$Contract.domain;work_type=$Contract.work_type;risks=$(if($Contract.ContainsKey('risks')){@($Contract.risks)}else{@()})})
}
function Get-CFPolicyDigest($Contract) {Get-CFJsonHash ([ordered]@{workflow=$Contract.workflow;review_policy=$Contract.review_policy})}
