param([ValidateSet('All','ImplicitUpgrade','BackupUpgrade','Uninstall','SelfUninstall','ForeignRegistration','FlavorRace','Transitions','InvalidTargets','Noop')][string]$Case='All')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'scripts/ControlFlow.Package.psm1') -Force -DisableNameChecking
$tempBase=Resolve-ControlFlowPath ([IO.Path]::GetTempPath())
$temp=Join-Path $tempBase ('cf-install-life-'+[guid]::NewGuid().ToString('N'))
$pwsh=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$script:assertions=0
function Check([bool]$Ok,[string]$Why){if(-not$Ok){throw "ASSERT: $Why"};$script:assertions++}
function Fingerprint([string]$Root){if(-not(Test-Path $Root)){return '<absent>'};return (@(Get-ChildItem -LiteralPath $Root -Recurse -Force -File|Sort-Object FullName|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')+':'+(Get-FileHash $_.FullName).Hash})-join'|')}
function Bytes([string]$Path){[Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))}
function WriteFile([string]$Path,[string]$Text){[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))|Out-Null;[IO.File]::WriteAllText($Path,$Text)}
function Run([string]$FixtureHome,[string]$Flavor,[switch]$Force,[switch]$Uninstall,[switch]$DryRun,[string]$Script=(Join-Path $repo 'scripts/install.ps1'),[string[]]$ExtraArguments=@()){
 $argsList=@('-NoProfile','-NonInteractive','-File',$Script,'-HomeRoot',$FixtureHome)
 if($Flavor){$argsList+=@('-Flavor',$Flavor)};if($Force){$argsList+='-Force'};if($Uninstall){$argsList+='-Uninstall'};if($DryRun){$argsList+='-DryRun'}
 $argsList+=@($ExtraArguments)
 $global:LASTEXITCODE=0;$output=@(& $pwsh @argsList 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
 return @{code=$code;output=($output-join"`n")}
}
function Target([string]$FixtureHome){Join-Path $FixtureHome 'plugins/controlflow-codex'}
function Market([string]$FixtureHome){Join-Path $FixtureHome '.agents/plugins/marketplace.json'}
function Backups([string]$FixtureHome){@(Get-ChildItem -LiteralPath (Join-Path $FixtureHome 'plugins') -Directory -Force -ErrorAction SilentlyContinue|Where-Object Name -like '.controlflow-codex-backup-*')}
function Seed([string]$Name,[string]$Flavor='Universal'){
 $h=Join-Path $temp $Name;$installer=if($Flavor-ceq'NativeLegacy'){Join-Path $script:legacy 'scripts/install.ps1'}else{Join-Path $repo 'scripts/install.ps1'}
 $r=Run $h -Flavor $Flavor -Force -Script $installer;Check ($r.code-eq0) ('FixtureInstall:'+ $r.output)
 $mp=Get-Content (Market $h) -Raw|ConvertFrom-Json -AsHashtable;$mp.extra=@{keep='top'};$mp.plugins+=@{name='sibling';custom='preserve'}
 $own=@($mp.plugins|Where-Object name -ceq 'controlflow-codex')[0];$own.custom=@{keep='owned'};$own.policy['custom_policy']='retain'
 $mp|ConvertTo-Json -Depth 50|Set-Content (Market $h)
 WriteFile (Join-Path $h 'external-state/old-run/state.json') 'foreign run sentinel'
 WriteFile (Join-Path $h '.codex/config.toml') 'foreign config sentinel'
 return $h
}
function CheckForeign([string]$h){
 $mp=Get-Content (Market $h) -Raw|ConvertFrom-Json -AsHashtable
 Check ($mp.extra.keep-ceq'top' -and @($mp.plugins|Where-Object{$_.name-ceq'sibling' -and $_.custom-ceq'preserve'}).Count-eq1) 'SiblingAndTopMetadataPreserved'
 Check ([IO.File]::ReadAllText((Join-Path $h 'external-state/old-run/state.json'))-ceq'foreign run sentinel') 'RunDataPreserved'
 Check ([IO.File]::ReadAllText((Join-Path $h '.codex/config.toml'))-ceq'foreign config sentinel') 'ConfigPreserved'
}
try{
 [IO.Directory]::CreateDirectory($temp)|Out-Null
 $script:legacy=Join-Path $temp 'legacy-source';Copy-ControlFlowPackage $repo $script:legacy
 Remove-Item -LiteralPath (Join-Path $script:legacy 'plugin.json');$null=Assert-ControlFlowPackage $script:legacy -Flavor NativeLegacy
 if($Case-in@('All','ImplicitUpgrade')){
  $h=Seed implicit NativeLegacy;$r=Run $h -Force
  Check ($r.code-eq0) ('ImplicitUpgradePreservesNativeLegacy:'+ $r.output)
  Check ($r.output-match'NativeLegacy' -and $r.output-match'preserv') 'ImplicitChoiceIsVisible'
  Check (-not(Test-Path (Join-Path (Target $h) 'plugin.json'))) 'ImplicitUpgradeDidNotSwitchToUniversal'
  $null=Assert-ControlFlowPackage (Target $h) -Flavor NativeLegacy
  $a=Fingerprint $h;$r=Run $h -Force -DryRun;Check ($r.code-eq0 -and (Fingerprint $h)-ceq$a) 'PreservedFlavorDryRunWritesNothing'
  $mp=Get-Content (Market $h) -Raw|ConvertFrom-Json -AsHashtable;$own=@($mp.plugins|Where-Object name -ceq 'controlflow-codex')[0]
  Check ($own.custom.keep-ceq'owned' -and $own.policy.custom_policy-ceq'retain') 'OwnedRegistrationCustomMetadataPreserved'
  CheckForeign $h
 }
 if($Case-in@('All','BackupUpgrade')){
  $h=Seed backup;$target=Target $h;WriteFile (Join-Path $target 'user-notes/private.txt') 'custom source bytes';$old=Fingerprint $target;$oldMarket=Bytes (Market $h)
  $r=Run $h -Force;Check ($r.code-eq0) ('SameFlavorUpgrade:'+ $r.output);$b=@(Backups $h)
  Check ($b.Count-eq1 -and (Fingerprint (Join-Path $b[0].FullName 'source'))-ceq$old) 'BackupPreservesUnknownFiles'
  Check ((Bytes (Join-Path $b[0].FullName 'marketplace.json'))-ceq$oldMarket) 'BackupPreservesExactRegistrationBytes'
  Check ($r.output.Contains($b[0].FullName)) 'BackupPathIsVisible'
  Check (-not(Test-Path (Join-Path $target 'user-notes/private.txt'))) 'ActivePackageIsClean'
  CheckForeign $h
 }
 if($Case-in@('All','Uninstall')){
  $h=Seed uninstall NativeLegacy;$target=Target $h;WriteFile (Join-Path $target 'user-notes.txt') 'keep me';$old=Fingerprint $target;$oldMarket=Bytes (Market $h)
  $r=Run $h -Uninstall -Force;Check ($r.code-eq0) ('Uninstall:'+ $r.output);$b=@(Backups $h)
  Check (-not(Test-Path $target) -and $b.Count-eq1 -and (Fingerprint (Join-Path $b[0].FullName 'source'))-ceq$old) 'UninstallRetainsUnknownData'
  Check ((Bytes (Join-Path $b[0].FullName 'marketplace.json'))-ceq$oldMarket) 'UninstallBackupKeepsRegistration'
  $mp=Get-Content (Market $h) -Raw|ConvertFrom-Json;Check (@($mp.plugins|Where-Object name -ceq 'controlflow-codex').Count-eq0) 'OnlyOwnedRegistrationRemoved';CheckForeign $h
  $before=Fingerprint $h;[IO.File]::SetLastWriteTimeUtc((Market $h),[datetime]'2001-01-01T00:00:00Z');$time=[IO.File]::GetLastWriteTimeUtc((Market $h));$r=Run $h -Uninstall
  Check ($r.code-eq0 -and (Fingerprint $h)-ceq$before -and [IO.File]::GetLastWriteTimeUtc((Market $h))-eq$time) 'RepeatedUninstallIsNoop'
  $r=Run $h -Force;Check ($r.code-eq0) ('ReinstallAfterUninstall:'+ $r.output);$null=Assert-ControlFlowPackage (Target $h);CheckForeign $h
 }
 if($Case-in@('All','SelfUninstall')){
  $h=Seed self NativeLegacy;$target=Target $h;$old=Fingerprint $target
  $r=Run $h -Force -Uninstall -Script (Join-Path $target 'scripts/install.ps1');Check ($r.code-eq0) ('ExactSelfUninstall:'+ $r.output)
  $b=@(Backups $h);Check (-not(Test-Path $target) -and $b.Count-eq1 -and (Fingerprint (Join-Path $b[0].FullName 'source'))-ceq$old) 'SelfUninstallRetainsBackup';CheckForeign $h
 }
 if($Case-in@('All','ForeignRegistration')){
  foreach($kind in @('foreign','foreign-duplicate','owned-duplicate')){
   $h=Seed ('registration-'+$kind);$mp=Get-Content (Market $h) -Raw|ConvertFrom-Json -AsHashtable
   if($kind-ceq'foreign'){@($mp.plugins|Where-Object name -ceq 'controlflow-codex')[0].source.path='./plugins/foreign'}else{$mp.plugins+=@{name='controlflow-codex';source=@{source='local';path=$(if($kind-ceq'owned-duplicate'){'./plugins/controlflow-codex'}else{'./plugins/foreign'})}}}
   $mp|ConvertTo-Json -Depth 40|Set-Content (Market $h);$before=Fingerprint $h
   foreach($remove in @($false,$true)){$r=Run $h -Force -Uninstall:$remove;Check ($r.code-ne0 -and (Fingerprint $h)-ceq$before) ('ForeignOrDuplicateRegistrationRejectedWithoutMutation:'+ $kind)}
  }
 }
 if($Case-in@('All','FlavorRace')){
  $h=Seed race NativeLegacy;$target=Target $h;$before=@(Get-ChildItem $target -Recurse -File -Force|ForEach-Object{@{path=[IO.Path]::GetRelativePath($target,$_.FullName);hash=(Get-FileHash $_.FullName).Hash}});$marketBefore=Bytes (Market $h)
  $wrapper=Join-Path $temp 'race-wrapper.ps1';$marker=Join-Path $temp 'race-marker'
  WriteFile $wrapper @'
param([string]$HomeRoot,[string]$Installer,[string]$FixtureManifest,[string]$Marker,[switch]$Force)
$ErrorActionPreference='Stop'
$lines=[IO.File]::ReadAllLines($Installer);$line=0
for($i=0;$i-lt$lines.Length;$i++){if($lines[$i].StartsWith('$installationLock = ')){$line=$i+1;break}}
if(-not$line){throw 'RACE_SYNC_POINT_MISSING'}
$bp=Set-PSBreakpoint -Script $Installer -Line $line -Action {
 [IO.File]::Copy($FixtureManifest,(Join-Path $HomeRoot 'plugins/controlflow-codex/plugin.json'),$false)
 [IO.File]::WriteAllText($Marker,'after-initial-selection')
}
try{& $Installer -HomeRoot $HomeRoot -Force}finally{Remove-PSBreakpoint -Breakpoint $bp}
'@
  $r=Run $h -Force -Script $wrapper -ExtraArguments @('-Installer',(Join-Path $repo 'scripts/install.ps1'),'-FixtureManifest',(Join-Path $repo 'plugin.json'),'-Marker',$marker)
  Check ((Test-Path $marker) -and $r.code-ne0 -and $r.output-match'changed during initialization') 'ChangedFlavorAfterInitialSelectionRejected'
  Check ((Bytes (Market $h))-ceq$marketBefore -and @(Backups $h).Count-eq0) 'FlavorRaceDoesNotPublishOrBackUpForeignChange'
  foreach($f in $before){Check ((Get-FileHash (Join-Path $target $f.path)).Hash-ceq$f.hash) 'FlavorRacePreservesExistingFiles'}
  Check ((Bytes (Join-Path $target 'plugin.json'))-ceq(Bytes (Join-Path $repo 'plugin.json'))) 'FlavorRacePreservesConcurrentRootManifest'
 }
 if($Case-in@('All','Transitions')){
  $h=Seed transitions;$before=Fingerprint $h;$r=Run $h -Flavor NativeLegacy
  Check ($r.code-ne0 -and (Fingerprint $h)-ceq$before) 'CrossFlavorStillRequiresForce'
  $r=Run $h -Flavor NativeLegacy -Force;Check ($r.code-eq0) ('CanonicalSourceCanStageNativeLegacy:'+ $r.output);$null=Assert-ControlFlowPackage (Target $h) -Flavor NativeLegacy
  foreach($p in Get-ControlFlowPackageFiles $script:legacy -Flavor NativeLegacy){Check ((Bytes (Join-Path $script:legacy $p))-ceq(Bytes (Join-Path (Target $h) $p))) ('CrossFlavorSharedBytes:'+ $p)}
  $r=Run $h -Flavor Universal -Force;Check ($r.code-eq0) 'ExplicitUniversalTransition';$null=Assert-ControlFlowPackage (Target $h)
  $before=Fingerprint $h;$r=Run $h -Force -Script (Join-Path $script:legacy 'scripts/install.ps1');Check ($r.code-ne0 -and (Fingerprint $h)-ceq$before) 'NativeSourceCannotSilentlyManufactureUniversal'
  CheckForeign $h
 }
 if($Case-in@('All','InvalidTargets')){
  foreach($kind in @('unowned','corrupt','file')){
   $h=Join-Path $temp ('invalid-'+$kind);$target=Target $h
   if($kind-ceq'file'){WriteFile $target 'foreign file'}else{WriteFile (Join-Path $target 'keep.txt') 'unknown bytes';if($kind-ceq'corrupt'){WriteFile (Join-Path $target 'plugin.json') '{broken'}}
   $before=Fingerprint $h;foreach($remove in @($false,$true)){$r=Run $h -Force -Uninstall:$remove;Check ($r.code-ne0 -and (Fingerprint $h)-ceq$before) ('InvalidTargetPreserved:'+ $kind)}
  }
  $h=Seed partial;$target=Target $h;Remove-Item -LiteralPath (Join-Path $target 'scripts/doctor.ps1');WriteFile (Join-Path $target 'unknown.txt') 'partial custom';$old=Fingerprint $target
  $r=Run $h -Force;Check ($r.code-eq0) 'OwnedPartialInstallRepair';$b=@(Backups $h);Check ($b.Count-eq1 -and (Fingerprint (Join-Path $b[0].FullName 'source'))-ceq$old) 'PartialRepairBackupIsExact';$null=Assert-ControlFlowPackage $target
 }
 if($Case-in@('All','Noop')){
  $h=Join-Path $temp 'missing-home';$r=Run $h -Uninstall;Check ($r.code-eq0 -and -not(Test-Path $h)) 'MissingUninstallDoesNotCreateHome'
  $h=Join-Path $temp 'fresh-legacy';$r=Run $h -Force -Script (Join-Path $script:legacy 'scripts/install.ps1');Check ($r.code-ne0 -and -not(Test-Path $h)) 'FreshNativeArtifactStillNeedsExplicitFlavor'
 }
 Write-Output "installer-lifecycle $Case`: $script:assertions assertions passed"
 $global:LASTEXITCODE=0
}finally{if(Test-Path $temp){Remove-ControlFlowTree $temp $tempBase}}
