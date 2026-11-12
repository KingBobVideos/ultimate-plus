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
if(!(Test-Path -LiteralPath $ready) -or [IO.File]::ReadAllText($ready) -ne $version){
Write-Host "Preparing Ultimate+ in this folder. Checking downloads..."
$backup=Join-Path $UserFolder ("UltimatePlus Backup "+[guid]::NewGuid())
$parts=foreach($line in Get-Content -LiteralPath "$PSScriptRoot/parts.sha256"){
 if($line -notmatch '^([a-f0-9]{64})  (UltimatePlus-[0-9]+\.zip)$'){throw "Invalid parts list"}
 $hash=$Matches[1];$part=Join-Path $PSScriptRoot $Matches[2]
 if((Get-FileHash -LiteralPath $part).Hash -ne $hash){throw "Missing or damaged download: $part"}
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
if(!$SetupOnly){Start-Process -FilePath $exe -WorkingDirectory $eden}