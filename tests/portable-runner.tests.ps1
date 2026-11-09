param([switch]$FullPackage,[ValidateSet('All','Runner','Package')][string]$Case='All')
. "$PSScriptRoot/core-test-helpers.ps1"
Import-Module "$script:CoreRoot/scripts/ControlFlow.Package.psm1" -Force -DisableNameChecking
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cf-portable-runner-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
$savedProgress=$env:CONTROLFLOW_TEST_PROGRESS
try{
 if($Case -in @('All','Runner')){
  $env:CONTROLFLOW_TEST_PROGRESS='0'
  $fixture=Join-Path $temp 'runner';[IO.Directory]::CreateDirectory($fixture)|Out-Null
  $runner=Join-Path $fixture 'run-contract-tests.ps1'
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'run-contract-tests.ps1') -Destination $runner
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'controlflow-contract.Tests.ps1') -Destination $fixture
  $source=[IO.File]::ReadAllText($runner)
  $names=@([regex]::Matches($source,'(?m)^Invoke-ContractScript "([^"]+)"')|ForEach-Object {$_.Groups[1].Value})
  Assert ($names.Count -gt 0) 'RunnerFixtureHasSuites'
  foreach($name in $names){File $fixture $name ('[IO.File]::AppendAllText((Join-Path $PSScriptRoot ''calls.log''),'''+$name+[Environment]::NewLine+"')")}
  $log=Join-Path $fixture 'calls.log'
  function Describe {param($Name,[scriptblock]$Body)& $Body}
  function It {param($Name,[scriptblock]$Body)& $Body}
  $global:CFMockPesterFail=$false;$global:CFMockPesterV3=$false;$global:CFMockPesterUsedConfiguration=$false
  function Invoke-Pester {
   param($Path,[switch]$PassThru,$Configuration)
   if($Configuration){
    $global:CFMockPesterUsedConfiguration=$true
    $Path=$Configuration.Run.Path
    Assert (-not $Configuration.TestRegistry.Enabled) 'UnusedRegistryFixtureDisabled'
   }
   & $Path
   if($global:CFMockPesterV3){return [pscustomobject]@{FailedCount=$(if($global:CFMockPesterFail){1}else{0})}}
   return [pscustomobject]@{Result=$(if($global:CFMockPesterFail){'Failed'}else{'Passed'})}
  }
  & $runner -UsePester|Out-Null
  Assert $global:CFMockPesterUsedConfiguration 'Pester5ConfigurationRouteExercised'
  $calls=@(Get-Content -LiteralPath $log)
  Assert ($calls.Count -eq $names.Count -and @($calls|Group-Object|Where-Object Count -ne 1).Count -eq 0) 'PesterRunsEachSuiteExactlyOnce'
  foreach($legacy in @($false,$true)){
   $global:CFMockPesterV3=$legacy;$global:CFMockPesterFail=$true
   Throws {& $runner -UsePester|Out-Null} ('PesterFailurePropagates:'+ $legacy)
  }
  [IO.File]::Delete($log)
  $blocked=& {
   param($RunnerPath)
   function Get-Command {param($Name,$ErrorAction)return $null}
   try{& $RunnerPath -UsePester|Out-Null;$false}catch{$_.Exception.Message -match 'Pester is required'}
  } $runner
  Assert ($blocked -and -not [IO.File]::Exists($log)) 'MissingPesterRejectedBeforeSuites'
  File $fixture $names[0] "throw 'intentional fixture failure'"
  Throws {& $runner|Out-Null} 'PlainSuiteFailurePropagates'
  $env:CONTROLFLOW_TEST_PROGRESS=$savedProgress
 }
 if($Case -in @('All','Package')){
  $sourceHasManifest=Test-Path -LiteralPath (Join-Path $script:CoreRoot 'plugin.json') -PathType Leaf
  $flavors=if($sourceHasManifest){@('Universal','NativeLegacy')}else{@('NativeLegacy')}
  foreach($flavor in $flavors){
   $copy=Join-Path $temp $flavor
   if($sourceHasManifest){
    Copy-ControlFlowPackage $script:CoreRoot $copy
    if($flavor -ceq 'NativeLegacy'){Remove-Item -LiteralPath (Join-Path $copy 'plugin.json');Assert-ControlFlowPackage $copy -Flavor NativeLegacy|Out-Null}
   }else{Copy-ControlFlowPackage $script:CoreRoot $copy -Flavor NativeLegacy}
   Assert (-not (Test-Path -LiteralPath (Join-Path $copy '.github'))) 'PortableFixtureHasNoWorkflow'
   & (Join-Path $copy 'tests/e2e-v4-cli.tests.ps1') -AdapterRoot $copy|Out-Null
   Assert ($LASTEXITCODE -eq 0) ('PortableCliPasses:'+ $flavor)
   if($FullPackage -and $flavor -ceq 'Universal'){
    # The default call in the packaged full suite does not recurse into FullPackage.
    # A fresh process prevents this test's helper functions/mocks from shadowing
    # native commands (for example Git) in the packaged standalone runner.
    & (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -NoProfile -File (Join-Path $copy 'tests/run-contract-tests.ps1')|Out-Null
    Assert ($LASTEXITCODE -eq 0) 'FullUniversalPortableRunnerPasses'
   }
  }
 }
 Write-Output "portable-runner $Case : $script:Count assertions passed"
}finally{
 Remove-Variable CFMockPesterFail,CFMockPesterV3,CFMockPesterUsedConfiguration -Scope Global -ErrorAction SilentlyContinue
 $env:CONTROLFLOW_TEST_PROGRESS=$savedProgress
 $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($full).StartsWith('cf-portable-runner-')){throw 'Unsafe portable runner cleanup'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
$global:LASTEXITCODE=0
