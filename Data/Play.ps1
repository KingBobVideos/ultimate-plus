$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$eden = Join-Path $PSScriptRoot 'Eden'
$userDir = Join-Path $eden 'user'
$exe = Join-Path $eden 'eden.exe'
$ini = Join-Path $userDir 'config/qt-config.ini'
$catalog = Get-Content -Raw -LiteralPath "$PSScriptRoot/SmashContent.json" | ConvertFrom-Json
$utf8 = New-Object Text.UTF8Encoding($false)

function Pick($title, $filter, [bool]$multiple = $false) {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = $title
        $dialog.Filter = $filter
        $dialog.Multiselect = $multiple
        if ($dialog.ShowDialog() -eq 'OK') { $dialog.FileNames }
    } finally { $dialog.Dispose() }
}
function Notice($message) {
    [void][Windows.Forms.MessageBox]::Show($message, 'Ultimate+')
}
function Read-NspIds($path) {
    $stream = [IO.File]::OpenRead($path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'PFS0') {return}
        $count = $reader.ReadUInt32()
        $size = $reader.ReadUInt32()
        $start = 16L + 24L * $count
        if ($count -gt 65536 -or $size -gt 8MB -or $start + $size -gt $stream.Length) {return}
        $stream.Position = $start
        $names = [Text.Encoding]::ASCII.GetString($reader.ReadBytes($size)).Split([char]0)
        foreach ($name in $names) { if ($name -match '^([a-fA-F0-9]{32})\.nca$') {$Matches[1]} }
    } finally { $reader.Dispose() }
}
function Has-Content($item, $ids) {
    foreach ($id in $item.ids) {if (!$ids.ContainsKey($id)) {return $false}}
    return $true
}
function Save-ExternalDir($folder) {
    $folder = $folder.Replace('\','/')
    $text = if ([IO.File]::Exists($ini)) {[IO.File]::ReadAllText($ini)} else {''}
    $pattern = '(?m)^Paths\\external_content_dirs\\(\d+)\\path=(.*)\r?$'
    $highest = 0
    foreach ($entry in [regex]::Matches($text,$pattern)) {
        if ($entry.Groups[2].Value.Trim().Trim('"').Replace('\','/').TrimEnd('/') -eq $folder.TrimEnd('/')) {return}
        $highest = [Math]::Max($highest,[int]$entry.Groups[1].Value)
    }
    $sizePattern = '(?m)^Paths\\external_content_dirs\\size=(\d+)\r?$'
    $sizeMatch = [regex]::Match($text,$sizePattern)
    if ($sizeMatch.Success) {$highest=[Math]::Max($highest,[int]$sizeMatch.Groups[1].Value)}
    $index = $highest+1
    $record = "Paths\external_content_dirs\$index\path=$folder`r`nPaths\external_content_dirs\size=$index"
    if ($sizeMatch.Success) {$text=$text.Remove($sizeMatch.Index,$sizeMatch.Length).Insert($sizeMatch.Index,$record)}
    else {
        $section=[regex]::Match($text,'(?m)^\[UI\]\r?$')
        if ($section.Success) {$text=$text.Insert($section.Index+$section.Length,"`n$record`r`n")}
        else {$text+="`r`n[UI]`r`n$record`r`n"}
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ini))
    $tmp=$ini+'.ultimate-plus.tmp'
    [IO.File]::WriteAllText($tmp,$text,$utf8)
    if ([IO.File]::Exists($ini)) {[IO.File]::Replace($tmp,$ini,$ini+'.ultimate-plus.bak')}
    else {[IO.File]::Move($tmp,$ini)}
}
function Add-Package($path, $wanted, $known) {
    $ids=@{}
    foreach ($id in (Read-NspIds $path)) {$ids[$id]=$true}
    $found=@($wanted | Where-Object { Has-Content $_ $ids })
    if (!$found.Count) {return $false}
    Save-ExternalDir ([IO.Path]::GetDirectoryName($path))
    foreach ($id in $ids.Keys) {$known[$id]=$true}
    return $true
}
function Read-DlcFolder($folder, $known) {
    foreach ($file in Get-ChildItem -LiteralPath $folder -Recurse -File -Filter '*.nsp' -ErrorAction SilentlyContinue) {
        try { foreach ($id in (Read-NspIds $file.FullName)) {$known[$id]=$true} } catch {continue}
    }
}
function Pick-DlcFolder {
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = 'Choose the folder containing your Smash DLC. Optional DLC can be in the same folder.'
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq 'OK') {$dialog.SelectedPath}
    } finally {$dialog.Dispose()}
}
function Test-ProdKeys($path) {
    if (![IO.File]::Exists($path)) {return $false}
    return [bool](Select-String -LiteralPath $path -Pattern '^\s*header_key\s*=\s*[a-fA-F0-9]{64}\s*$' -Quiet)
}
function Play {
    if (![IO.File]::Exists($exe)) {throw 'Extract the complete Ultimate+ folder before running Play.'}
    foreach ($instance in Get-Process -Name 'eden','eden-cli' -ErrorAction SilentlyContinue) {
        if (!$instance.HasExited) {
            Write-Host "Closing $($instance.ProcessName) (PID $($instance.Id))..."
            try { $instance.Kill() } catch { if (!$instance.HasExited) { throw } }
            if (!$instance.WaitForExit(10000)) { throw "Eden process $($instance.Id) is still running." }
        }
    }
    $keys = Join-Path $userDir 'keys'
    [void][IO.Directory]::CreateDirectory($keys)
    $prod = Join-Path $keys 'prod.keys'
    while (!(Test-ProdKeys $prod)) {
        $file = Pick 'Locate your prod.keys for Eden' 'Production keys (prod.keys)|prod.keys'
        if (!$file) {return}
        if (!(Test-ProdKeys $file)) { Notice 'This file does not contain a valid header_key. Choose your prod.keys.'; continue }
        [IO.File]::Copy($file,$prod,$true)
        $titles = Join-Path ([IO.Path]::GetDirectoryName($file)) 'title.keys'
        if ([IO.File]::Exists($titles) -and ![IO.File]::Exists("$keys/title.keys")) {[IO.File]::Copy($titles,"$keys/title.keys")}
    }
    $saved = Join-Path $userDir 'smash-game.txt'
    $game = $env:ULTIMATE_PLUS_GAME
    if (!$game -and [IO.File]::Exists($saved)) {$game=[IO.File]::ReadAllText($saved).Trim()}
    if (!$game -or ![IO.File]::Exists($game)) {$game=Pick 'Choose your Smash Ultimate base game' 'Switch game (*.xci;*.nsp)|*.xci;*.nsp'}
    if (!$game) {return}
    if ([IO.Path]::GetExtension($game) -notin '.nsp','.xci') {throw 'Choose a Smash base-game XCI or NSP.'}
    $game=(Get-Item -LiteralPath $game).FullName
    [IO.File]::WriteAllText($saved,$game,$utf8)
    $known=@{}
    $config=if ([IO.File]::Exists($ini)) {[IO.File]::ReadAllText($ini)} else {''}
    $nand=Join-Path $userDir 'nand'
    if ($config -match '(?m)^nand_directory=(.+)$') {
        $custom=$Matches[1].Trim().Trim('"')
        if ([IO.Path]::IsPathRooted($custom)) {$nand=$custom}
    }
    $registered=Join-Path $nand 'user/Contents/registered'
    if ([IO.Directory]::Exists($registered)) {
        foreach ($nca in Get-ChildItem -LiteralPath $registered -Recurse -Filter '*.nca') {$known[$nca.BaseName]=$true}
    }
    if ([IO.Path]::GetExtension($game) -eq '.nsp') {
        foreach ($id in (Read-NspIds $game)) {$known[$id]=$true}
    }
    foreach ($entry in [regex]::Matches($config,'(?m)^Paths\\external_content_dirs\\\d+\\path=(.*)$')) {
        $folder=$entry.Groups[1].Value.Trim().Trim('"')
        if (![IO.Directory]::Exists($folder)) {continue}
        Read-DlcFolder $folder $known
    }
    while (!(Has-Content $catalog[0] $known)) {
        $file=Pick 'Locate the Smash Ultimate 13.0.5 update NSP' 'Switch update (*.nsp)|*.nsp'
        if (!$file) {return}
        if (!(Add-Package $file @($catalog[0]) $known)) {Notice 'That package did not match the Smash 13.0.5 update. Please choose the correct update NSP.'}
    }
    $fighters=@($catalog | Select-Object -Skip 1)
    while ($true) {
        $missing=@($fighters | Where-Object {!(Has-Content $_ $known)})
        $status = "Core fighter DLC: $($fighters.Count - $missing.Count)/$($fighters.Count) detected."
        Write-Host $status
        if (!$missing.Count) {break}
        $answer=[Windows.Forms.MessageBox]::Show(("$status`nMissing: "+($missing.label -join ', ')+".`n`nYes: choose your Smash DLC folder. No: play now. Cancel: exit."),'Ultimate+','YesNoCancel')
        if ($answer -eq 'Cancel') {return}
        if ($answer -eq 'No') {break}
        $folder=Pick-DlcFolder
        if (!$folder) {continue}
        Read-DlcFolder $folder $known
        Save-ExternalDir $folder
        if (!@($fighters | Where-Object {!(Has-Content $_ $known)}).Count) {
            Notice "Core fighter DLC: $($fighters.Count)/$($fighters.Count) detected. Your DLC folder is ready."
            break
        }
    }
    Start-Process -FilePath $exe -WorkingDirectory $eden -ArgumentList ('"'+$game+'"')
}
if ($MyInvocation.InvocationName -ne '.') {
    try {Play} catch {Write-Host "Could not launch Ultimate+: $($_.Exception.Message)";exit 1}
}
