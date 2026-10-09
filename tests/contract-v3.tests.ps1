. "$PSScriptRoot/core-test-helpers.ps1"
LoadCore
$readerSource=Get-Content -LiteralPath (Join-Path $script:CoreRoot 'scripts/lib/Contract.ps1') -Raw
Assert ($readerSource -notmatch 'plan-meta\.schema\.json') 'migration input validation has no shipped v2 schema dependency'
$r=NewFixture
try {
$p=Contract $r
$c=Read-ControlFlowContract -Path $p
Assert ($c.contract.task_id -eq 'test-task') 'valid v3 contract read'
$v=Get-Content $p -Raw|ConvertFrom-Json -AsHashtable
$v.checks[0].criteria=@('missing');[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
Throws {Read-ControlFlowContract $p} 'invalid criterion reference rejected'
$v.checks[0].criteria=@('C1');$v.phases=@(@{id='P1';depends_on=@('P2')},@{id='P2';depends_on=@('P1')});[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
Throws {Read-ControlFlowContract $p} 'phase dependency cycle rejected'
$v.Remove('phases');$v.risks=@(@{id='R1';impact='HIGH';resolved=$false;text='Danger'});[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
Throws {Read-ControlFlowContract $p} 'unresolved high risk requires LARGE'
$v.tier='LARGE';[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
Assert ((Read-ControlFlowContract $p).contract.tier -eq 'LARGE') 'large high risk contract accepted'
$v.unknown='bad';[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 20))
Throws {Read-ControlFlowContract $p} 'unknown field rejected'
Write-Output "contract-v3: $script:Count assertions passed"
}finally{RemoveFixture $r}
# Migration must retain HIGH risks and never guess criterion coverage.
$r=NewFixture
try {
$legacy=@{schema_version='2.0.0';goal='Legacy migration';tier='MEDIUM';baseline=@{commit=(Git $r @('rev-parse','HEAD'));dirty_paths=@()};scope=@('owned.txt');criteria=@('Legacy behavior');checks=@('Write-Output ok');risks=@{rollback=@{impact='HIGH';mitigation='Keep old reader'}};phases=@(@{id='old-phase';objective='Migrate safely';depends_on=@();scope=@('owned.txt');checks=@('Write-Output ok');criteria=@('Phase behavior')})}
File $r 'legacy.json' ($legacy|ConvertTo-Json -Depth 20)
$source=Join-Path $r 'legacy.json';$dest=Join-Path $r 'new.json'
$out=& (Join-Path $script:CoreRoot 'scripts/migrate-contract.ps1') -Path $source -OutputPath $dest -TaskId migration-test
Assert ($LASTEXITCODE -eq 0) 'migration creates valid new copy'
$new=Get-Content $dest -Raw|ConvertFrom-Json -AsHashtable
Assert ($new.tier -eq 'LARGE' -and $new.risks[0].impact -eq 'HIGH' -and -not $new.risks[0].resolved) 'migration retains unresolved HIGH risk and LARGE tier'
Assert ($new.phases[0].scope[0] -eq 'owned.txt' -and $new.criteria.Count -eq 2) 'migration preserves phase scope and distinct criteria'
Assert ($new.checks[0].criteria.Count -eq 0) 'migration leaves unknown check criterion mapping for manual review'
$prior=[IO.File]::ReadAllText($dest)
$out=& (Join-Path $script:CoreRoot 'scripts/migrate-contract.ps1') -Path $source -OutputPath $dest -TaskId migration-test
Assert ($LASTEXITCODE -eq 2 -and [IO.File]::ReadAllText($dest) -ceq $prior) 'existing migration output never overwritten'
$validLegacy=$legacy|ConvertTo-Json -Depth 20
$invalidInputs=@(
    @{name='unknown root field';change={param($v) $v.obsolete='ignored'}},
    @{name='invalid tier';change={param($v) $v.tier='UNKNOWN'}},
    @{name='non-string goal';change={param($v) $v.goal=42}},
    @{name='missing baseline commit';change={param($v) $v.baseline.Remove('commit')}},
    @{name='unknown baseline field';change={param($v) $v.baseline.extra=$true}},
    @{name='non-object baseline';change={param($v) $v.baseline=@()}},
    @{name='non-string baseline commit';change={param($v) $v.baseline.commit=42}},
    @{name='scalar dirty paths';change={param($v) $v.baseline.dirty_paths='owned.txt'}},
    @{name='null dirty path';change={param($v) $v.baseline.dirty_paths=@($null)}},
    @{name='empty scope';change={param($v) $v.scope=@()}},
    @{name='scalar scope';change={param($v) $v.scope='owned.txt'}},
    @{name='empty criterion';change={param($v) $v.criteria=@('')}},
    @{name='object criterion';change={param($v) $v.criteria=@(@{text='behavior'})}},
    @{name='empty checks';change={param($v) $v.checks=@()}},
    @{name='scalar checks';change={param($v) $v.checks='Write-Output ok'}},
    @{name='risk array';change={param($v) $v.risks=@(@{impact='HIGH'})}},
    @{name='null risks';change={param($v) $v.risks=$null}},
    @{name='missing risk impact';change={param($v) $v.risks.rollback.Remove('impact')}},
    @{name='invalid risk impact';change={param($v) $v.risks.rollback.impact='high'}},
    @{name='unknown risk field';change={param($v) $v.risks.rollback.extra=$true}},
    @{name='empty mitigation';change={param($v) $v.risks.rollback.mitigation=''}},
    @{name='phase object instead of array';change={param($v) $v.phases=$v.phases[0]}},
    @{name='missing phase objective';change={param($v) $v.phases[0].Remove('objective')}},
    @{name='empty phase criteria';change={param($v) $v.phases[0].criteria=@()}},
    @{name='unknown phase field';change={param($v) $v.phases[0].obsolete=$true}},
    @{name='scalar dependencies';change={param($v) $v.phases[0].depends_on='old-phase'}},
    @{name='non-string phase scope';change={param($v) $v.phases[0].scope=@(42)}},
    @{name='scalar phase checks';change={param($v) $v.phases[0].checks='Write-Output ok'}},
    @{name='duplicate phase IDs';change={param($v) $v.phases+=,$v.phases[0]}},
    @{name='unknown phase dependency';change={param($v) $v.phases[0].depends_on=@('missing')}},
    @{name='phase dependency cycle';change={param($v) $v.phases[0].depends_on=@('old-phase')}}
)
foreach($case in $invalidInputs){
    $candidate=$validLegacy|ConvertFrom-Json -AsHashtable
    & $case.change $candidate|Out-Null
    [IO.File]::WriteAllText($source,($candidate|ConvertTo-Json -Depth 20))
    Throws {Read-ControlFlowContract $source -AllowV2} ('malformed migration input rejected: '+$case.name)
}
$minimal=$validLegacy|ConvertFrom-Json -AsHashtable
$minimal.Remove('risks');$minimal.Remove('phases')
[IO.File]::WriteAllText($source,($minimal|ConvertTo-Json -Depth 20))
Assert ((Read-ControlFlowContract $source -AllowV2).legacy) 'migration accepts valid input without optional risks or phases'
$legacy.Remove('goal');[IO.File]::WriteAllText($source,($legacy|ConvertTo-Json -Depth 20))
Throws {Read-ControlFlowContract $source -AllowV2} 'legacy schema is validated before migration'
$out=& (Join-Path $script:CoreRoot 'scripts/migrate-contract.ps1') -Path $source -OutputPath (Join-Path $r 'invalid.json') -TaskId migration-test
Assert ($LASTEXITCODE -eq 2 -and -not (Test-Path (Join-Path $r 'invalid.json'))) 'invalid migration leaves no published copy'
Write-Output "contract-v3 migration total: $script:Count assertions passed"
}finally{if($r -and [IO.Path]::GetFileName($r).StartsWith('cf-core-')){RemoveFixture $r}}
$global:LASTEXITCODE=0
