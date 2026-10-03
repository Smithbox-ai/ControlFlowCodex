param([Parameter(Mandatory)][string]$NativeDirectory,[Parameter(Mandatory)][string]$V3Directory,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'e2e-lib.ps1')
if(Test-Path -LiteralPath $OutputPath){throw 'Comparison output must be new; evidence is immutable'}
$results=@()
foreach($dir in @($NativeDirectory,$V3Directory)){
    $summary=Get-Content -LiteralPath (Join-Path $dir 'summary.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $results+=@($summary.results)
}
$comparison=Measure-E2EPairs -Results $results
$comparison | ConvertTo-Json -Depth 30 | ForEach-Object {Write-E2EText $OutputPath $_}
Write-Output "Paired comparison: $OutputPath"
