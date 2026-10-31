param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$TarPath,
    [string]$ExtractedRoot
)
$ErrorActionPreference='Stop'
if ($Commit -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') { throw 'Invalid snapshot commit' }
$git=@(Get-Command git -CommandType Application)[0].Source
$utf8=[Text.UTF8Encoding]::new($false,$true)
function Get-GitBlobHash([IO.Stream]$Content,[long]$Length,[int]$DigestLength) {
    $algorithm=if($DigestLength -eq 40){[Security.Cryptography.HashAlgorithmName]::SHA1}else{[Security.Cryptography.HashAlgorithmName]::SHA256}
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash($algorithm)
    try {
        $hash.AppendData([Text.Encoding]::ASCII.GetBytes("blob $Length`0"))
        $chunk=[byte[]]::new(65536)
        while(($read=$Content.Read($chunk,0,$chunk.Length)) -gt 0){$hash.AppendData($chunk,0,$read)}
        return [Convert]::ToHexString($hash.GetHashAndReset()).ToLowerInvariant()
    } finally {$hash.Dispose()}
}

# Git writes NUL-separated path records. Read raw bytes so whitespace, Unicode,
# and newlines in Git paths cannot be confused with record boundaries.
$info=[Diagnostics.ProcessStartInfo]::new()
$info.FileName=$git; $info.UseShellExecute=$false; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
$info.Environment['GIT_NO_REPLACE_OBJECTS']='1'
foreach($arg in @('-C',$RepoRoot,'ls-tree','-r','-z','--full-tree',$Commit)){[void]$info.ArgumentList.Add($arg)}
$process=[Diagnostics.Process]::new();$process.StartInfo=$info;$buffer=[IO.MemoryStream]::new()
try {
    if(-not $process.Start()){throw 'Could not start Git tree observation'}
    $stderr=$process.StandardError.ReadToEndAsync()
    $process.StandardOutput.BaseStream.CopyTo($buffer)
    $process.WaitForExit();[void]$stderr.GetAwaiter().GetResult()
    if($process.ExitCode -ne 0){throw 'Git tree observation failed'}
    $bytes=$buffer.ToArray()
} finally {$process.Dispose();$buffer.Dispose()}
if ($bytes.Length -eq 0 -or $bytes[-1] -ne 0) { throw 'Incomplete or empty Git tree observation' }
$expected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$directories=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$start=0
for($i=0;$i -lt $bytes.Length;$i++) {
    if($bytes[$i] -ne 0){continue}
    try {$record=$utf8.GetString($bytes,$start,$i-$start)} catch {throw 'Non UTF-8 Git path is unsupported'}
    $start=$i+1
    if($record -cnotmatch '^(?<mode>[0-9]{6}) (?<type>blob|commit) (?<oid>[a-f0-9]{40}(?:[a-f0-9]{24})?)\t(?<path>[\s\S]+)$'){throw 'Invalid Git tree record'}
    $mode=$Matches.mode;$type=$Matches.type;$oid=$Matches.oid;$path=$Matches.path
    if($type -cne 'blob' -or $mode -cnotin @('100644','100755')){throw "Unsupported Git source mode: $path ($mode)"}
    if($oid.Length -ne $Commit.Length -or $path.StartsWith('/') -or $path.Contains('\') -or @($path.Split('/')|Where-Object {$_ -in @('','.','..')}).Count){throw "Unsupported Git source path: $path"}
    if($expected.ContainsKey($path)){throw 'Duplicate Git source path'}
    $expected.Add($path,@{mode=$mode;oid=$oid})
    $parts=$path.Split('/')
    for($n=1;$n -lt $parts.Length;$n++){[void]$directories.Add(($parts[0..($n-1)] -join '/'))}
}
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$seenDirs=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$stream=[IO.File]::OpenRead($TarPath);$reader=[System.Formats.Tar.TarReader]::new($stream)
try {
    while($null -ne ($entry=$reader.GetNextEntry())) {
        $name=$entry.Name
        if($entry.EntryType -eq [System.Formats.Tar.TarEntryType]::GlobalExtendedAttributes) { if($name -cne 'pax_global_header'){throw 'Unexpected global tar metadata'};continue }
        if($entry.EntryType -eq [System.Formats.Tar.TarEntryType]::Directory) {
            $dir=$name.TrimEnd('/')
            if(-not $directories.Contains($dir) -or -not $seenDirs.Add($dir)){throw "Unexpected tar directory: $name"}
            continue
        }
        if($entry.EntryType -notin @([System.Formats.Tar.TarEntryType]::RegularFile,[System.Formats.Tar.TarEntryType]::V7RegularFile)){throw "Unsupported tar entry: $name"}
        if(-not $expected.ContainsKey($name) -or -not $seen.Add($name)){throw "Unexpected tar source: $name"}
        $item=$expected[$name];$executable=([int]$entry.Mode -band 73)
        if(($item.mode -ceq '100644' -and $executable -ne 0) -or ($item.mode -ceq '100755' -and $executable -ne 73)){throw "Tar executable mode differs from Git: $name"}
        $actual=Get-GitBlobHash $entry.DataStream $entry.Length $Commit.Length
        if($actual -cne $item.oid){throw "Tar content differs from Git blob: $name (expected $($item.oid), actual $actual)"}
    }
} finally {$reader.Dispose();$stream.Dispose()}
if($seen.Count -ne $expected.Count){throw 'Tar source inventory differs from Git tree'}
if($ExtractedRoot) {
    $root=[IO.Path]::GetFullPath($ExtractedRoot)
    if(-not [IO.Directory]::Exists($root)){throw 'Extracted source directory is missing'}
    $extracted=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($entry in Get-ChildItem -LiteralPath $root -Force -Recurse) {
        $path=[IO.Path]::GetRelativePath($root,$entry.FullName).Replace('\','/')
        if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Extracted link is unsupported: $path"}
        if($entry.PSIsContainer){if(-not $directories.Contains($path)){throw "Unexpected extracted directory: $path"};continue}
        if(-not $expected.ContainsKey($path) -or -not $extracted.Add($path)){throw "Unexpected extracted file: $path"}
        $item=$expected[$path]
        if(-not $IsWindows) {
            $executable=([int][IO.File]::GetUnixFileMode($entry.FullName) -band 73)
            if(($item.mode -ceq '100644' -and $executable -ne 0) -or ($item.mode -ceq '100755' -and $executable -ne 73)){throw "Extracted executable mode differs from Git: $path"}
        }
        $file=[IO.File]::OpenRead($entry.FullName)
        try {$actual=Get-GitBlobHash $file $file.Length $Commit.Length} finally {$file.Dispose()}
        if($actual -cne $item.oid){throw "Extracted content differs from Git blob: $path"}
    }
    if($extracted.Count -ne $expected.Count){throw 'Extracted source inventory differs from Git tree'}
}
Write-Output "VALID release snapshot at $Commit"
