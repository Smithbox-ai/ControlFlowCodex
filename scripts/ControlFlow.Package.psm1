#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:PathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

function Assert-ControlFlowWindowsPath([string]$Path) {
    if ($IsWindows) {
        # GetFullPath is lexical: namespace and 8.3 spellings can refer to the
        # same tree while defeating string containment/source-overlap checks.
        # Fail closed before resolving or touching these Windows path forms.
        $windowsPath = $Path.Replace('/', '\')
        foreach ($prefix in @('\\?\', '\\.\', '\??\', '\\??\', '\Device\')) {
            if ($windowsPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Windows namespace/device alias paths are unsupported' }
        }
        if ($windowsPath.Contains('~')) { throw 'Windows short-name alias paths are unsupported' }
        foreach ($component in $windowsPath.Split('\')) {
            if ($component -in @('', '.', '..')) { continue }
            if ($component.EndsWith('.') -or $component.EndsWith(' ')) { throw 'Windows trailing-dot/space alias paths are unsupported' }
            if ($component -match '^(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(?:\.|$)') { throw 'Windows device alias paths are unsupported' }
        }
    }
}

function Resolve-ControlFlowPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path must not be empty' }
    Assert-ControlFlowWindowsPath $Path
    if ([IO.Path]::IsPathFullyQualified($Path)) { $resolved = $Path }
    else {
        $provider = $null; $drive = $null
        try { $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive) }
        catch { throw 'Path must use the FileSystem provider' }
        if ($provider.Name -ne 'FileSystem') { throw 'Path must use the FileSystem provider' }
    }
    # Recheck filesystem spelling so provider-qualified paths cannot hide aliases.
    Assert-ControlFlowWindowsPath $resolved
    $full = [IO.Path]::GetFullPath($resolved)
    $current = $full
    while ($current) {
        # Native inspection preserves Unix filename bytes and works from any provider.
        try { $attributes = [IO.File]::GetAttributes($current) }
        catch [IO.FileNotFoundException] { $attributes = $null }
        catch [IO.DirectoryNotFoundException] { $attributes = $null }
        if ($null -ne $attributes -and ($attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Link/reparse path is not allowed: $current" }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $full
}

function Test-ControlFlowContained([string]$Path, [string]$Root) {
    $pathFull = Resolve-ControlFlowPath $Path
    $rootFull = (Resolve-ControlFlowPath $Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, $script:PathComparison)
}

function Assert-ControlFlowContained([string]$Path, [string]$Root) {
    $full = Resolve-ControlFlowPath $Path
    $rootFull = Resolve-ControlFlowPath $Root
    if (-not (Test-ControlFlowContained $full $rootFull)) { throw "Path escapes its allowed root: $full ($rootFull)" }
    return $full
}

function Assert-ControlFlowTree([string]$Path) {
    $full = Resolve-ControlFlowPath $Path
    if (Test-Path -LiteralPath $full -PathType Container) {
        foreach ($item in Get-ChildItem -LiteralPath $full -Force -Recurse) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Link/reparse item is not allowed: $($item.FullName)" }
        }
    }
}

function Remove-ControlFlowTree([string]$Path, [string]$Root) {
    $full = Assert-ControlFlowContained $Path $Root
    if (Test-Path -LiteralPath $full) {
        Assert-ControlFlowTree $full
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

function Move-ControlFlowTree([string]$Source, [string]$Destination, [string]$Root) {
    $src = Assert-ControlFlowContained $Source $Root
    $dst = Assert-ControlFlowContained $Destination $Root
    Assert-ControlFlowTree $src
    if (Test-Path -LiteralPath $dst) { throw "Move destination already exists: $dst" }
    Move-Item -LiteralPath $src -Destination $dst
}

function Get-ControlFlowInventory([string]$SourceRoot) {
    $root = Resolve-ControlFlowPath $SourceRoot
    $path = Assert-ControlFlowContained (Join-Path $root 'scripts/package-inventory.json') $root
    $inventory = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in @('required', 'optional', 'exclude', 'obsolete')) {
        if (-not $inventory.ContainsKey($key) -or $inventory[$key] -isnot [array]) { throw "Inventory $key must be an array" }
        foreach ($entry in $inventory[$key]) {
            if ($entry -isnot [string] -or $entry -notmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$' -or @($entry.Split('/') | Where-Object { $_ -in '.', '..' }).Count) { throw "Invalid inventory path: $entry" }
        }
    }
    return $inventory
}

function Assert-ControlFlowNoObsoleteFiles([string]$SourceRoot, [Collections.IDictionary]$Inventory) {
    $root = Resolve-ControlFlowPath $SourceRoot
    foreach ($entry in $Inventory.obsolete) {
        $path = Assert-ControlFlowContained (Join-Path $root $entry) $root
        # A forbidden directory is rejected even when empty: any old child
        # would otherwise re-enter the package on a later recursive copy.
        if (Test-Path -LiteralPath $path) { throw "Obsolete v2 package path is forbidden: $entry" }
    }
}

function Get-ControlFlowPackageFiles([string]$SourceRoot, [ValidateSet('Universal','NativeLegacy', IgnoreCase=$false)][string]$Flavor = 'Universal') {
    $root = Resolve-ControlFlowPath $SourceRoot
    $inventory = Get-ControlFlowInventory $root
    Assert-ControlFlowNoObsoleteFiles $root $inventory
    $files = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($inventory.required) + @($inventory.optional)) {
        if ($Flavor -ceq 'NativeLegacy' -and $entry -ceq 'plugin.json') { continue }
        $path = Assert-ControlFlowContained (Join-Path $root $entry) $root
        if (-not (Test-Path -LiteralPath $path)) {
            if ($entry -in $inventory.required) { throw "Required package item is missing: $entry" }
            continue
        }
        Assert-ControlFlowTree $path
        $items = if (Test-Path -LiteralPath $path -PathType Container) { @(Get-ChildItem -LiteralPath $path -File -Recurse -Force) } else { @(Get-Item -LiteralPath $path) }
        foreach ($item in $items) {
            $relative = [IO.Path]::GetRelativePath($root, $item.FullName).Replace('\', '/')
            if ($relative.Split('/') -contains '.git' -or $relative.Split('/') -contains '.vs') { throw "Working state in package inventory: $relative" }
            $excluded = $false
            foreach ($exclude in $inventory.exclude) { if ($relative -eq $exclude -or $relative.StartsWith($exclude + '/', [StringComparison]::Ordinal)) { $excluded = $true } }
            if (-not $excluded) { $null = $files.Add($relative) }
        }
    }
    return @($files)
}

function ConvertTo-ControlFlowCanonical([object]$Value) {
    if ($Value -is [Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) { $ordered[$key] = ConvertTo-ControlFlowCanonical $Value[$key] }
        return $ordered
    }
    if ($Value -is [array]) {
        $array = @($Value | ForEach-Object { ConvertTo-ControlFlowCanonical $_ })
        return ,$array
    }
    return $Value
}

function Assert-ControlFlowPackage([string]$SourceRoot, [string]$Version, [ValidateSet('Universal','NativeLegacy', IgnoreCase=$false)][string]$Flavor = 'Universal') {
    $root = Resolve-ControlFlowPath $SourceRoot
    $null = Get-ControlFlowPackageFiles $root -Flavor $Flavor
    $compat = Get-Content -LiteralPath (Join-Path $root '.codex-plugin/plugin.json') -Raw | ConvertFrom-Json -AsHashtable
    if (-not $compat.ContainsKey('skills') -or $compat.skills -cnotin @('./skills', './skills/')) { throw 'Compatibility skills must point to the portable skills directory' }
    if ($Flavor -ceq 'Universal') {
        $portable = Get-Content -LiteralPath (Join-Path $root 'plugin.json') -Raw | ConvertFrom-Json -AsHashtable
        if ($portable.name -cne $compat.name -or $portable.version -cne $compat.version) { throw 'Portable/compatibility manifest identity mismatch' }
        if (-not $portable.ContainsKey('extensions') -or -not $portable.extensions.ContainsKey('com.openai')) { throw 'Missing extensions.com.openai settings' }
        $openai = $portable.extensions['com.openai']
        foreach ($key in $openai.Keys) {
            if (-not $compat.ContainsKey($key)) { throw "Compatibility manifest lacks OpenAI setting: $key" }
            $a = ConvertTo-ControlFlowCanonical $openai[$key] | ConvertTo-Json -Depth 100 -Compress
            $b = ConvertTo-ControlFlowCanonical $compat[$key] | ConvertTo-Json -Depth 100 -Compress
            if ($a -cne $b) { throw "Portable/compatibility settings differ: $key" }
        }
        foreach ($key in @('interface', 'hooks')) {
            if ($compat.ContainsKey($key) -and -not $openai.ContainsKey($key)) { throw "Portable extension omits compatibility setting: $key" }
        }
    } else {
        if ($compat.name -cne 'controlflow-codex') { throw 'NativeLegacy is restricted to ControlFlowCodex' }
        if (Test-Path -LiteralPath (Join-Path $root 'plugin.json')) { throw 'NativeLegacy must not contain root AgentPlugin plugin.json' }
        Assert-ControlFlowTree $root
        # Legacy discovery is recursive. Bound this flavor to the existing four
        # skill entries and no MCP/apps capabilities, regardless of defaults.
        foreach ($key in $compat.Keys) {
            if ($key -cnotin @('name','version','description','author','homepage','repository','license','keywords','skills','interface','hooks')) { throw "NativeLegacy does not allow manifest capability/key: $key" }
        }
        if (-not $compat.ContainsKey('hooks') -or $compat.hooks -cne './hooks/hooks.json') { throw 'NativeLegacy requires the existing hooks/hooks.json declaration' }
        $wanted = @('controlflow','controlflow-plan','controlflow-review','controlflow-verify')
        $skillRoot = Join-Path $root 'skills'
        $actual = @(Get-ChildItem -LiteralPath $skillRoot -Directory -Force | ForEach-Object Name)
        if (@(Compare-Object $wanted $actual -CaseSensitive).Count) { throw 'NativeLegacy requires exactly the four existing skill directories' }
        foreach ($extraRoot in @('commands','.codex-plugin/migrated-command-skills')) {
            if (Test-Path -LiteralPath (Join-Path $root $extraRoot)) { throw "NativeLegacy does not allow additional skill/command roots: $extraRoot" }
        }
        $skillFiles = @(Get-ChildItem -LiteralPath $root -File -Force -Recurse | Where-Object Name -IEQ 'SKILL.md')
        if ($skillFiles.Count -ne 4) { throw 'NativeLegacy does not allow nested or extra SKILL.md entries' }
        foreach ($file in $skillFiles) {
            if ($file.Name -cne 'SKILL.md' -or $file.Directory.Parent.FullName -cne $skillRoot) { throw 'NativeLegacy requires direct skill entry paths' }
        }
        foreach ($file in Get-ChildItem -LiteralPath $root -File -Force -Recurse) {
            if ($file.Name -match '^(?:\.?mcp(?:[.-].*)?|mcpServers.*|\.?apps?\.json)$') { throw "NativeLegacy does not allow MCP/apps configs: $($file.Name)" }
        }
        $portable = $compat
        $openai = $compat
    }
    if ($portable.name -notmatch '^[a-z0-9][a-z0-9-]*$' -or $portable.version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') { throw 'Invalid plugin identity/version' }
    if ($Version -and $portable.version -cne $Version) { throw "Requested version $Version differs from manifest $($portable.version)" }
    foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $root 'skills') -Directory) {
        if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md') -PathType Leaf)) { throw "Skill entry is missing SKILL.md: $($skill.Name)" }
    }
    foreach ($key in @('composerIcon', 'logo')) {
        if ($openai.ContainsKey('interface') -and $openai.interface.ContainsKey($key)) {
            $null = Assert-ControlFlowContained (Join-Path $root $openai.interface[$key]) $root
            if (-not (Test-Path -LiteralPath (Join-Path $root $openai.interface[$key]) -PathType Leaf)) { throw "Missing interface asset: $key" }
        }
    }
    if ($openai.ContainsKey('hooks')) {
        $hookPath = Assert-ControlFlowContained (Join-Path $root $openai.hooks) $root
        $null = Get-Content -LiteralPath $hookPath -Raw | ConvertFrom-Json
    }
    return $portable
}

function Copy-ControlFlowPackage([string]$SourceRoot, [string]$Destination, [ValidateSet('Universal','NativeLegacy', IgnoreCase=$false)][string]$Flavor = 'Universal') {
    $root = Resolve-ControlFlowPath $SourceRoot
    $dest = Resolve-ControlFlowPath $Destination
    if ($root.Equals($dest, $script:PathComparison) -or (Test-ControlFlowContained $dest $root) -or (Test-ControlFlowContained $root $dest)) { throw 'Source and package destination overlap' }
    $null = Assert-ControlFlowPackage $root -Flavor $Flavor
    if (Test-Path -LiteralPath $dest) { throw "Package destination already exists: $dest" }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    foreach ($relative in Get-ControlFlowPackageFiles $root -Flavor $Flavor) {
        $target = Assert-ControlFlowContained (Join-Path $dest $relative) $dest
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $target
    }
    $null = Assert-ControlFlowPackage $dest -Flavor $Flavor
}

Export-ModuleMember -Function Resolve-ControlFlowPath, Test-ControlFlowContained, Assert-ControlFlowContained, Assert-ControlFlowTree, Remove-ControlFlowTree, Move-ControlFlowTree, Get-ControlFlowInventory, Assert-ControlFlowNoObsoleteFiles, Get-ControlFlowPackageFiles, Assert-ControlFlowPackage, Copy-ControlFlowPackage
