param([ValidateSet('All','Package','Installer')][string]$Group='All')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'scripts/ControlFlow.Package.psm1') -Force -DisableNameChecking
$tempBase=Resolve-ControlFlowPath ([IO.Path]::GetTempPath())
$temp=Join-Path $tempBase ('controlflow-flavor-'+[guid]::NewGuid().ToString('N'))
$assertions=0
function Check([bool]$Ok,[string]$Why){if(-not $Ok){throw $Why};$script:assertions++}
function Reject([scriptblock]$Action,[string]$Why){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Why}
function Bytes([string]$Path){return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))}
function Tree([string]$Root){return (@(Get-ChildItem -LiteralPath $Root -Recurse -Force -File|Sort-Object FullName|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName)+':'+(Get-FileHash -LiteralPath $_.FullName).Hash}) -join "`n")}
try{
 New-Item -ItemType Directory -Path $temp|Out-Null
 $rootBefore=Bytes (Join-Path $repo 'plugin.json')
 $inventoryBefore=Bytes (Join-Path $repo 'scripts/package-inventory.json')
 Reject {Assert-ControlFlowPackage $repo -Flavor NativeLegacy} 'NativeLegacy accepted a root AgentPlugin manifest'
 Reject {Assert-ControlFlowPackage $repo -Flavor Unknown} 'Unknown package flavor was accepted'
 Reject {Get-ControlFlowPackageFiles $repo -Flavor nativelegacy} 'Noncanonical flavor spelling was silently interpreted'
 & (Join-Path $repo 'scripts/package.ps1') -Flavor NativeLegacy -OutputDirectory (Join-Path $temp 'dist')|Out-Null
 $v=(Get-Content -LiteralPath (Join-Path $repo 'plugin.json') -Raw|ConvertFrom-Json).version
 $zip=Join-Path $temp "dist/controlflow-codex-$v-native-legacy.zip"
 Check (Test-Path -LiteralPath $zip -PathType Leaf) 'NativeLegacy artifact filename is not distinct'
 [IO.Compression.ZipFile]::ExtractToDirectory($zip,(Join-Path $temp 'extract'))
 $legacy=Join-Path $temp 'extract/controlflow-codex'
 $null=Assert-ControlFlowPackage $legacy -Flavor NativeLegacy
 Check (-not (Test-Path -LiteralPath (Join-Path $legacy 'plugin.json'))) 'NativeLegacy retained root AgentPlugin manifest'
 Reject {Assert-ControlFlowPackage $legacy} 'Universal silently fell back to legacy'
 $expected=@(Get-ControlFlowPackageFiles $repo|Where-Object{$_ -cne 'plugin.json'})
 $actual=@(Get-ChildItem -LiteralPath $legacy -Recurse -Force -File|ForEach-Object{[IO.Path]::GetRelativePath($legacy,$_.FullName).Replace('\','/')}|Sort-Object)
 Check (@(Compare-Object $expected $actual).Count -eq 0) 'NativeLegacy file set differs by more than root manifest'
 foreach($p in $expected){Check ((Bytes (Join-Path $repo $p)) -ceq (Bytes (Join-Path $legacy $p))) "Flavor changed common bytes: $p"}
 $receipt=Get-Content -LiteralPath ($zip+'.inventory.json') -Raw|ConvertFrom-Json
 Check ($receipt.flavor -ceq 'NativeLegacy' -and $receipt.callbacks -ceq 'NOT_RUN') 'Flavor provenance implies callback acceptance or omits flavor'
 Check ($receipt.archive_sha256 -ceq (Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant()) 'Flavor provenance has wrong ZIP digest'
 Check ((Bytes (Join-Path $repo 'plugin.json')) -ceq $rootBefore -and (Bytes (Join-Path $repo 'scripts/package-inventory.json')) -ceq $inventoryBefore) 'Packaging modified canonical manifest/inventory'
 if($Group -in @('All','Package')){
  foreach($p in @('skills/controlflow/nested/SKILL.md','skills/unexpected/SKILL.md','.codex-plugin/migrated-command-skills/extra/SKILL.md','commands/extra.md','mcp.json','.mcp.json','.mcp.json5','.codex-plugin/mcp.json','hooks/mcp.json','.app.json')){
   $injected=Join-Path $legacy $p;New-Item -ItemType Directory -Path (Split-Path $injected -Parent) -Force|Out-Null
   Set-Content -LiteralPath $injected '{}'
   Reject {Assert-ControlFlowPackage $legacy -Flavor NativeLegacy} "NativeLegacy accepted unexpected capability: $p"
   Remove-Item -LiteralPath $injected -Force
   Check (-not (Test-Path -LiteralPath $injected)) "Fixture cleanup retained injected capability: $p"
   if($p -ceq 'skills/unexpected/SKILL.md'){Remove-Item -LiteralPath (Split-Path $injected -Parent)}
   foreach($extraRoot in @('commands','.codex-plugin/migrated-command-skills')){if(Test-Path -LiteralPath (Join-Path $legacy $extraRoot)){Remove-ControlFlowTree (Join-Path $legacy $extraRoot) $legacy}}
   $null=Assert-ControlFlowPackage $legacy -Flavor NativeLegacy
  }
  $compatPath=Join-Path $legacy '.codex-plugin/plugin.json';$compatBytes=[IO.File]::ReadAllBytes($compatPath)
  foreach($key in @('mcpServers','mcp_servers','apps')){
   $c=Get-Content -LiteralPath $compatPath -Raw|ConvertFrom-Json -AsHashtable;$c[$key]='./outside.json';$c|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $compatPath
   Reject {Assert-ControlFlowPackage $legacy -Flavor NativeLegacy} "NativeLegacy accepted manifest capability: $key"
   [IO.File]::WriteAllBytes($compatPath,$compatBytes)
  }
  $outside=Join-Path $temp 'outside';New-Item -ItemType Directory -Path $outside|Out-Null
  $link=Join-Path $legacy 'skills/link';$kind=if($IsWindows){'Junction'}else{'SymbolicLink'}
  New-Item -ItemType $kind -Path $link -Target $outside|Out-Null
  try{Reject {Assert-ControlFlowPackage $legacy -Flavor NativeLegacy} 'NativeLegacy followed a link'}finally{Remove-Item -LiteralPath $link -Force}
  $badOut=Join-Path $temp 'bad-output';New-Item -ItemType Directory -Path (Join-Path $badOut "controlflow-codex-$v-native-legacy.zip.sha256") -Force|Out-Null
  Reject {& (Join-Path $repo 'scripts/package.ps1') -Flavor NativeLegacy -OutputDirectory $badOut} 'Package accepted a non-file sidecar output'
  Check (-not (Test-Path -LiteralPath (Join-Path $badOut "controlflow-codex-$v-native-legacy.zip"))) 'Invalid sidecar caused partial ZIP publication'
  $linkedOut=Join-Path $temp 'linked-output';New-Item -ItemType Directory -Path $linkedOut|Out-Null
  $sidecarLink=Join-Path $linkedOut "controlflow-codex-$v-native-legacy.zip.inventory.json"
  New-Item -ItemType $kind -Path $sidecarLink -Target $outside|Out-Null
  try{
   $guarded=$false;try{& (Join-Path $repo 'scripts/package.ps1') -Flavor NativeLegacy -OutputDirectory $linkedOut|Out-Null}catch{$guarded=$_.Exception.Message -match 'Link/reparse'}
   Check $guarded 'Sidecar publication did not use the reparse guard'
   Check (-not (Test-Path -LiteralPath (Join-Path $linkedOut "controlflow-codex-$v-native-legacy.zip"))) 'Linked sidecar caused partial ZIP publication'
  }finally{Remove-Item -LiteralPath $sidecarLink -Force}
 }
 if($Group -in @('All','Installer')){
  $install=Join-Path $legacy 'scripts/install.ps1';$homeFixture=Join-Path $temp 'home'
  $dry=@(& $install -Flavor NativeLegacy -HomeRoot $homeFixture -DryRun)
  Check (-not (Test-Path -LiteralPath $homeFixture)) 'Installer dry-run wrote to the home'
  Check (($dry -join ' ') -match 'NativeLegacy') 'Installer dry-run omits chosen flavor'
  Reject {& $install -HomeRoot $homeFixture -Force} 'Installer silently accepted NativeLegacy as Universal'
  Check (-not (Test-Path -LiteralPath $homeFixture)) 'Rejected flavor created home state'
  & (Join-Path $repo 'scripts/install.ps1') -HomeRoot $homeFixture -Force|Out-Null
  $target=Join-Path $homeFixture 'plugins/controlflow-codex';$market=Join-Path $homeFixture '.agents/plugins/marketplace.json'
  $mp=Get-Content -LiteralPath $market -Raw|ConvertFrom-Json -AsHashtable;$mp.plugins+=@{name='sibling';keep='preserve'};$mp|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $market
  $beforeTree=Tree $target;$beforeMarket=Bytes $market
  & $install -Flavor NativeLegacy -HomeRoot $homeFixture -Force -DryRun|Out-Null
  Check ((Tree $target) -ceq $beforeTree -and (Bytes $market) -ceq $beforeMarket) 'Existing-home dry-run mutated installation'
  if($IsWindows){
   $held=[IO.File]::Open($market,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
   try{Reject {& $install -Flavor NativeLegacy -HomeRoot $homeFixture -Force} 'Locked marketplace unexpectedly published NativeLegacy'}finally{$held.Dispose()}
   Check ((Tree $target) -ceq $beforeTree -and (Bytes $market) -ceq $beforeMarket) 'Flavor transition rollback lost previous bytes'
  }
  $out=@(& $install -Flavor NativeLegacy -HomeRoot $homeFixture -Force)
  Check (($out -join ' ') -match 'NativeLegacy') 'Install output omits selected flavor'
  Check (-not (Test-Path -LiteralPath (Join-Path $target 'plugin.json'))) 'Flavor replacement retained stale root manifest'
  foreach($p in $expected){Check ((Bytes (Join-Path $legacy $p)) -ceq (Bytes (Join-Path $target $p))) "Installed flavor bytes differ: $p"}
  $preserved=Tree $target;$marketBefore=Bytes $market
  Reject {& (Join-Path $repo 'scripts/install.ps1') -HomeRoot $homeFixture -Force} 'Implicit cross-flavor replacement was accepted'
  Check ((Tree $target) -ceq $preserved -and (Bytes $market) -ceq $marketBefore) 'Rejected implicit switch mutated installation'
  & (Join-Path $repo 'scripts/install.ps1') -Flavor Universal -HomeRoot $homeFixture -Force|Out-Null
  Check (Test-Path -LiteralPath (Join-Path $target 'plugin.json') -PathType Leaf) 'Explicit Universal rollback did not restore root manifest'
  $mp=Get-Content -LiteralPath $market -Raw|ConvertFrom-Json
  Check (@($mp.plugins|Where-Object{$_.name -ceq 'sibling' -and $_.keep -ceq 'preserve'}).Count -eq 1) 'Flavor transitions lost sibling marketplace entry'
 }
 Write-Output "VALID NativeLegacy $Group ($assertions assertions; callback NOT_RUN)"
}finally{if(Test-Path -LiteralPath $temp){Remove-ControlFlowTree $temp $tempBase}}
