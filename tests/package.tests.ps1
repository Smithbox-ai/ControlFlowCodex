$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp = Join-Path $tempBase ('controlflow-package-' + [guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Fingerprint([string]$Root) {
    return (@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')+':'+(Get-FileHash -LiteralPath $_.FullName).Hash
    }) -join "`n")
}
$obsolete=@('scripts/validate-plan.ps1','scripts/detect-drift.ps1','schemas/plan-meta.schema.json','plans/templates/plan.md','plans/templates/plan.meta.json','plans/examples/auth-migration-plan.md','plans/artifacts/auth-migration','evals/run-evals.ps1','evals/legacy','evals/cases','evals/baseline','evals/expected','tests/validate-plan.tests.ps1','tests/detect-drift.tests.ps1','tests/fixtures/plan-metadata')
function Assert-NoObsolete([string]$Root,[string]$Label) {
    foreach($relative in $obsolete){Assert (-not (Test-Path -LiteralPath (Join-Path $Root $relative))) "$Label contains obsolete v2 path: $relative"}
}
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    $packageScript = Join-Path $repoRoot 'scripts/package.ps1'
    Assert (Test-Path -LiteralPath $packageScript) 'Package helper is missing; releases must inspect the extracted archive'
    Import-Module (Join-Path $repoRoot 'scripts/ControlFlow.Package.psm1') -Force -DisableNameChecking
    $inventory=Get-ControlFlowInventory $repoRoot
    Assert (@(Compare-Object $obsolete $inventory.obsolete).Count -eq 0) 'Release inventory lost the explicit obsolete-file policy'
    Assert-NoObsolete $repoRoot 'Source repository'
    & $packageScript -OutputDirectory (Join-Path $temp 'dist') | Out-Null
    $version = (Get-Content (Join-Path $repoRoot 'plugin.json') -Raw | ConvertFrom-Json).version
    $zip = Join-Path $temp "dist/controlflow-codex-$version.zip"
    Assert (Test-Path -LiteralPath $zip) 'Package ZIP was not produced'
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $temp 'extracted')
    $extracted = Join-Path $temp 'extracted/controlflow-codex'
    foreach ($file in @('plugin.json', '.codex-plugin/plugin.json', 'plans/templates/plan.meta.v3.json', 'plans/examples/small-v3.meta.json', 'scripts/validate-contract.ps1', 'scripts/install.ps1', 'scripts/ControlFlow.Package.psm1')) {
        Assert (Test-Path -LiteralPath (Join-Path $extracted $file) -PathType Leaf) "Extracted package lost nested file: $file"
    }
    $portable = Get-Content (Join-Path $extracted 'plugin.json') -Raw | ConvertFrom-Json
    $compat = Get-Content (Join-Path $extracted '.codex-plugin/plugin.json') -Raw | ConvertFrom-Json
    Assert ($portable.version -eq $compat.version -and $portable.name -eq $compat.name) 'Portable and compatibility manifests differ'
    Assert ($portable.extensions.'com.openai'.interface.displayName -eq $compat.interface.displayName) 'Portable manifest lacks the OpenAI interface extension'
    Assert (-not (Test-Path -LiteralPath (Join-Path $extracted '.git'))) 'Package contains Git working state'
    Assert-NoObsolete $extracted 'Extracted ZIP'
    & (Join-Path $extracted 'scripts/validate-contract.ps1') -Path (Join-Path $extracted 'plans/examples/small-v3.meta.json') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Extracted v3 SMALL example failed validation' }
    $installHome = Join-Path $temp 'home'
    & (Join-Path $extracted 'scripts/install.ps1') -HomeRoot $installHome -Force | Out-Null
    $installedRoot=Join-Path $installHome 'plugins/controlflow-codex'
    Assert (Test-Path (Join-Path $installedRoot 'plans/examples/small-v3.meta.json')) 'Extracted installer lost v3 SMALL example metadata'
    Assert-NoObsolete $installedRoot 'Installed ZIP'
    # Exercise every known obsolete exact file and directory child without
    # changing the real checkout. Source, extracted ZIP and installer share
    # this guard; installer rejection must preserve all previously owned bytes.
    $installedBefore=Fingerprint $installedRoot
    $marketPath=Join-Path $installHome '.agents/plugins/marketplace.json'
    $marketBefore=[Convert]::ToBase64String([IO.File]::ReadAllBytes($marketPath))
    foreach($relative in $obsolete){
        $isDirectory=$relative -in @('plans/artifacts/auth-migration','evals/legacy','evals/cases','evals/baseline','evals/expected','tests/fixtures/plan-metadata')
        $injectPath=Join-Path $extracted $relative
        $leaf=if($isDirectory){Join-Path $injectPath 'nested/obsolete.txt'}else{$injectPath}
        New-Item -ItemType Directory -Path (Split-Path $leaf -Parent) -Force|Out-Null
        Set-Content -LiteralPath $leaf 'obsolete v2 sentinel'
        $rejected=$false
        try{$null=Assert-ControlFlowPackage $extracted}catch{$rejected=$_.Exception.Message -match 'Obsolete v2 package path'}
        Assert $rejected "Extracted/source package accepted obsolete exact path or child: $relative"
        $rejected=$false
        try{& (Join-Path $extracted 'scripts/install.ps1') -HomeRoot $installHome -Force|Out-Null}catch{$rejected=$_.Exception.Message -match 'Obsolete v2 package path'}
        Assert $rejected "Installer accepted an obsolete package source: $relative"
        Assert ((Fingerprint $installedRoot) -ceq $installedBefore -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($marketPath)) -ceq $marketBefore) "Obsolete source changed installed bytes or registration: $relative"
        if($isDirectory){Remove-ControlFlowTree $injectPath $temp}else{Remove-Item -LiteralPath (Assert-ControlFlowContained $injectPath $temp)}
    }
    # Obsolete files must stop archive production, rather than being silently
    # excluded from a source checkout that still ships a stale workflow.
    $legacy=Join-Path $extracted 'plans/templates/plan.md';Set-Content -LiteralPath $legacy '# obsolete v2'
    $rejected=$false
    try{& (Join-Path $extracted 'scripts/package.ps1') -OutputDirectory (Join-Path $temp 'obsolete-dist')|Out-Null}catch{$rejected=$_.Exception.Message -match 'Obsolete v2 package path'}
    Assert ($rejected -and -not (Test-Path -LiteralPath (Join-Path $temp 'obsolete-dist'))) 'Package helper published an obsolete source archive'
    Remove-Item -LiteralPath (Assert-ControlFlowContained $legacy $temp)
    # The same inventory must include declared optional components and exclude
    # development output when packaging a copied/extracted source.
    New-Item -ItemType Directory -Path (Join-Path $extracted 'hooks/nested'), (Join-Path $extracted 'evals/results') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $extracted 'hooks/nested/portable.txt') 'optional component'
    Set-Content -LiteralPath (Join-Path $extracted 'evals/results/private-run.json') 'development output'
    & (Join-Path $extracted 'scripts/package.ps1') -OutputDirectory (Join-Path $temp 'repacked') | Out-Null
    Expand-Archive -LiteralPath (Join-Path $temp "repacked/controlflow-codex-$version.zip") -DestinationPath (Join-Path $temp 'repacked-extracted')
    Assert (Test-Path -LiteralPath (Join-Path $temp 'repacked-extracted/controlflow-codex/hooks/nested/portable.txt')) 'Optional hooks component was lost'
    Assert (-not (Test-Path -LiteralPath (Join-Path $temp 'repacked-extracted/controlflow-codex/evals/results'))) 'Package leaked development results'

    $compatPath = Join-Path $extracted '.codex-plugin/plugin.json'
    $compatBytes = [IO.File]::ReadAllBytes($compatPath)
    $badCompat = Get-Content -LiteralPath $compatPath -Raw | ConvertFrom-Json
    $badCompat.skills = '../outside-skills/'
    $badCompat | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $compatPath
    $skillsRejected = $false
    try { & (Join-Path $extracted 'scripts/package.ps1') -OutputDirectory (Join-Path $temp 'bad-skills') | Out-Null } catch { $skillsRejected = $true }
    Assert $skillsRejected 'Compatibility manifest accepted skills outside the portable directory'
    [IO.File]::WriteAllBytes($compatPath, $compatBytes)

    # Missing the required v3 example must fail before installer replacement.
    $installedManifest = Join-Path $installHome 'plugins/controlflow-codex/plugin.json'
    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($installedManifest))
    Remove-Item -LiteralPath (Join-Path $extracted 'plans/examples/small-v3.meta.json')
    $missingRejected = $false
    try { & (Join-Path $extracted 'scripts/install.ps1') -HomeRoot $installHome -Force | Out-Null } catch { $missingRejected = $true }
    Assert $missingRejected 'Missing required v3 source example was silently skipped'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($installedManifest)) -eq $before -and (Fingerprint $installedRoot) -ceq $installedBefore) 'Missing v3 source example changed installed bytes'
    $rejected = $false
    try { & $packageScript -OutputDirectory (Join-Path $temp 'wrong-version') -Version '99.0.0' | Out-Null } catch { $rejected = $true }
    Assert $rejected 'Package accepted a version differing from its manifest'
} finally {
    $resolved = [IO.Path]::GetFullPath($temp)
    if (-not $resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Output 'VALID package archive roundtrip and extracted install contract'
