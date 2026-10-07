param([switch]$FocusedProvenance)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $repo 'evals/e2e-lib.ps1'
if (-not (Test-Path $lib)) { throw 'ASSERT: executable E2E adapter exists (feature missing)' }
. $lib
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('controlflow-e2e-tests-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $scratch | Out-Null
$passed = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT: $Message" }
    $script:passed++
}
function Write-Utf8([string]$Path, [string]$Value) {
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}
# Actual child process using Codex exec JSONL and separate rollout records.
$fake = Join-Path $scratch 'fake-codex.ps1'
Write-Utf8 $fake @'
$ErrorActionPreference = 'Stop'
$a = @($args)
if ($a -contains '--version') { 'codex-cli 0.160.0'; exit 0 }
if ($a -contains '--dangerously-bypass-approvals-and-sandbox' -or $a -contains '--dangerously-bypass-hook-trust' -or $a -contains '--last') { throw 'unsafe argv' }
$scenario = $env:CF_EVAL_TEST_SCENARIO
if($scenario -eq 'stdin-rejected'){[Console]::Error.WriteLine('Failed to read prompt from stdin: input is not valid UTF-8 (invalid byte at offset 51). Convert it to UTF-8 and retry (e.g., `iconv -f <ENC> -t UTF-8 prompt.txt`).');exit 1}
if(($a -contains '--approve-for-me' -and $a -contains '--sandbox') -or $scenario -in @('parser-rejected','preflight-bad')){
    [Console]::Error.WriteLine("error: '--sandbox' cannot be used with '--approve-for-me'");[Console]::Error.WriteLine('Usage: codex exec [OPTIONS] [PROMPT]');exit 2
}
$stdin = [Console]::In.ReadToEnd()
$fixtureKey=([IO.Path]::GetFullPath((Get-Location).Path)|ConvertTo-Json -Compress)
if(@($a|Where-Object {$_ -match '^projects='}).Count -ne 1 -or $a -notcontains ('projects={'+$fixtureKey+'={trust_level="untrusted"}}')){[Console]::Error.WriteLine('error: fixture-only untrusted project map required');[Console]::Error.WriteLine('Usage: codex exec [OPTIONS] [PROMPT]');exit 2}
$resume = $a -contains 'resume'
$execPosition=[array]::IndexOf($a,'exec');$sandboxPosition=[array]::IndexOf($a,'--sandbox')
if($sandboxPosition -lt 0 -or $sandboxPosition -ge $execPosition){throw 'native sandbox flag must precede exec'}
$sandbox=$a[$sandboxPosition+1]
if($IsWindows -and $sandbox -eq 'workspace-write' -and $a -notcontains 'windows.sandbox="elevated"' -and $a -notcontains 'windows.sandbox="unelevated"'){$sandbox='read-only'}
$reviewer=if($a -contains 'approvals_reviewer="auto_review"'){'auto_review'}else{'user'}
$policy=if($reviewer -eq 'auto_review' -and $a -contains 'approval_policy="on-request"'){'on-request'}else{'never'}
$id = '11111111-1111-7111-8111-111111111111'
if ($resume -and ($a -notcontains $id)) { throw 'resume requires exact UUID' }
if($stdin.Length -eq 0){[Console]::Error.WriteLine('No prompt provided via stdin.');exit 1}
$log = Join-Path $env:CF_EVAL_TEST_SESSIONS ('rollout-' + $id + '.jsonl')
function Emit($obj) { $obj | ConvertTo-Json -Compress -Depth 20 }
function Log($obj) { $obj | ConvertTo-Json -Compress -Depth 20 | Add-Content -LiteralPath $log -Encoding utf8 }
if (-not $resume) { Log @{type='session_meta'; payload=@{id=$id;cwd=(Get-Location).Path;cli_version='0.160.0';model_provider='openai'}} }
Log @{type='turn_context';payload=@{model='test-model';effort='high';approval_policy=$policy;approvals_reviewer=$reviewer;sandbox_policy=@{type=$sandbox}}}
Log @{type='response_item';payload=@{type='message';role='developer';content=@(@{type='input_text';text="<skills_instructions>`n### Available skills`n- imagegen: Native built-in.`n- openai-docs: Native built-in.`n- skill-creator: Native built-in.`n- skill-installer: Native built-in.`n</skills_instructions>"})}}
if($scenario -eq 'ambient-context'){Log @{type='response_item';payload=@{type='message';role='developer';content=@(@{type='input_text';text="<skills_instructions>`n### Available skills`n- superpowers:brainstorming: Ambient extension.`n</skills_instructions>"})}}}
if($scenario -eq 'wrong-native-policy'){Log @{type='turn_context';payload=@{model='test-model';effort='high';approval_policy='never';sandbox_policy=@{type='read-only'}}}}
if($scenario -eq 'wrong-reviewer'){Log @{type='turn_context';payload=@{model='test-model';effort='high';approval_policy=$policy;approvals_reviewer='user';sandbox_policy=@{type=$sandbox}}}}
Emit @{type='thread.started';thread_id=$id}
if($scenario -eq 'api-rejected') {
    $failure=@{type='error';error=@{type='invalid_request_error';message='Invalid reasoning effort';code=$null};status=400} | ConvertTo-Json -Compress
    Emit @{type='error';message=$failure};Emit @{type='turn.failed';error=@{message=$failure}};exit 1
}
if($scenario -eq 'nonzero-after-usage') {
    Log @{type='event_msg';payload=@{type='token_count';info=@{total_token_usage=@{input_tokens=30;output_tokens=5;total_tokens=35}}}}
    Emit @{type='error';message='execution failed after generation'};exit 1
}
if ($scenario -eq 'timeout') {
    $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=(Get-Command pwsh).Source;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.ArgumentList.Add('-NoProfile');$psi.ArgumentList.Add('-Command');$psi.ArgumentList.Add('Start-Sleep -Seconds 20')
    $sleeper=[Diagnostics.Process]::Start($psi)
    [IO.File]::WriteAllText((Join-Path $env:CF_EVAL_TEST_SESSIONS 'child.pid'),[string]$sleeper.Id)
    Start-Sleep -Seconds 15; exit
}
if ($scenario -eq 'bad-json') { 'not json'; exit }
if ($scenario -eq 'wrong-session' -and $resume) { Emit @{type='thread.started';thread_id='22222222-2222-7222-8222-222222222222'} }
if ($scenario -ne 'missing-usage') {
    $tokens = if ($scenario -eq 'budget') { 99999 } else { 30 }
    $cumulative=if($resume){$tokens*2}else{$tokens};$out=if($resume){10}else{5}
    Log @{type='event_msg';payload=@{type='token_count';info=@{total_token_usage=@{input_tokens=$cumulative;output_tokens=$out;cached_input_tokens=10;total_tokens=($cumulative+$out)}}}}
    Log @{type='event_msg';payload=@{type='token_count';info=@{total_token_usage=@{input_tokens=$cumulative;output_tokens=$out;cached_input_tokens=10;total_tokens=($cumulative+$out)}}}}
    Emit @{type='turn.completed';usage=@{input_tokens=$tokens;output_tokens=5;cached_input_tokens=10}}
}
if ($scenario -eq 'child' -or $scenario -eq 'missing-child') {
    $childId = '33333333-3333-7333-8333-333333333333'
    Log @{type='response_item';payload=@{type='function_call';name='spawn_agent';call_id='spawn-1';arguments='{}'}}
    $childLog = Join-Path $env:CF_EVAL_TEST_SESSIONS ('rollout-' + $childId + '.jsonl')
    @{type='session_meta';payload=@{id=$childId;parent_thread_id=$id;cwd=(Get-Location).Path;cli_version='0.160.0'}} | ConvertTo-Json -Compress -Depth 10 | Set-Content $childLog
    if ($scenario -eq 'child') {
        @{type='event_msg';payload=@{type='token_count';info=@{total_token_usage=@{input_tokens=12;output_tokens=3;cached_input_tokens=0;total_tokens=15}}}} | ConvertTo-Json -Compress -Depth 10 | Add-Content $childLog
        @{type='event_msg';payload=@{type='task_complete'}} | ConvertTo-Json -Compress -Depth 10 | Add-Content $childLog
    }
}
if ($scenario -eq 'tool-budget') {for($i=0;$i -lt 21;$i++){Log @{type='response_item';payload=@{type='function_call';name='exec_command';call_id="tool-$i";arguments='{}'}}}}
$status = 'done'; $question = ''; $questionId = ''
if ($scenario -in @('resume','alternate-question-id','ambiguous-answer','unmatched','wrong-session') -and -not $resume) {
    $status = 'needs_clarification'; $question = if ($scenario -eq 'unmatched') { 'What should I invent?' } else { 'Which label should the document use?' }; $questionId='label'
    if($scenario -in @('alternate-question-id','ambiguous-answer')){$questionId='my-stable-label-choice'}
} elseif ($scenario -notin @('outcome-fail','budget','missing-usage','missing-child')) {
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'doc.txt'), 'expected')
}
Emit @{type='item.completed';item=@{id='final-1';type='agent_message';text=(@{status=$status;question=$question;question_id=$questionId;summary='Done; all tests pass'} | ConvertTo-Json -Compress)}}
Log @{type='event_msg';payload=@{type='task_complete'}}
exit 0
'@
try {
    $validPairProvenance=@{model='test-model';effort='max';host='test-host';fixture_hash=('a'*64);settings=@();project_trust='untrusted';sandbox='workspace-write';windows_sandbox='elevated';approval_policy='on-request';approvals_reviewer='auto_review';cli_version='0.160.0';budget=@{tokens=1000;tools=20;wall_seconds=60}}
    $provenanceRecords=@(foreach($arm in @('native','v3')){@{case_id='provenance';tier='SMALL';trial=1;variant=$arm;status='success';false_completion=$false;usage=@{complete=$true;input_tokens=90;output_tokens=10;cached_input_tokens=0;total_tokens=100;tool_calls=0};outcome=@{pass=$true;collection_complete=$true;check_count=1;planned_check_count=1;receipt=@{verified=$true;nonce='grader-receipt'}};provenance=$validPairProvenance}})
    foreach($missingField in @('model','effort','host','fixture_hash','sandbox','approval_policy','cli_version','budget','settings')){
        $missingPair=$provenanceRecords | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        foreach($r in $missingPair){$r.provenance.Remove($missingField)}
        $missingMeasurement=Measure-E2EPairs -Results $missingPair
        Assert ($missingMeasurement.incomplete_metrics_pairs -eq 1 -and $missingMeasurement.absolute_counts.native.success_count -eq 0 -and $null -eq $missingMeasurement.tiers.SMALL.native_median_tokens -and $null -eq $missingMeasurement.success_delta) "matched missing $missingField provenance is incomplete, never successful measurement"
    }
    $emptyBudgetPair=$provenanceRecords | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
    foreach($r in $emptyBudgetPair){$r.provenance.budget=@{}}
    Assert ((Measure-E2EPairs -Results $emptyBudgetPair).incomplete_metrics_pairs -eq 1) 'matched empty budgets cannot certify paired measurement'
    foreach($badProvenance in @(@{field='fixture_hash';value='same'},@{field='fixture_hash';value=''},@{field='effort';value='ultra'},@{field='settings';value=''},@{field='approval_policy';value='bypass'})){
        $badPair=$provenanceRecords | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        foreach($r in $badPair){$r.provenance[$badProvenance.field]=$badProvenance.value}
        Assert ((Measure-E2EPairs -Results $badPair).incomplete_metrics_pairs -eq 1) "invalid $($badProvenance.field) provenance cannot certify paired measurement"
    }
    foreach($badBudget in @($null,0,-1,'1000',1.5)){
        $badPair=$provenanceRecords | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        foreach($r in $badPair){$r.provenance.budget.tokens=$badBudget}
        Assert ((Measure-E2EPairs -Results $badPair).incomplete_metrics_pairs -eq 1) 'missing, nonpositive or noninteger budget fails closed'
    }
    foreach($badTrial in @($null,0,'1',1.5)){
        $badPair=$provenanceRecords | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        foreach($r in $badPair){$r.trial=$badTrial}
        $badIdentityRejected=$false;try{Measure-E2EPairs -Results $badPair | Out-Null}catch{$badIdentityRejected=$true}
        Assert $badIdentityRejected 'trial identity requires an actual positive integer'
    }
    $diagnosticPair=$provenanceRecords | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
    foreach($r in $diagnosticPair){$r.tier='CRITICAL_DIAGNOSTIC'}
    $diagnosticMeasurement=Measure-E2EPairs -Results $diagnosticPair
    Assert ($diagnosticMeasurement.paired_trials -eq 1 -and $diagnosticMeasurement.incomplete_metrics_pairs -eq 0 -and $diagnosticMeasurement.absolute_counts.native.success_count -eq 1) 'explicit critical diagnostic tier remains supported by shared validated pairing'
    foreach($legacyTrust in @($null,'trusted','')){
        $legacyPair=($provenanceRecords|ConvertTo-Json -Depth 30|ConvertFrom-Json -AsHashtable)
        foreach($record in $legacyPair){$record.provenance.project_trust=$legacyTrust}
        Assert ((Measure-E2EPairs -Results $legacyPair).incomplete_metrics_pairs -eq 1) 'legacy or granted project trust cannot certify future paired protocol'
    }
    $trustConfig=@{Model='test-model';Effort='high';Variant='native';Sandbox='workspace-write';ApprovalPolicy='on-request';ApprovalReviewer='auto_review';WindowsSandbox='elevated';CliPrefix=@();Settings=@()}
    $complexFixture=Join-Path $scratch 'Ж İstanbul.[x] repo'
    foreach($trustSession in @('','11111111-1111-7111-8111-111111111111')){
        $trustArgs=@(Get-E2EExecArguments -Config $trustConfig -Schema 'schema.json' -Session $trustSession -FixtureRoot $complexFixture)
        $wholeMap=@($trustArgs|Where-Object {$_ -match '^projects='})
        $quotedKey=([IO.Path]::GetFullPath($complexFixture)|ConvertTo-Json -Compress)
        Assert ($wholeMap.Count -eq 1 -and $wholeMap[0] -ceq ('projects={'+$quotedKey+'={trust_level="untrusted"}}')) 'initial and exact resume bind one session-only untrusted fixture with Unicode, dots and spaces'
        Assert (@($trustArgs|Where-Object {$_ -match '^projects\.' -or $_ -match 'trust_level="trusted"'}).Count -eq 0) 'no dotted path ambiguity or trusted grant enters native argv'
    }
    $missingFixtureRejected=$false;try{Get-E2EExecArguments -Config $trustConfig -Schema 'schema.json'|Out-Null}catch{$missingFixtureRejected=$true}
    Assert $missingFixtureRejected 'missing fixture trust scope rejects before startup'
    $marketplaceRoot=Join-Path $scratch 'isolated/candidate'
    $candidatePluginPath=Join-Path $marketplaceRoot 'plugins/controlflow-codex'
    $namedMarket=@{Model='test-model';Effort='max';Variant='v3';ApprovalPolicy='on-request';ApprovalReviewer='auto_review';Sandbox='workspace-write';WindowsSandbox='elevated';Settings=@();MarketplaceRoot=$marketplaceRoot;MarketplaceName='controlflow-eval-unique-test';CliPrefix=@()}
    $namedArgs=@(Get-E2EConfigArguments $namedMarket)
    foreach($ambient in @('pages','plugin-management','sites','superpowers','work-pets')){
        Assert ($namedArgs -contains ('plugins.'+$ambient+'@openai-curated-remote.enabled=false')) 'session overrides explicitly disable observed ambient native plugin identities'
    }
    Assert ($namedArgs -contains 'plugins.controlflow-codex@controlflow-eval-unique-test.enabled=true' -and $namedArgs -notcontains 'plugins."controlflow-codex@controlflow-eval-unique-test".enabled=true') 'native CLI override path uses bare plugin identity, rather than a literal quoted key'
    $marketplaceSourceArgument='marketplaces.controlflow-eval-unique-test.source='+($marketplaceRoot.Replace('\','/') | ConvertTo-Json -Compress)
    Assert ($namedArgs -contains 'marketplaces.controlflow-eval-unique-test.source_type="local"' -and $namedArgs -contains $marketplaceSourceArgument) 'explicit named marketplace source and local type stay independent arguments'
    $namedDiscovery=@(Get-E2EDiscoveryArguments $namedMarket);$filterIndex=[array]::IndexOf($namedDiscovery,'--marketplace')
    Assert ($filterIndex -ge 0 -and $namedDiscovery[$filterIndex+1] -ceq $namedMarket.MarketplaceName) 'native discovery filters the same explicit marketplace identity'
    $discoveryCapture=@{exit_code=0;timed_out=$false;streams_complete=$true;cleanup_verified=$true;stdout=(@{installed=@();available=@(@{pluginId='controlflow-codex@controlflow-eval-unique-test';marketplaceName='controlflow-eval-unique-test';installed=$false;enabled=$false;source=@{source='local';path=$candidatePluginPath}})} | ConvertTo-Json -Depth 8)}
    Assert (-not (Test-E2EPluginDiscovery -Capture $discoveryCapture -Config $namedMarket).verified) 'available but uninstalled v3 plugin fails no-model preflight'
    $namedMarket.Variant='native'
    Assert (Test-E2EPluginDiscovery -Capture $discoveryCapture -Config $namedMarket).verified 'native inactive snapshot passes no-model preflight'
    $namedMarket.Variant='v3';$activeRecord=@{pluginId='controlflow-codex@controlflow-eval-unique-test';marketplaceName='controlflow-eval-unique-test';installed=$true;enabled=$true;source=@{source='local';path=$candidatePluginPath}}
    $discoveryCapture.stdout=@{installed=@($activeRecord);available=@()} | ConvertTo-Json -Depth 8
    Assert (Test-E2EPluginDiscovery -Capture $discoveryCapture -Config $namedMarket).verified 'explicit installed and enabled local v3 identity passes no-model preflight'
    $activeRecord.source.path=Join-Path $scratch 'another/source';$discoveryCapture.stdout=@{installed=@($activeRecord);available=@()} | ConvertTo-Json -Depth 8
    Assert (-not (Test-E2EPluginDiscovery -Capture $discoveryCapture -Config $namedMarket).verified) 'mismatched discovery source cannot certify candidate identity'
    $inventoryFirst=@([ordered]@{path='skills/entry/SKILL.md';sha256=('a'*64)},[ordered]@{path='plugin.json';sha256=('b'*64)})
    $inventoryOther=@([ordered]@{sha256=('B'*64);path='plugin.json'},[ordered]@{sha256=('A'*64);path='skills\entry\SKILL.md'})
    $canonicalDigest=Get-E2EPluginDigest -Inventory $inventoryFirst
    Assert ($canonicalDigest -ceq (Get-E2EPluginDigest -Inventory $inventoryOther)) 'plugin digest is canonical across key/file order, separators and hash letter case'
    $inventoryOther[0].sha256='c'*64
    Assert ($canonicalDigest -cne (Get-E2EPluginDigest -Inventory $inventoryOther)) 'plugin digest changes when actual file bytes change'
    $entryPath=Join-Path $scratch 'owned-cache/skills/controlflow/SKILL.md';$entryBody="---`nname: controlflow`n---`nEntry rules.`n"
    $entryFragment="<skill>`n<name>controlflow-codex:controlflow</name>`n<path>$entryPath</path>`n$entryBody`n</skill>"
    Assert (Test-E2ENativeSkillInjection -Text $entryFragment -ExpectedPath $entryPath -ExpectedContents $entryBody).verified 'native hidden qualified skill injection verifies exact path and full SDK body'
    Assert (-not (Test-E2ENativeSkillInjection -Text ($entryFragment.Replace('Entry rules.','Altered rules.')) -ExpectedPath $entryPath -ExpectedContents $entryBody).verified) 'injected entry contents cannot differ from immutable snapshot'
    Assert (-not (Test-E2ENativeSkillInjection -Text ($entryFragment.Replace($entryPath,(Join-Path $scratch 'foreign/SKILL.md'))) -ExpectedPath $entryPath -ExpectedContents $entryBody).verified) 'same skill body from foreign native path fails proof'
    Assert (-not (Test-E2ENativeSkillInjection -Text ($entryFragment.Replace('controlflow-codex:controlflow','controlflow')) -ExpectedPath $entryPath -ExpectedContents $entryBody).verified) 'unqualified SDK skill identity cannot certify plugin treatment'
    Assert ((Get-E2ETrialPrompt -Case @{task='Frozen task'} -Variant v3).StartsWith('$controlflow-codex:controlflow Frozen task')) 'v3 selects native namespaced entry explicitly'
    Assert ((Get-E2ETrialPrompt -Case @{task='Frozen task'} -Variant native).StartsWith('Frozen task')) 'native keeps identical frozen task without plugin invocation'
    $entrySessions=Join-Path $scratch 'entry-sessions';[IO.Directory]::CreateDirectory($entrySessions)|Out-Null
    $entryId='55555555-5555-7555-8555-555555555555';$entryRollout=Join-Path $entrySessions 'entry.jsonl'
    $entryRows=@(@{type='session_meta';payload=@{id=$entryId;cwd=$scratch;cli_version='0.160.0'}},@{type='turn_context';payload=@{model='test-model';effort='high';approval_policy='never';approvals_reviewer='user';sandbox_policy=@{type='read-only'}}},@{type='response_item';payload=@{type='message';role='developer';content=@(@{text="### Available skills`n- imagegen: built-in`n- openai-docs: built-in`n- skill-creator: built-in`n- skill-installer: built-in"})}})
    Write-Utf8 $entryRollout (($entryRows|ForEach-Object {($_|ConvertTo-Json -Compress -Depth 20)+"`n"}) -join '')
    $entryArgs=@{SessionRoot=$entrySessions;RootSession=$entryId;FixtureRoot=$scratch;Since=[datetime]::UtcNow.AddSeconds(-2);Variant='v3';ExpectedEntryPath=$entryPath;ExpectedEntryContents=$entryBody}
    $entryUsage=Get-E2EUsage @entryArgs
    Assert ($entryUsage.actual_context.entry_injection_pending -and -not $entryUsage.actual_context.verified) 'startup catalog alone remains pending and cannot prove hidden native entry'
    Add-Content -LiteralPath $entryRollout -Encoding utf8 -Value (@{type='response_item';payload=@{type='message';role='user';content=@(@{text=$entryFragment})}}|ConvertTo-Json -Compress -Depth 20)
    $entryUsage=Get-E2EUsage @entryArgs
    Assert ($entryUsage.actual_context.verified -and $entryUsage.actual_context.entry_injection.verified -and -not $entryUsage.actual_context.entry_injection_pending) 'hidden native entry verifies from SDK user fragment despite four builtin catalog entries'
    $entryArgs.Variant='native';$entryUsage=Get-E2EUsage @entryArgs
    Assert ($entryUsage.actual_context.failures -contains 'unexpected-native-skill-injection') 'native arm rejects selected plugin entry even when catalog omits it'
    $entryArgs.Variant='v3';Write-Utf8 $entryRollout (($entryRows|ForEach-Object {($_|ConvertTo-Json -Compress -Depth 20)+"`n"}) -join '')
    Add-Content -LiteralPath $entryRollout -Encoding utf8 -Value (@{type='response_item';payload=@{type='message';role='assistant';content=@(@{text='Model reply without selected entry'})}}|ConvertTo-Json -Compress -Depth 20)
    $entryUsage=Get-E2EUsage @entryArgs
    Assert (-not $entryUsage.actual_context.entry_injection_pending -and -not $entryUsage.actual_context.verified) 'sampling without selected entry is a definite mismatch and final incomplete'
    if($FocusedProvenance){Write-Output "VALID focused E2E provenance tests: $passed assertions";return}
    $strictReader=Join-Path $scratch 'strict-utf8-stdin.ps1'
    Write-Utf8 $strictReader @'
$raw=[IO.MemoryStream]::new();[Console]::OpenStandardInput().CopyTo($raw);$bytes=$raw.ToArray()
if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){throw 'Unexpected stdin BOM'}
$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
if($text -cne $env:CF_EVAL_EXPECTED_UNICODE){throw 'Unicode stdin changed'}
[Console]::WriteLine('strict UTF-8 exact')
'@
    foreach($transportSession in @('','11111111-1111-7111-8111-111111111111')){
        $unicodePrompt="Привет, ёж! İstanbul, ı, ş, ç. 日本語🙂`n"+$(if($transportSession){'Resume answer: İЯ'}else{'Initial prompt: Жğ'})
        $transport=Invoke-E2EProcess -Executable (Get-Command pwsh).Source -Arguments (@('-NoProfile','-File',$strictReader)+$(if($transportSession){@('exec','resume',$transportSession,'-')}else{@('exec','-')})) -WorkingDirectory $scratch -TimeoutSeconds 5 -InputText $unicodePrompt -Environment @{CF_EVAL_EXPECTED_UNICODE=$unicodePrompt}
        Assert ($transport.exit_code -eq 0 -and $transport.stdout.Trim() -ceq 'strict UTF-8 exact' -and $transport.streams_complete -and $transport.cleanup_verified) "raw stdin uses strict UTF-8 without BOM, including resume: $($transport.stderr)"
    }
    $liveSessions=Join-Path $scratch 'live-sessions';$liveFixture=Join-Path $scratch 'live-fixture';[IO.Directory]::CreateDirectory($liveSessions) | Out-Null;[IO.Directory]::CreateDirectory($liveFixture) | Out-Null
    $liveId='44444444-4444-7444-8444-444444444444';$livePath=Join-Path $liveSessions 'live.jsonl'
    $heldFile=[IO.FileStream]::new($livePath,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $heldWriter=[IO.StreamWriter]::new($heldFile,[Text.UTF8Encoding]::new($false));$heldWriter.AutoFlush=$true
    try{
        foreach($row in @(@{type='session_meta';payload=@{id=$liveId;cwd=$liveFixture;cli_version='0.160.0'}},@{type='turn_context';payload=@{model='test-model';effort='high';approval_policy='on-request';approvals_reviewer='auto_review';sandbox_policy=@{type='read-only'}}},@{type='response_item';payload=@{type='message';role='developer';content=@(@{text="### Available skills`n- imagegen: built-in`n- openai-docs: built-in`n- skill-creator: built-in`n- skill-installer: built-in"})}},@{type='event_msg';payload=@{type='token_count';info=@{total_token_usage=@{input_tokens=30;output_tokens=5;cached_input_tokens=10;total_tokens=35}}}})){$heldWriter.WriteLine(($row | ConvertTo-Json -Compress -Depth 20))}
        $heldWriter.Write('{"type":"unfinished')
        $liveUsage=Get-E2EUsage -SessionRoot $liveSessions -RootSession $liveId -FixtureRoot $liveFixture -Since ([datetime]::UtcNow.AddSeconds(-2)) -Model test-model -Effort high -ExpectedApproval on-request -ExpectedReviewer auto_review -ExpectedSandbox workspace-write
        Assert ($liveUsage.actual_context.failures -contains 'sandbox-policy' -and $liveUsage.actual_context.catalog_present) 'live locked rollout exposes definite policy mismatch before writer exits'
        Assert (-not $liveUsage.complete -and $liveUsage.total_tokens -eq 35) 'unterminated append tail never certifies complete usage or erases published spend'
    }finally{$heldWriter.Dispose();$heldFile.Dispose()}
    $policyConfig=@{Model='test-model';Effort='high';Variant='native';ApprovalPolicy='on-request';ApprovalReviewer='auto_review';Sandbox='workspace-write';WindowsSandbox='elevated';Settings=@();CliPrefix=@()}
    Assert (@(Get-E2EConfigArguments $policyConfig) -contains 'windows.sandbox="elevated"') 'isolated native config preserves explicitly chosen Windows sandbox implementation'
    if($IsWindows){
        $missingPlatform=$policyConfig.Clone();$missingPlatform.Remove('WindowsSandbox');$platformRejected=$false
        try{Get-E2EExecArguments -Config $missingPlatform -Schema 'schema.json' -FixtureRoot $scratch | Out-Null}catch{$platformRejected=$true}
        Assert $platformRejected 'Windows workspace-write without implementation rejects before read-only downgrade or generation'
    }
    if(-not (Get-Command Get-E2EExecArguments -ErrorAction SilentlyContinue)){throw 'ASSERT: native headless policy argv builder exists'}
    foreach($session in @('','11111111-1111-7111-8111-111111111111')){
        $nativeArgs=@(Get-E2EExecArguments -Config $policyConfig -Schema 'response-schema.json' -Session $session -FixtureRoot $scratch)
        $execPosition=[array]::IndexOf($nativeArgs,'exec');$sandboxPosition=[array]::IndexOf($nativeArgs,'--sandbox')
        Assert ($sandboxPosition -ge 0 -and $sandboxPosition -lt $execPosition -and $nativeArgs[$sandboxPosition+1] -eq 'workspace-write') 'sandbox native flag precedes exec including exact UUID resume'
        Assert ($nativeArgs -notcontains '--approve-for-me' -and $nativeArgs -contains 'approvals_reviewer="auto_review"' -and $nativeArgs -contains 'approval_policy="on-request"') 'explicit auto reviewer uses resolved native config without conflicting shorthand flag'
        if($session){Assert ($nativeArgs[$execPosition+1] -eq 'resume' -and $nativeArgs[$execPosition+2] -eq $session) 'global native flags retain exact resume identity'}
    }
    $policyConfig.ApprovalReviewer='user';$rejectedPolicy=$false
    try{Get-E2EExecArguments -Config $policyConfig -Schema 'schema.json' -FixtureRoot $scratch | Out-Null}catch{$rejectedPolicy=$true}
    Assert $rejectedPolicy 'headless on-request user approval rejected before generation'
    $policyConfig.ApprovalPolicy='never';$policyConfig.Sandbox='read-only'
    $bounded=@(Get-E2EExecArguments -Config $policyConfig -Schema 'schema.json' -FixtureRoot $scratch)
    Assert ($bounded -notcontains '--approve-for-me' -and $bounded -contains 'read-only') 'bounded never/user policy does not enable automatic review'
    $policyConfig.ApprovalPolicy='on-request';$policyConfig.ApprovalReviewer='auto_review';$rejectedPolicy=$false
    try{Get-E2EExecArguments -Config $policyConfig -Schema 'schema.json' -FixtureRoot $scratch | Out-Null}catch{$rejectedPolicy=$true}
    Assert $rejectedPolicy 'automatic review cannot silently widen an explicitly read-only sandbox'
    $securityCase=@(Get-E2ECases -RepoRoot $repo -Suite Release | Where-Object {$_.oracle -and $_.protected})[0]
    $securityFixture=New-E2EFixture -Case $securityCase -Directory (Join-Path $scratch 'grader-exit')
    Set-E2EReferenceOutcome -Case $securityCase -Fixture $securityFixture
    Write-Utf8 (Join-Path $securityFixture.root 'src/operations.ps1') 'exit 0'
    $early=Test-E2EOutcome -Case $securityCase -Fixture $securityFixture
    Assert (-not $early.pass -and -not $early.collection_complete) 'source exit zero cannot certify unexecuted hidden assertions'
    Set-E2EReferenceOutcome -Case $securityCase -Fixture $securityFixture
    $genuine=Test-E2EOutcome -Case $securityCase -Fixture $securityFixture
    Assert ($genuine.pass -and $genuine.collection_complete -and $genuine.check_count -gt 0 -and $genuine.receipt.nonce) 'genuine repair collects positive grader completion receipt'
    $foreign=@($securityFixture.protected.Keys)[0]
    $source=[IO.File]::ReadAllText((Join-Path $securityFixture.root 'src/operations.ps1'))
    $runtimeWrite="param(`$Value) [IO.File]::WriteAllText('"+$foreign.Replace("'","''")+"','clobbered');"
    Write-Utf8 (Join-Path $securityFixture.root 'src/operations.ps1') ($source.Replace('param($Value)',$runtimeWrite))
    $corrupt=Test-E2EOutcome -Case $securityCase -Fixture $securityFixture
    Assert (-not $corrupt.pass -and ($corrupt.failures -contains "foreign-content:$foreign")) 'final protected files observed after executing model source'
    $inheritScript=Join-Path $scratch 'inherit.ps1';$inheritPid=Join-Path $scratch 'inherit.pid'
    Write-Utf8 $inheritScript @'
$p=[Diagnostics.ProcessStartInfo]::new();$p.FileName=(Get-Command pwsh).Source;$p.UseShellExecute=$false;$p.CreateNoWindow=$true
$p.ArgumentList.Add('-NoProfile');$p.ArgumentList.Add('-Command');$p.ArgumentList.Add('Start-Sleep -Seconds 4; "late child"')
$child=[Diagnostics.Process]::Start($p);[IO.File]::WriteAllText($args[0],[string]$child.Id);exit 0
'@
    $inherited=Invoke-E2EProcess -Executable (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',$inheritScript,$inheritPid) -WorkingDirectory $scratch -TimeoutSeconds 1
    Assert ($inherited.timed_out -and $inherited.wall_ms -lt 2500) 'deadline bounds inherited streams after parent exits'
    $ownedChild=[int][IO.File]::ReadAllText($inheritPid)
    Assert (-not (Get-Process -Id $ownedChild -ErrorAction SilentlyContinue)) 'owned descendant terminated after parent exits'
    $case = @{id='adapter-case';tier='SMALL';task='Set doc.txt to expected.';factory='declarative';files=@{'doc.txt'='initial'};expected=@{'doc.txt'='expected'};oracle='';commit='none';answers=@{label=@{pattern='Which label should the document use\?';answer='Use expected.'}}}
    $config = @{Model='test-model';Effort='high';HostLabel='test-host';ExpectedCliVersion='0.160.0';CliPath=(Get-Command pwsh).Source;CliPrefix=@('-NoProfile','-File',$fake);MaxTokens=1000;MaxToolCalls=20;MaxWallSeconds=10;MaxResumes=2;ApprovalPolicy='on-request';ApprovalReviewer='auto_review';Sandbox='workspace-write';WindowsSandbox='elevated';Variant='native';PluginRoot=$repo;Settings=@();SessionRoot='';Environment=@{}}
    $overrides=@(Get-E2EConfigArguments $config)
    $preflight=Invoke-E2EPolicyPreflight -Config $config -Directory (Join-Path $scratch 'preflight-valid')
    Assert ($preflight.verified -and $preflight.checks.Count -eq 2 -and $preflight.checks[1].session_id -eq '11111111-1111-7111-8111-111111111111') 'exact initial and resume argv reach the genuine empty stdin guard before generation'
    Assert (-not (Test-Path (Join-Path $scratch 'preflight-valid/rollout-*.jsonl'))) 'empty stdin preflight creates no fake model rollout'
    $config.Environment=@{CF_EVAL_TEST_SCENARIO='preflight-bad'}
    $badPreflight=Invoke-E2EPolicyPreflight -Config $config -Directory (Join-Path $scratch 'preflight-invalid')
    Assert (-not $badPreflight.verified -and $badPreflight.checks[0].exit_code -eq 2) 'CLI parser errors cannot pass empty stdin preflight'
    $config.Environment=@{}
    foreach($pair in @('model_reasoning_effort="high"','approval_policy="on-request"','approvals_reviewer="auto_review"','sandbox_mode="workspace-write"','windows.sandbox="elevated"')){
        Assert (@($overrides | Where-Object {$_ -ceq $pair}).Count -eq 1) "CLI override is a separate exact argv element: $pair"
        $position=[array]::IndexOf($overrides,$pair);Assert ($position -gt 0 -and $overrides[$position-1] -ceq '-c') "CLI override has its own -c: $pair"
    }
    if(-not (Get-Command Get-E2EDiscoveryArguments -ErrorAction SilentlyContinue)){throw 'ASSERT: focused marketplace discovery argument builder exists'}
    $discoveryArgs=@(Get-E2EDiscoveryArguments $config)
    $marketplacePosition=[array]::IndexOf($discoveryArgs,'--marketplace')
    Assert ($marketplacePosition -ge 0 -and $discoveryArgs[$marketplacePosition+1] -ceq 'controlflow-eval') 'discovery filters the isolated marketplace instead of expanding global remote catalogs'
    foreach ($scenario in @('success','outcome-fail','missing-usage','timeout','resume','alternate-question-id','ambiguous-answer','unmatched','wrong-session','child','missing-child','budget','tool-budget','bad-json','api-rejected','parser-rejected','stdin-rejected','nonzero-after-usage','ambient-context','wrong-native-policy','wrong-reviewer')) {
        $dir = Join-Path $scratch $scenario
        $sessions = Join-Path $dir 'sessions'
        New-Item -ItemType Directory -Path $sessions -Force | Out-Null
        $config.SessionRoot=$sessions
        $config.MaxWallSeconds=if($scenario -eq 'timeout'){5}else{10}
        $config.Environment=@{CF_EVAL_TEST_SCENARIO=$scenario;CF_EVAL_TEST_SESSIONS=$sessions}
        if($scenario -eq 'ambiguous-answer'){$case.answers.other=@{pattern='Which label.*';answer='An independently configured different answer.'}}
        $result = Invoke-E2ETrial -Case $case -Config $config -TrialDirectory $dir
        if($scenario -eq 'ambiguous-answer'){$case.answers.Remove('other')}
        switch ($scenario) {
            success {
                Assert ($result.status -eq 'success') "actual process and content grader success: $($result.reason)"; Assert ($result.usage.total_tokens -eq 35) 'cumulative snapshots count once and cached input is subset'
                Assert ($result.usage.actual_context.verified -and $result.usage.actual_context.skill_names.Count -eq 4) 'actual exec rollout, rather than differently loaded debug prompt, verifies context isolation'
            }
            outcome-fail { Assert ($result.status -eq 'failed') 'plausible done rejected by actual repository grader' }
            missing-usage { Assert ($result.status -eq 'incomplete') 'missing root usage is incomplete' }
            timeout {
                Assert ($result.status -eq 'incomplete' -and $result.reason -match 'timeout') 'process timeout bounded and incomplete'
                $pidFile=Join-Path $sessions 'child.pid';Assert (Test-Path $pidFile) 'timeout fixture spawned actual child'
                $alive=$false;try{$p=[Diagnostics.Process]::GetProcessById([int](Get-Content $pidFile));$alive=-not $p.HasExited;$p.Dispose()}catch{}
                Assert (-not $alive) 'timeout kills process tree, including actual grandchild'
            }
            resume { Assert ($result.status -eq 'success' -and $result.resumes -eq 1 -and $result.usage.total_tokens -eq 70) 'exact session resume uses latest cumulative usage once across turns' }
            alternate-question-id { Assert ($result.status -eq 'success' -and $result.resumes -eq 1) 'unique predeclared regex answers actual question without guessing hidden ID' }
            ambiguous-answer { Assert ($result.status -eq 'incomplete' -and $result.reason -match 'clarification') 'multiple matching predeclared answers remain incomplete' }
            unmatched { Assert ($result.status -eq 'incomplete' -and $result.reason -match 'clarification') 'unmatched question never gets invented answer' }
            wrong-session { Assert ($result.status -eq 'incomplete') 'resume session mismatch rejected' }
            child { Assert ($result.status -eq 'success' -and $result.usage.total_tokens -eq 50 -and $result.usage.sessions.Count -eq 2) "root and child counted once: $($result.reason), $($result.usage.total_tokens)" }
            missing-child { Assert ($result.status -eq 'incomplete') 'missing child usage is incomplete' }
            budget { Assert ($result.status -eq 'incomplete' -and $result.reason -match 'budget') 'strict token budget stops success' }
            tool-budget { Assert ($result.status -eq 'incomplete' -and $result.reason -match 'budget') 'strict observed tool budget stops success' }
            bad-json { Assert ($result.status -eq 'incomplete') 'protocol corruption incomplete' }
            api-rejected {
                Assert ($result.status -eq 'incomplete' -and $result.api_rejected_before_generation -and -not $result.generation_started) 'structured invalid-request400 before any items is a rejected attempt, not a model trial'
                Assert ($result.session_id -eq '11111111-1111-7111-8111-111111111111' -and $null -ne $result.usage -and -not $result.usage.complete) 'API reject preserves trusted session and honest missing telemetry'
            }
            parser-rejected {
                Assert ($result.configuration_rejected_before_generation -and -not $result.generation_started -and -not $result.api_rejected_before_generation -and $result.spend_status -eq 'not-generated-cli-parser-rejection') 'native parser exit2 before any events is a rejected configuration with no generation'
                Assert ($null -eq $result.session_id -and $null -eq $result.usage) 'parser rejection does not invent session or usage telemetry'
                $parserRejectedResult=$result
            }
            stdin-rejected {
                Assert ($result.configuration_rejected_before_generation -and -not $result.generation_started -and $result.spend_status -eq 'not-generated-cli-stdin-rejection' -and $null -eq $result.session_id -and $null -eq $result.usage) 'exact native UTF8 input guard before any events is a configuration rejection without generation'
                $stdinRejectedResult=$result
            }
            nonzero-after-usage {
                Assert ($result.status -eq 'incomplete' -and -not $result.api_rejected_before_generation -and $result.usage.total_tokens -eq 35) 'nonzero process after generation retains actual spend'
                Assert ($result.session_id -eq '11111111-1111-7111-8111-111111111111') 'nonzero exit retains trusted native session id'
                Assert (-not $result.usage.complete) 'aborted native turn cannot assert final usage accounting complete'
            }
            ambient-context {Assert ($result.status -eq 'incomplete' -and $result.reason -match 'context|ambient') 'actual exec catalog contamination cannot become success'}
            wrong-native-policy {Assert ($result.status -eq 'incomplete' -and $result.reason -match 'policy|sandbox') 'actual native policy must match separately passed overrides'}
            wrong-reviewer {Assert ($result.status -eq 'incomplete' -and $result.reason -match 'reviewer') 'actual native approvals reviewer must match declared policy'}
        }
        Assert (Test-Path (Join-Path $dir 'result.json')) 'separate result persisted'
        Assert (Test-Path (Join-Path $dir 'raw/turn-0.jsonl')) 'raw JSONL retained'
        $versionReceipt=Get-Content -LiteralPath (Join-Path $dir 'raw/version.process.json') -Raw|ConvertFrom-Json
        $turnReceipt=Get-Content -LiteralPath (Join-Path $dir 'raw/turn-0.process.json') -Raw|ConvertFrom-Json
        Assert ($versionReceipt.cleanup_verified -and $turnReceipt.cleanup_verified -and $turnReceipt.exit_code -is [long]) 'actual owned version and turn cleanup receipts persist, including failures'
        Assert ($result.provenance.project_trust -ceq 'untrusted') 'actual process result declares required future trust protocol'
    }
    $config.ApprovalReviewer='user'
    $unsupported=Invoke-E2ETrial -Case $case -Config $config -TrialDirectory (Join-Path $scratch 'unsupported-user-approval')
    Assert ($unsupported.status -eq 'incomplete' -and $unsupported.reason -match 'Headless' -and -not (Test-Path (Join-Path $scratch 'unsupported-user-approval/raw'))) 'unsupported user approval starts no generation process'
    $boundedDir=Join-Path $scratch 'bounded-user';$boundedSessions=Join-Path $boundedDir 'sessions';[IO.Directory]::CreateDirectory($boundedSessions) | Out-Null
    $config.ApprovalPolicy='never';$config.SessionRoot=$boundedSessions;$config.Environment=@{CF_EVAL_TEST_SCENARIO='success';CF_EVAL_TEST_SESSIONS=$boundedSessions}
    $boundedResult=Invoke-E2ETrial -Case $case -Config $config -TrialDirectory $boundedDir
    Assert ($boundedResult.status -eq 'success' -and $boundedResult.usage.actual_context.approvals_reviewer -eq 'user' -and $boundedResult.usage.actual_context.approval_policy -eq 'never') 'bounded user never policy is verified from actual process rollout'
    $config.ApprovalReviewer='auto_review';$config.ApprovalPolicy='on-request'
    $diagnosticCase=@(Get-E2EReleaseDiagnosticCases)[0];$diagnosticDir=Join-Path $scratch 'diagnostic-no-artifact';$diagnosticSessions=Join-Path $diagnosticDir 'sessions';[IO.Directory]::CreateDirectory($diagnosticSessions) | Out-Null
    $config.SessionRoot=$diagnosticSessions;$config.Environment=@{CF_EVAL_TEST_SCENARIO='success';CF_EVAL_TEST_SESSIONS=$diagnosticSessions}
    $diagnosticResult=Invoke-E2ETrial -Case $diagnosticCase -Config $config -TrialDirectory $diagnosticDir
    $diagnosticResult=Set-E2EDiagnosticCollectionResult -Result $diagnosticResult -Case $diagnosticCase -Fixture @{root=(Join-Path $diagnosticDir 'repo')}
    Assert ($diagnosticResult.status -eq 'incomplete' -and -not $diagnosticResult.risk_diagnostics.collection_complete -and $diagnosticResult.false_completion -and $diagnosticResult.usage.total_tokens -eq 35) 'actual fake done without diagnostics cannot become summary success and retains observed usage'
    $config.ExpectedCliVersion='0.159.0'
    $mismatch = Invoke-E2ETrial -Case $case -Config $config -TrialDirectory (Join-Path $scratch 'version')
    Assert ($mismatch.status -eq 'incomplete' -and $mismatch.reason -match 'version') 'CLI version mismatch rejects before run'
    $config.ExpectedCliVersion='0.160.0';$config.MaxTokens=0
    $noBudget=Invoke-E2ETrial -Case $case -Config $config -TrialDirectory (Join-Path $scratch 'no-budget')
    Assert ($noBudget.status -eq 'incomplete' -and $noBudget.reason -match 'budget') 'absent positive token budget rejected before execution'
    Assert (-not (Test-Path (Join-Path $scratch 'no-budget/raw'))) 'invalid budget performs no model process'
    $homeRejected=$false;try{Invoke-E2EProcess -Executable (Get-Command pwsh).Source -Arguments @('-NoProfile','-Command','exit 0') -WorkingDirectory $scratch -TimeoutSeconds 2 -Environment @{CODEX_HOME='another'} | Out-Null}catch{$homeRejected=$true}
    Assert $homeRejected 'process adapter forbids auth/home identity overrides'
    $catalog = @(Get-E2ECases -RepoRoot $repo -Suite Release)
    Assert ($catalog.Count -eq 55) '55 release cases'
    foreach ($tier in @(@('TRIVIAL',5),@('SMALL',10),@('MEDIUM',15),@('LARGE',10),@('TRAP',15))) {
        Assert (@($catalog | Where-Object tier -eq $tier[0]).Count -eq $tier[1]) "release tier $($tier[0]) count"
    }
    Assert (@(Get-E2ECases -RepoRoot $repo -Suite Pilot).Count -eq 12) '12 pilot cases'
    foreach ($c in $catalog) {
        $fixture = New-E2EFixture -Case $c -Directory (Join-Path $scratch ('catalog-' + $c.id))
        Assert (-not (Test-E2EOutcome -Case $c -Fixture $fixture).pass) "initial fixture requires work: $($c.id)"
        Set-E2EReferenceOutcome -Case $c -Fixture $fixture
        $repaired = Test-E2EOutcome -Case $c -Fixture $fixture
        Assert $repaired.pass "reference repair satisfies hidden oracle: $($c.id) $($repaired.failures -join ',')"
    }
    $boundaryResults=[Collections.Generic.List[object]]::new()
    $config.MaxTokens=1000
    foreach($number in 1..5){
        $boundaryDir=Join-Path $scratch ('boundary-'+$number);$boundarySessions=Join-Path $boundaryDir 'sessions'
        [IO.Directory]::CreateDirectory($boundarySessions) | Out-Null
        $config.SessionRoot=$boundarySessions;$config.Environment=@{CF_EVAL_TEST_SCENARIO=if($number -eq 5){'api-rejected'}else{'success'};CF_EVAL_TEST_SESSIONS=$boundarySessions}
        $boundaryResults.Add((Invoke-E2ETrial -Case $case -Config $config -TrialDirectory $boundaryDir))
    }
    $boundary=Measure-E2EArmCounts -Results $boundaryResults.ToArray() -RequestedCount 5
    Assert ($boundaryResults[3].status -eq 'success' -and $boundaryResults[4].api_rejected_before_generation -and $boundary.run_count -eq 4 -and $boundary.unrun_count -eq 1) 'actual four completed processes plus final rejected API process cannot consume all five requested model trials'
    $boundaryResults.Add($parserRejectedResult)
    $boundary=Measure-E2EArmCounts -Results $boundaryResults.ToArray() -RequestedCount 6
    Assert ($boundary.run_count -eq 4 -and $boundary.unrun_count -eq 2 -and $boundary.rejected_attempt_count -eq 2 -and $boundary.configuration_rejected_attempt_count -eq 1) 'CLI parser rejection also leaves requested model trial unrun'
    $paired=[Collections.Generic.List[object]]::new()
    for($i=1;$i -le 3;$i++){
        foreach($arm in @('native','v3')){$paired.Add(@{case_id='paired';tier='SMALL';trial=$i;variant=$arm;status='success';false_completion=$false;outcome=@{pass=$true;collection_complete=$true;check_count=1;planned_check_count=1;receipt=@{verified=$true;nonce='grader-receipt'}};usage=@{complete=$true;input_tokens=90;output_tokens=10;cached_input_tokens=0;total_tokens=100;tool_calls=0};provenance=@{model='m';effort='high';host='h';fixture_hash=('a'*64);settings=@();project_trust='untrusted';sandbox='workspace-write';approval_policy='on-request';approvals_reviewer='auto_review';cli_version='0.160.0';budget=@{tokens=1000;tools=20;wall_seconds=60}}})}
    }
    $comparison=Measure-E2EPairs -Results $paired.ToArray()
    Assert ($comparison.paired_trials -eq 3 -and $comparison.fixture_clusters -eq 1) 'exact fixture/trial paired aggregation'
    Assert ($null -eq $comparison.false_completion_relative_reduction) 'zero baseline has no invented relative reduction'
    Assert ($comparison.success_delta -eq 0 -and $comparison.tiers.SMALL.median_token_overhead -eq 0) 'paired success and token deltas measured'
    $malformed=@($paired[0],$paired[1]) | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
    foreach($r in $malformed){$r.usage=@{complete=$true};$r.Remove('outcome')}
    $invalid=Measure-E2EPairs -Results $malformed
    Assert ($invalid.incomplete_metrics_pairs -eq 1 -and $invalid.absolute_counts.native.success_count -eq 0 -and $null -eq $invalid.tiers.SMALL.native_median_tokens) 'missing metrics and positive grading evidence cannot become successful zero-token pairs'
    $contradiction=@($paired[0],$paired[1]) | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
    $contradiction[0].outcome.pass=$false
    $invalid=Measure-E2EPairs -Results $contradiction
    Assert ($invalid.absolute_counts.native.success_count -eq 0 -and $invalid.absolute_counts.native.incomplete_count -eq 1) 'success status inconsistent with grader outcome is incomplete'
    $counts=Measure-E2EArmCounts -Results @($paired[0],$paired[0],$paired[0],$paired[0],@{status='incomplete';api_rejected_before_generation=$true}) -RequestedCount 5
    Assert ($counts.run_count -eq 4 -and $counts.unrun_count -eq 1 -and $counts.rejected_attempt_count -eq 1) 'last requested API rejection leaves one model trial unrun'
    $paired[0].usage.complete=$false
    $comparison=Measure-E2EPairs -Results $paired.ToArray()
    Assert ($comparison.incomplete_metrics_pairs -eq 1 -and -not $comparison.release_sample_complete) 'missing metrics cannot qualify release sample'
    $paired[1].provenance.fixture_hash=('b'*64)
    $mismatchRejected=$false;try{Measure-E2EPairs -Results $paired.ToArray() | Out-Null}catch{$mismatchRejected=$true}
    Assert $mismatchRejected 'mismatched fixture provenance rejects pairing'
    $paired[1].provenance.fixture_hash=('a'*64)
    $paired[1].provenance.approvals_reviewer='user';$reviewerRejected=$false
    try{Measure-E2EPairs -Results $paired.ToArray() | Out-Null}catch{$reviewerRejected=$true}
    Assert $reviewerRejected 'paired arms cannot silently differ in native approval reviewer'
    $paired[1].provenance.approvals_reviewer='auto_review'
    $paired[1].provenance.windows_sandbox='unelevated';$platformPairRejected=$false
    try{Measure-E2EPairs -Results $paired.ToArray() | Out-Null}catch{$platformPairRejected=$true}
    Assert $platformPairRejected 'paired arms cannot silently differ in native Windows sandbox implementation'
    $paired[1].provenance.Remove('windows_sandbox')
    $paired.Add(@{case_id='rejected';trial=1;variant='native';status='incomplete';api_rejected_before_generation=$true})
    $comparison=Measure-E2EPairs -Results $paired.ToArray()
    Assert ($comparison.rejected_attempt_count -eq 1 -and $comparison.paired_trials -eq 3 -and $comparison.absolute_counts.native.run_count -eq 3) 'provable pre-generation API reject is retained separately and excluded from model outcomes'
    Write-Output "VALID E2E eval tests: $passed assertions"
} finally {
    $resolved=[IO.Path]::GetFullPath($scratch)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
