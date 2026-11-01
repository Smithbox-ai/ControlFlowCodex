function Test-SourceSnapshot {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ManifestPath)
    $manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json -AsHashtable
    if($manifest.schema_version -ne 1 -or $manifest.files.Count -ne 118){throw 'INVALID_SOURCE_MANIFEST'}
    $wanted=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($f in $manifest.files){
        if($f.path -isnot [string] -or $f.path -match '(^/|\\|(^|/)\.\.(/|$)|:|^\.git(/|$))' -or -not $wanted.Add($f.path)){throw 'INVALID_SOURCE_PATH'}
        $p=Join-Path $Root $f.path
        if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "SOURCE_INVENTORY_MISMATCH:$($f.path)"}
        $item=Get-Item -LiteralPath $p -Force
        if($item.LinkTarget -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'SOURCE_LINK_FORBIDDEN'}
        if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -cne $f.sha256){throw "SOURCE_HASH_MISMATCH:$($f.path)"}
    }
    $actual=@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_ -cne '.git' -and -not $_.StartsWith('.git/',[StringComparison]::Ordinal)})
    if($actual.Count -ne 118 -or @($actual|Where-Object{-not $wanted.Contains($_)}).Count){throw 'SOURCE_INVENTORY_MISMATCH'}
}
