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
try {
    $processAst=[Management.Automation.Language.Parser]::ParseFile($lib,[ref]$null,[ref]$null)
    $functionAst=@($processAst.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-E2EProcess'},$false))[0]
    $drainLoops=@($functionAst.FindAll({param($n)$n -is [Management.Automation.Language.WhileStatementAst] -and $n.Condition.Extent.Text.Contains('$drain.ElapsedMilliseconds')},$true))
    if($drainLoops.Count -ne 1){throw 'Process cleanup loop must be unique'}
    foreach($command in $drainLoops[0].FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)){
        if($command.GetCommandName() -cnotin @('Invoke-E2EGroupSignal','Out-Null')){throw 'Controlled cleanup fixture refuses unexpected native commands'}
    }
    $drainCode=[scriptblock]::Create($drainLoops[0].Extent.Text)
    $sequenceCases=@(
        @{name='ESRCH then EPERM at deadline loses prior absence';observations=@('absent','EPERM');eof_after=1;prior=$true;expected=$false},
        @{name='EPERM then ESRCH establishes fresh absence';observations=@('EPERM','absent');eof_after=0;prior=$true;expected=$true},
        @{name='persistent EPERM is unknown';observations=@('EPERM','EPERM');eof_after=0;prior=$true;expected=$false},
        @{name='unexpected errno stays failed after later absence';observations=@('EINVAL','absent');eof_after=0;prior=$true;expected=$false},
        @{name='prior kill failure is preserved';observations=@('absent');eof_after=0;prior=$false;expected=$false},
        @{name='live group at deadline cannot pass';observations=@('present','present');eof_after=0;prior=$true;expected=$false},
        @{name='direct ESRCH with complete streams is accepted';observations=@('absent');eof_after=0;prior=$true;expected=$true}
    )
    foreach($case in $sequenceCases){
        $actual=& {
            param($code,$case)
            $script:E2EProbe=0;$script:E2ESequence=$case
            function Invoke-E2EGroupSignal {
                param($Id,$Signal)
                $next=$script:E2ESequence.observations[$script:E2EProbe];$script:E2EProbe++
                switch -CaseSensitive ($next){'absent'{return $false}'present'{return $true}'EPERM'{throw 'PROCESS_GROUP_SIGNAL_UNVERIFIABLE: errno=1'}'EINVAL'{throw 'PROCESS_GROUP_SIGNAL_UNVERIFIABLE: errno=22'}}
            }
            $lineTask=[pscustomobject]@{}
            $lineTask|Add-Member -MemberType ScriptProperty -Name IsCompleted -Value {$script:E2EProbe -ge $script:E2ESequence.eof_after}
            $lineTask|Add-Member -MemberType ScriptMethod -Name GetAwaiter -Value {$this}
            $lineTask|Add-Member -MemberType ScriptMethod -Name GetResult -Value {$null}
            $stderrTask=@{IsCompleted=$true};$process=@{Id=2147483647;HasExited=$true};$eof=$false;$group=$true;$job=$null
            $cleanup=$case.prior;$ownedEmpty=$false;$stdout=[Text.StringBuilder]::new();$writer=$null
            $drain=[pscustomobject]@{}
            $drain|Add-Member -MemberType ScriptProperty -Name ElapsedMilliseconds -Value {if($script:E2EProbe -ge $script:E2ESequence.observations.Count){750}else{0}}
            . $code
            @{verified=($cleanup -and $process.HasExited -and $ownedEmpty);probes=$script:E2EProbe}
        } $drainCode $case
        Assert ($actual.verified -eq $case.expected -and $actual.probes -eq $case.observations.Count) $case.name
    }
    $strictReady=& {Set-StrictMode -Version Latest;Get-E2EProtocolReadiness @{Variant='v4'}}
    Assert ($strictReady.collector -ceq 'stdout-jsonl' -and -not $strictReady.may_launch) 'optional Collector default works under StrictMode'
    foreach($variant in @('v3','future',$null)){
        $rejected=$false;try{Get-E2EConfigArguments @{Variant=$variant}|Out-Null}catch{$rejected=$true}
        Assert $rejected 'offline config builder cannot silently reinterpret a retired or unknown treatment as native'
    }
    $processCore=Get-E2EProcessCore
    Assert ((& $processCore {Resolve-CFGroupSignalResult -1 3}) -eq $false) 'shared Unix signal resolver accepts ESRCH as absence'
    foreach($errno in @(1,22)){
        $rejected=$false;try{& $processCore {param($value) Resolve-CFGroupSignalResult -1 $value} $errno|Out-Null}catch{$rejected=$true}
        Assert $rejected 'EPERM and unexpected signal errors never prove owned-group absence'
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
    $namedMarket=@{Model='test-model';Effort='max';Variant='v4';ApprovalPolicy='on-request';ApprovalReviewer='auto_review';Sandbox='workspace-write';WindowsSandbox='elevated';Settings=@();MarketplaceRoot=$marketplaceRoot;MarketplaceName='controlflow-eval-unique-test';CliPrefix=@()}
    $namedArgs=@(Get-E2EConfigArguments $namedMarket)
    $upperMarket=$namedMarket.Clone();$upperMarket.Variant='V4'
    Assert (@(Get-E2EConfigArguments $upperMarket) -contains 'plugins.controlflow-codex@controlflow-eval-unique-test.enabled=true') 'accepted case variants cannot silently disable the V4 treatment'
    Assert ((Get-E2ETrialPrompt @{task='Frozen task'}).StartsWith('$controlflow-codex:controlflow Use contract/runtime 4.0.0.')) 'trial prompt defaults to the V4 route'
    foreach($ambient in @('pages','plugin-management','sites','superpowers','work-pets')){
        Assert ($namedArgs -contains ('plugins.'+$ambient+'@openai-curated-remote.enabled=false')) 'session overrides explicitly disable observed ambient native plugin identities'
    }
    Assert ($namedArgs -contains 'plugins.controlflow-codex@controlflow-eval-unique-test.enabled=true' -and $namedArgs -notcontains 'plugins."controlflow-codex@controlflow-eval-unique-test".enabled=true') 'native CLI override path uses bare plugin identity, rather than a literal quoted key'
    $marketplaceSourceArgument='marketplaces.controlflow-eval-unique-test.source='+($marketplaceRoot.Replace('\','/') | ConvertTo-Json -Compress)
    Assert ($namedArgs -contains 'marketplaces.controlflow-eval-unique-test.source_type="local"' -and $namedArgs -contains $marketplaceSourceArgument) 'explicit named marketplace source and local type stay independent arguments'
    $inventoryFirst=@([ordered]@{path='skills/entry/SKILL.md';sha256=('a'*64)},[ordered]@{path='plugin.json';sha256=('b'*64)})
    $inventoryOther=@([ordered]@{sha256=('B'*64);path='plugin.json'},[ordered]@{sha256=('A'*64);path='skills\entry\SKILL.md'})
    $canonicalDigest=Get-E2EPluginDigest -Inventory $inventoryFirst
    Assert ($canonicalDigest -ceq (Get-E2EPluginDigest -Inventory $inventoryOther)) 'plugin digest is canonical across key/file order, separators and hash letter case'
    $inventoryOther[0].sha256='c'*64
    Assert ($canonicalDigest -cne (Get-E2EPluginDigest -Inventory $inventoryOther)) 'plugin digest changes when actual file bytes change'
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
    $validProvenance=@{model='test-model';effort='high';host='test-host';fixture_hash=('a'*64);settings=@();project_trust='untrusted';sandbox='workspace-write';windows_sandbox='elevated';approval_policy='on-request';approvals_reviewer='auto_review';cli_version='0.166.0';collector='stdout-jsonl';protocol_version='exec-jsonl-root-v1';plugin_sha256=('b'*64);budget=@{tokens=1000;tools=20;wall_seconds=60}}
    Assert (Test-E2EProvenance $validProvenance) 'well-shaped declared provenance can be validated without authenticating it'
    foreach($field in @('model','effort','host','fixture_hash','sandbox','approval_policy','cli_version','budget','settings')){
        $invalid=$validProvenance|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
        $invalid.Remove($field)
        Assert (-not (Test-E2EProvenance $invalid)) "missing $field cannot certify declared provenance shape"
    }
    foreach($bad in @(@{field='fixture_hash';value='same'},@{field='effort';value='ultra'},@{field='settings';value=''},@{field='approval_policy';value='bypass'},@{field='project_trust';value='trusted'})){
        $invalid=$validProvenance|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
        $invalid[$bad.field]=$bad.value
        Assert (-not (Test-E2EProvenance $invalid)) "invalid $($bad.field) stays invalid"
    }
    foreach($badBudget in @($null,0,-1,'1000',1.5)){
        $invalid=$validProvenance|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
        $invalid.budget.tokens=$badBudget
        Assert (-not (Test-E2EProvenance $invalid)) 'budget requires positive integer values'
    }
    $records=@(foreach($variant in @('native','v4')){@{schema_version='2.0.0';case_id='paired';tier='SMALL';trial=1;variant=$variant;status='success';false_completion=$false;usage=@{complete=$true;input_tokens=90;output_tokens=10;cached_input_tokens=0;total_tokens=100;tool_calls=0};outcome=@{pass=$true;collection_complete=$true;check_count=1;planned_check_count=1;receipt=@{verified=$true;nonce='offline-grader-fixture'}};provenance=($validProvenance|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable)}})
    $paired=Measure-E2EPairs $records
    Assert ($paired.treatment -ceq 'v4' -and $paired.paired_trials -eq 1 -and $paired.incomplete_metrics_pairs -eq 1 -and $null -eq $paired.success_delta -and -not $paired.release_sample_complete -and -not $paired.production_ready) 'declared complete usage and receipts cannot invent V4 native provenance or measured benefit'
    foreach($trial in @($null,0,'1',1.5)){
        $badPair=$records|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
        $badPair[0].trial=$trial
        $rejected=$false;try{Measure-E2EPairs $badPair|Out-Null}catch{$rejected=$true}
        Assert $rejected 'paired identity requires a real positive integer trial'
    }
    $legacy=$records|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
    $legacy[1].variant='v3';$legacy[1].schema_version='1.0.0'
    $rejected=$false;try{Measure-E2EPairs $legacy|Out-Null}catch{$rejected=$true}
    Assert $rejected 'historical schema1 V3 data is never relabeled into a V4 pair'
    foreach($counter in @('check_count','planned_check_count')){
        $invalid=$records[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
        $invalid.outcome[$counter]=0
        Assert (-not (Test-E2EResultEnvelope $invalid)) 'zero or mismatched executed assertions cannot certify a result envelope'
    }
    $observeScript=Join-Path $scratch 'observed-budget.ps1'
    Write-Utf8 $observeScript '[Console]::Out.WriteLine("budget-observed"); Start-Sleep -Seconds 4'
    $observed=Invoke-E2EProcess -Executable (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',$observeScript) -WorkingDirectory $scratch -TimeoutSeconds 6 -Observe {param($text)if($text.Contains('budget-observed')){'OBSERVED_TEST_BUDGET'}}
    Assert ($observed.budget_reason -ceq 'OBSERVED_TEST_BUDGET' -and $observed.wall_ms -lt 4000 -and $observed.cleanup_verified) 'observed local process budget stops its owned process and is not a global token-cap claim'
    $receiptPath=Join-Path $scratch 'observed.process.json'
    Write-E2EProcessReceipt $observed $receiptPath
    $receipt=Get-Content $receiptPath -Raw|ConvertFrom-Json -AsHashtable
    Assert ($receipt.cleanup_verified -and $receipt.streams_complete -and $receipt.budget_reason -ceq 'OBSERVED_TEST_BUDGET') 'process receipt retains actual stop/cleanup evidence'
    $guardScript=Join-Path $scratch 'stdin-preflight.ps1'
    Write-Utf8 $guardScript @'
$inputText=[Console]::In.ReadToEnd()
if($inputText.Length -eq 0){[Console]::Error.WriteLine('No prompt provided via stdin.');exit 1}
[IO.File]::WriteAllText($env:CF_EVAL_SHOULD_NOT_GENERATE,'generation')
exit 99
'@
    $marker=Join-Path $scratch 'must-not-generate'
    $preflightConfig=@{Model='test-model';Effort='high';Variant='v4';ApprovalPolicy='on-request';ApprovalReviewer='auto_review';Sandbox='workspace-write';WindowsSandbox='elevated';Settings=@();CliPrefix=@('-NoProfile','-File',$guardScript);CliPath=(Get-Command pwsh).Source;Environment=@{CF_EVAL_SHOULD_NOT_GENERATE=$marker}}
    $preflight=Invoke-E2EPolicyPreflight $preflightConfig (Join-Path $scratch 'preflight')
    Assert ($preflight.verified -and $preflight.checks.Count -eq 2 -and -not (Test-Path $marker)) 'retained exact initial/resume argv preflight uses empty stdin and never generates'
    foreach($variant in @('native','v4')){
        $config=$preflightConfig.Clone();$config.Variant=$variant;$config.CliPath=Join-Path $scratch 'must-not-launch.exe'
        $config.ActualContext=@{verified=$true};$config.IsolationVerified=$true;$config.ChildUsageVerified=$true
        $result=Invoke-E2ETrial @{id='blocked';tier='SMALL';task='Do not execute'} $config (Join-Path $scratch ('blocked-'+$variant))
        Assert ($result.protocol_blocked_before_generation -and -not $result.generation_started -and $result.spend_status -ceq 'not-generated-protocol-block' -and $null -eq $result.usage -and -not (Test-Path $marker)) 'both arms block before CLI even with caller-authored capability flags'
    }
    Write-Output "VALID E2E eval tests: $passed assertions"
} finally {
    $resolved=[IO.Path]::GetFullPath($scratch)
    $base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('controlflow-e2e-tests-')){throw 'Unsafe eval fixture cleanup'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$global:LASTEXITCODE=0
