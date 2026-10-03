$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$entry=Join-Path $root 'skills/controlflow/SKILL.md'
if(-not (Test-Path -LiteralPath $entry)){throw 'Missing explicit v3 entry skill'}
$text=Get-Content -LiteralPath $entry -Raw
$words=@($text -split '\s+'|Where-Object {$_}).Count
if($words -gt 250){throw "Entry exceeds progressive disclosure budget: $words words"}
foreach($needle in @('TRIVIAL','SMALL','MEDIUM','LARGE','HIGH','commit','one writer','ManualFallback','BLOCKED','execution.md')) {
    if($text -notmatch [regex]::Escape($needle)){throw "Entry lacks required behavior: $needle"}
}
$yaml=Get-Content -LiteralPath (Join-Path $root 'skills/controlflow/agents/openai.yaml') -Raw
if($yaml -notmatch 'allow_implicit_invocation: false'){throw 'Entry must be explicit only'}
if($yaml -notmatch '\$controlflow-codex:controlflow\b' -or $text -notmatch '\$controlflow-codex:<skill-name>'){throw 'Native explicit invocation must use a qualified plugin skill name'}
foreach($reference in @('execution.md','evidence.md','review.md','progress.md')) {
    $path=Join-Path $root "skills/controlflow/references/$reference"
    if(-not (Test-Path -LiteralPath $path)){throw "Missing progressive reference: $reference"}
}
$progress=Get-Content -LiteralPath (Join-Path $root 'skills/controlflow/references/progress.md') -Raw
foreach($behavior in @('update_plan','pending','in_progress','completed','accepted','resume','checks','review','stale','BLOCKED','textual','native list was not updated','completion gate')) {
    if($progress -notmatch [regex]::Escape($behavior)){throw "Native progress policy omits $behavior"}
}
if($text -notmatch 'update_plan' -or $text -notmatch 'progress.md'){throw 'Explicit entry does not reach native progress policy'}
foreach($skill in @('controlflow-plan','controlflow-verify','controlflow-review')) {
    $manualYaml=Get-Content -LiteralPath (Join-Path $root "skills/$skill/agents/openai.yaml") -Raw
    if($manualYaml -notmatch [regex]::Escape('$controlflow-codex:'+$skill)){throw "Native manual default prompt uses an unresolved short alias: $skill"}
    $manual=Get-Content -LiteralPath (Join-Path $root "skills/$skill/SKILL.md") -Raw
    if($manual -notmatch 'update_plan' -or $manual -notmatch '../controlflow/references/progress.md'){throw "Manual skill bypasses shared native progress policy: $skill"}
}
$manifest=Get-Content -LiteralPath (Join-Path $root 'plugin.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 40
foreach($prompt in $manifest.extensions.'com.openai'.interface.defaultPrompt){
    if($prompt -match '\$controlflow(?!-codex:)'){throw 'Native manifest default prompt uses an unresolved short skill alias'}
}
if(Test-Path -LiteralPath (Join-Path $root 'scripts/update-plan.ps1')){throw 'Native progress must not introduce a parallel TODO runtime'}
$hook=Get-Content -LiteralPath (Join-Path $root 'hooks/hooks.json') -Raw|ConvertFrom-Json -AsHashtable
foreach($event in @('Stop','SessionStart','Interrupt')){
    if(-not $hook.hooks.ContainsKey($event)){throw "Missing native adapter: $event"}
}
if($hook.hooks.ContainsKey('PreToolUse')){throw 'No custom commit parser or runtime interceptor belongs in v3'}
Write-Output "VALID explicit v3 entry, native progress/fallback policy and progressive references: $words entry words"
