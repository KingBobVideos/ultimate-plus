$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path $PSScriptRoot
$repo = 'KingBobVideos/ultimate-plus'
$indexUrl = "https://raw.githubusercontent.com/$repo/update-index"
$state = Join-Path $root '.ultimate-plus-update'
[void][IO.Directory]::CreateDirectory($state)

function Get-FileIndex($revision) {
    if ($revision -notmatch '^[0-9a-f]{40}$') {throw 'Invalid update revision.'}
    $file = Join-Path $state "$revision.json.gz"
    if (![IO.File]::Exists($file)) {
        & curl.exe -fsSL --retry 3 -o "$file.part" "$indexUrl/$revision.json.gz"
        if ($LASTEXITCODE) {throw "Could not download the file list for $revision. Run the updater again."}
        [IO.File]::Move("$file.part",$file)
    }
    try {
        $compressed = [IO.File]::OpenRead($file)
        try {
            $gzip = New-Object IO.Compression.GZipStream($compressed,[IO.Compression.CompressionMode]::Decompress)
            $reader = New-Object IO.StreamReader($gzip)
            try {
                Add-Type -AssemblyName System.Web.Extensions
                $json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
                $json.MaxJsonLength = 67108864
                return ,$json.DeserializeObject($reader.ReadToEnd())
            } finally {$reader.Dispose()}
        } finally {$compressed.Dispose()}
    } catch {
        [IO.File]::Delete($file)
        throw
    }
}

function Find-Changes($before,$after) {
    foreach ($path in $after.Keys) {
        if ($before[$path] -ne $after[$path]) {
            [pscustomobject]@{Path=$path; Old=$before[$path]; New=$after[$path]}
        }
    }
    foreach ($path in $before.Keys) {
        if (!$after.ContainsKey($path)) {
            [pscustomobject]@{Path=$path; Old=$before[$path]; New=$null}
        }
    }
}
function Blob-Id($path) {
    if (![IO.File]::Exists($path)) {return ''}
    $s = [IO.File]::OpenRead($path)
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        $header = [Text.Encoding]::ASCII.GetBytes("blob $($s.Length)" + [char]0)
        [void]$sha.TransformBlock($header,0,$header.Length,$header,0)
        $buf = New-Object byte[] 1048576
        while (($n = $s.Read($buf,0,$buf.Length)) -gt 0) {
            [void]$sha.TransformBlock($buf,0,$n,$buf,0)
        }
        [void]$sha.TransformFinalBlock($buf,0,0)
        [BitConverter]::ToString($sha.Hash).Replace('-','').ToLowerInvariant()
    } finally {$s.Dispose(); $sha.Dispose()}
}

function Local-Path($relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (!$path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {throw "Invalid package path: $relative"}
    for ($p=$path; $p -ne $root; $p=[IO.Path]::GetDirectoryName($p)) {
        if ((Test-Path -LiteralPath $p) -and ((Get-Item -Force -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Update path is redirected: $p"
        }
    }
    $path
}

$lock = $null
try {
    $lock = [IO.File]::Open((Join-Path $state 'lock'),'OpenOrCreate','ReadWrite','None')
    $marker = Join-Path $state 'revision'
    $stamp = Join-Path $root 'installer/revision.txt'
    $base = if (Test-Path -LiteralPath $marker) { [IO.File]::ReadAllText($marker).Trim() }
        elseif (Test-Path -LiteralPath $stamp) { [IO.File]::ReadAllText($stamp).Trim() }
    if ([string]$base -notmatch '^[0-9a-f]{40}$') {
        if (!(Test-Path -LiteralPath "$root/Data/Eden/user/sdmc/ultimate/mods")) {throw 'Extract the full Ultimate+ download first.'}
        # Earliest fully unpacked public build. Later changes are checked by content.
        $base = '5be58f222e09e06f1b4999541f2fb0aeec7c81e6'
    }
    Write-Host 'Checking Ultimate+ for updates...'
    $head = ((& curl.exe -fsSL --retry 3 "$indexUrl/latest.txt") -join "").Trim()
    if ($LASTEXITCODE -ne 0 -or $head -notmatch "^[0-9a-f]{40}$") {throw "Could not read the latest Ultimate+ version."}
    if ($head -eq $base) { Write-Host 'Ultimate+ is up to date.'; return }
    $eden = Join-Path $root 'Data/Eden/eden.exe'
    if (Get-Process eden -ErrorAction SilentlyContinue | Where-Object Path -eq $eden) {throw 'Close this copy of Eden and run the updater again.'}
    $changes = @(Find-Changes (Get-FileIndex $base) (Get-FileIndex $head))
    $stage = Join-Path $state 'downloads'
    [void][IO.Directory]::CreateDirectory($stage)
    $backup = Join-Path $state ('backup-'+[guid]::NewGuid())
    $pending = foreach ($change in $changes) {
        $path = Local-Path $change.Path
        $current = Blob-Id $path
        if ($current -eq [string]$change.New) {continue}
        if ($change.New) {
            $cached = Join-Path $stage $change.New
            if ((Blob-Id $cached) -ne $change.New) {
                Write-Host "Downloading $($change.Path)"
                $encoded = (($change.Path.Split('/') | ForEach-Object {[Uri]::EscapeDataString($_)}) -join '/')
                & curl.exe -fsSL --retry 3 -o "$cached.part" "https://raw.githubusercontent.com/$repo/$($head)/$encoded"
                if ($LASTEXITCODE -ne 0 -or (Blob-Id "$cached.part") -ne $change.New) {throw "Could not verify $($change.Path). Run the updater again."}
                [IO.File]::Copy("$cached.part",$cached,$true)
                [IO.File]::Delete("$cached.part")
            }
        }
        if ($current -and $current -ne $change.Old) {
            $copy = Join-Path $backup $change.Path
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($copy))
            [IO.File]::Copy($path,$copy)
            Write-Host "Saved your edited file under $backup"
        }
        $change
    }
    foreach ($change in $pending) {
        $path = Local-Path $change.Path
        if ($change.New) {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
            [IO.File]::Copy((Join-Path $stage $change.New),$path,$true)
        } else { [IO.File]::Delete($path) }
    }
    [IO.File]::WriteAllText("$marker.new",$head)
    if ([IO.File]::Exists($marker)) {[IO.File]::Replace("$marker.new",$marker,"$marker.previous")} else {[IO.File]::Move("$marker.new",$marker)}
    foreach ($change in $pending) {if ($change.New) {[IO.File]::Delete((Join-Path $stage $change.New))}}
    Write-Host "Ultimate+ is up to date. Applied $(@($pending | Where-Object {$_}).Count) file changes."
} catch {
    Write-Host "Update stopped: $($_.Exception.Message)"
    exit 1
} finally {if ($lock) {$lock.Dispose()}}
