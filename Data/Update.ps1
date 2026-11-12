$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path $PSScriptRoot
$repo = 'KingBobVideos/ultimate-plus'
$api = "https://api.github.com/repos/$repo"
$state = Join-Path $root '.ultimate-plus-update'
[void][IO.Directory]::CreateDirectory($state)

function Get-Json($url) {
    Invoke-RestMethod -Uri $url -Headers @{'User-Agent'='UltimatePlus-Updater'}
}

function Get-Tree($sha) {
    $entries = @{}
    if ($sha) {
        $cache = Join-Path $state ("tree-"+$sha+".json")
        if (![IO.File]::Exists($cache)) {
            $tree = Get-Json "$api/git/trees/$sha"
            if ($tree.truncated -or $tree.sha -ne $sha) {throw "Incomplete file list from GitHub. Retry later."}
            [IO.File]::WriteAllText("$cache.new", (ConvertTo-Json -InputObject $tree.tree -Depth 3 -Compress))
            [IO.File]::Move("$cache.new",$cache)
        }
        foreach ($item in (ConvertFrom-Json ([IO.File]::ReadAllText($cache)))) {
            $entries[$item.path] = $item
        }
    }
    return $entries
}

function Is-Distributed($path) {
    $path -in 'Data','README.md','Update Ultimate+.cmd','Play Ultimate+.cmd' -or
    $path.StartsWith('Data/')
}

function Find-Changes($prefix, $oldTree, $newTree) {
    if ($oldTree -eq $newTree) { return }
    $before = Get-Tree $oldTree
    $after = Get-Tree $newTree
    foreach ($name in (@($before.Keys) + @($after.Keys) | Sort-Object -Unique)) {
        $path = "$prefix$name"
        if (!(Is-Distributed $path)) { continue }
        $a = $before[$name]
        $b = $after[$name]
        if ($a.sha -eq $b.sha) { continue }
        if ($a.type -eq 'tree' -or $b.type -eq 'tree') {
            $old = if ($a.type -eq 'tree') { $a.sha }
            $new = if ($b.type -eq 'tree') { $b.sha }
            Find-Changes "$path/" $old $new
        }
        if ($a.type -eq 'blob' -or $b.type -eq 'blob') {
            [pscustomobject]@{Path=$path; Old=$(if ($a.type -eq 'blob') {$a.sha}); New=$(if ($b.type -eq 'blob') {$b.sha})}
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
    if ($base -notmatch '^[0-9a-f]{40}$') {
        if (!(Test-Path -LiteralPath "$root/Data/Eden/user/sdmc/ultimate/mods")) {throw 'Extract the full Ultimate+ download first.'}
        # Earliest fully unpacked public build. Later changes are checked by content.
        $base = '5be58f222e09e06f1b4999541f2fb0aeec7c81e6'
    }
    Write-Host 'Checking Ultimate+ for updates...'
    $head = Get-Json "$api/commits/main"
    if ($head.sha -eq $base) { Write-Host 'Ultimate+ is up to date.'; return }
    $eden = Join-Path $root 'Data/Eden/eden.exe'
    if (Get-Process eden -ErrorAction SilentlyContinue | Where-Object Path -eq $eden) {throw 'Close this copy of Eden and run the updater again.'}
    $old = Get-Json "$api/commits/$base"
    $changes = @(Find-Changes '' $old.commit.tree.sha $head.commit.tree.sha)
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
                & curl.exe -fsSL --retry 3 -o "$cached.part" "https://raw.githubusercontent.com/$repo/$($head.sha)/$encoded"
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
    [IO.File]::WriteAllText("$marker.new",$head.sha)
    if ([IO.File]::Exists($marker)) {[IO.File]::Replace("$marker.new",$marker,"$marker.previous")} else {[IO.File]::Move("$marker.new",$marker)}
    foreach ($change in $pending) {if ($change.New) {[IO.File]::Delete((Join-Path $stage $change.New))}}
    Write-Host "Ultimate+ is up to date. Applied $(@($pending | Where-Object {$_}).Count) file changes."
} catch {
    Write-Host "Update stopped: $($_.Exception.Message)"
    exit 1
} finally {if ($lock) {$lock.Dispose()}}
