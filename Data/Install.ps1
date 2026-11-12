param([switch]$SetupOnly)
$ErrorActionPreference="Stop"
$eden=Join-Path $PSScriptRoot "Eden"
$exe=Join-Path $eden "eden.exe"
if(!(Test-Path -LiteralPath $exe)){throw "Extract the entire Ultimate+ download first."}
$UserFolder=Join-Path $eden "user"
$sd=Join-Path $UserFolder "sdmc"
[void][IO.Directory]::CreateDirectory($sd)
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
if(!$SetupOnly){Start-Process -FilePath $exe -WorkingDirectory $eden -ArgumentList ('"'+$game+'"')}