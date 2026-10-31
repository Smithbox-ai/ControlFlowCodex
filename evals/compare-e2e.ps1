param([Parameter(Mandatory)][string]$NativeDirectory,[string]$V3Directory,[Parameter(Mandatory)][string]$OutputPath,[string]$V4Directory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'e2e-lib.ps1')
if(Test-Path -LiteralPath $OutputPath){throw 'Comparison output must be new; evidence is immutable'}
if([bool]$V3Directory -eq [bool]$V4Directory){throw 'Exactly one V3Directory or V4Directory required'}
$treatment=if($V4Directory){'v4'}else{'v3'}
$treatmentDirectory=if($V4Directory){$V4Directory}else{$V3Directory}
$results=@()
foreach($dir in @($NativeDirectory,$treatmentDirectory)){
    $summary=Get-Content -LiteralPath (Join-Path $dir 'summary.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $results+=@($summary.results)
}
$comparison=Measure-E2EPairs -Results $results -Treatment $treatment
$comparison | ConvertTo-Json -Depth 30 | ForEach-Object {Write-E2EText $OutputPath $_}
Write-Output "Paired comparison: $OutputPath"
