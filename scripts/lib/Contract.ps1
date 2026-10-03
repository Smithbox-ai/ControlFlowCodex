function Assert-CFMigrationInput {
    param([object]$Contract)
    # This validates imported data for the v3 converter, not an executable legacy
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
    $bytes=[IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path));$text=$script:Utf8.GetString($bytes).TrimStart([char]0xfeff)
    $contract=ConvertFrom-Json -InputObject $text -AsHashtable -Depth 80
    if($AllowV2 -and $contract.schema_version -eq '2.0.0'){
        Assert-CFMigrationInput $contract
        return @{contract=$contract;digest=(Get-CFHash $bytes);legacy=$true}
    }
    $schema=Join-Path $script:CoreModuleRoot '../schemas/plan-meta-v3.schema.json'
    if(-not (Test-Json -Json $text -SchemaFile $schema -ErrorAction Stop)){throw 'INVALID_CONTRACT_SCHEMA'}
    $all=Get-CFMap;$criteria=Get-CFMap
    foreach($kind in @('criteria','checks','phases','risks','assumptions')) {
        if(-not $contract.ContainsKey($kind)){continue}
        foreach($item in $contract[$kind]){if($all.ContainsKey($item.id)){throw "DUPLICATE_ID: $($item.id)"};$all.Add($item.id,$true);if($kind -eq 'criteria'){$criteria.Add($item.id,$true)}}
    }
    foreach($check in $contract.checks){foreach($id in $check.criteria){if(-not $criteria.ContainsKey($id)){throw "INVALID_CRITERION_REFERENCE: $id"}}}
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
    return @{contract=$contract;digest=(Get-CFHash $bytes);legacy=$false}
}
function Get-ControlFlowClassification {
    param([int]$ChangedFiles=0,[switch]$BehaviorChange,[switch]$HighRisk,[switch]$CrossBoundary,[switch]$ProductQuestion)
    $tier=if($HighRisk){'LARGE'}elseif($CrossBoundary -or $ProductQuestion -or $ChangedFiles -gt 5){'MEDIUM'}elseif($BehaviorChange -or $ChangedFiles -gt 1){'SMALL'}else{'TRIVIAL'}
    return @{schema_version='3.0.0';tier=$tier;signals=@{changed_files=$ChangedFiles;behavior_change=[bool]$BehaviorChange;high_risk=[bool]$HighRisk;cross_boundary=[bool]$CrossBoundary;product_question=[bool]$ProductQuestion}}
}
