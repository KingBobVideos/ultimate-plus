param([switch]$SetupOnly)
$ErrorActionPreference="Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$eden=Join-Path $PSScriptRoot "Eden"
$exe=Join-Path $eden "eden.exe"
if(!(Test-Path -LiteralPath $exe)){throw "Extract the entire Ultimate+ download first."}
$UserFolder=Join-Path $eden "user"
$sd=Join-Path $UserFolder "sdmc"
[void][IO.Directory]::CreateDirectory($sd)
$ready=Join-Path $UserFolder "ultimate-plus-installed.txt"
$version=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "parts.sha256")).Hash
if(Get-Process eden -ErrorAction SilentlyContinue | Where-Object Path -eq $exe){throw "Ultimate+ Eden is already open."}
if(!$SetupOnly){
 $savedGame=Join-Path $UserFolder 'smash-game.txt'
 $game=$env:ULTIMATE_PLUS_GAME
 if(!$game -and [IO.File]::Exists($savedGame)){$game=[IO.File]::ReadAllText($savedGame)}
 if(!$game -or ![IO.File]::Exists($game)){
  Add-Type -AssemblyName System.Windows.Forms
  $picker=New-Object System.Windows.Forms.OpenFileDialog
  $picker.Title='Choose your Super Smash Bros. Ultimate base game'
  $picker.Filter='Switch base game (*.xci;*.nsp)|*.xci;*.nsp'
  try{
   if($picker.ShowDialog() -ne 'OK'){return}
   $game=$picker.FileName
  }finally{$picker.Dispose()}
 }
 $game=(Get-Item -LiteralPath $game -ErrorAction Stop).FullName
 if([IO.Path]::GetExtension($game) -notin '.xci','.nsp'){throw 'Select your Smash base game (.xci or .nsp).'}
 [IO.File]::WriteAllText($savedGame,$game)
}
if(!(Test-Path -LiteralPath $ready) -or [IO.File]::ReadAllText($ready) -ne $version){
Write-Host "Preparing Ultimate+ in this folder. Checking downloads..."
$backup=Join-Path $UserFolder ("UltimatePlus Backup "+[guid]::NewGuid())
$parts=foreach($line in Get-Content -LiteralPath "$PSScriptRoot/parts.sha256"){
 if($line -notmatch '^([a-f0-9]{64})  (UltimatePlus-[0-9]+\.zip)$'){throw "Invalid parts list"}
 $hash=$Matches[1];$part=Join-Path $PSScriptRoot $Matches[2]
 if (!(Test-Path -LiteralPath $part) -or (Get-FileHash -LiteralPath $part).Hash -ne $hash) {
  $name=[IO.Path]::GetFileName($part)
  $tag=(Get-Content -LiteralPath "$PSScriptRoot/release-tag.txt" -Raw).Trim()
  $url="https://github.com/KingBobVideos/ultimate-plus/releases/download/$tag/$name"
  Write-Host "Downloading $name. If interrupted, open Play Ultimate+ again."
  & curl.exe --fail --location --retry 3 --output "$part.partial" $url
  if ($LASTEXITCODE -ne 0) {throw "Download interrupted: $name"}
  if ((Get-FileHash -LiteralPath "$part.partial").Hash -ne $hash) {throw "Download verification failed: $name"}
  Move-Item -LiteralPath "$part.partial" -Destination $part -Force
 }
 $part
}
foreach($part in $parts){
 Write-Host ("Installing "+[IO.Path]::GetFileName($part)+"...")
 $zip=[IO.Compression.ZipFile]::OpenRead($part)
 try{foreach($entry in $zip.Entries){
 $file=[IO.Path]::GetFullPath((Join-Path $sd $entry.FullName))
 if(!$file.StartsWith($sd.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Invalid archive path"}
 if([IO.File]::Exists($file)){
 $copy=Join-Path $backup $entry.FullName
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($copy))|Out-Null
 [IO.File]::Copy($file,$copy)
 }
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))|Out-Null
 [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$file,$true)
 }}finally{$zip.Dispose()}
}
Write-Host "Ultimate+ installed. Any replaced files were backed up under $backup."

[IO.File]::WriteAllText($ready,$version)
}
if(!$SetupOnly){Start-Process -FilePath $exe -WorkingDirectory $eden -ArgumentList ('"'+$game+'"')}