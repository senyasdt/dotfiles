param([Parameter(Mandatory=$true)][string]$RenderedHome,[string]$WezTerm)
$ErrorActionPreference='Stop'
$fixture=[IO.Path]::GetFullPath($RenderedHome)
if($fixture.TrimEnd('\') -ieq [Environment]::GetFolderPath('UserProfile').TrimEnd('\') -or !(Test-Path -LiteralPath (Join-Path $fixture '.desktop-recovery-fixture.json'))){throw 'Use an isolated check_desktop_recovery.py fixture, not the real profile.'}
if(!$WezTerm){$WezTerm=(Get-Command wezterm -ErrorAction Stop).Source}
$source=Join-Path $fixture '.config\wezterm'
$manager=Join-Path $fixture '.config\desktop-customization\appearance\Manage-Appearance.ps1'
& $manager -Action RestoreWezTerm -TargetHome $fixture | Out-Null
$evalRoot=Join-Path $fixture 'native-eval';[void][IO.Directory]::CreateDirectory($evalRoot)
$homeLiteral='"'+$fixture.Replace('\','/')+'"'
foreach($file in Get-ChildItem -LiteralPath $source -Filter '*.lua'){
    $content=[IO.File]::ReadAllText($file.FullName).Replace('wezterm.home_dir',$homeLiteral)
    [IO.File]::WriteAllText((Join-Path $evalRoot $file.Name),$content,(New-Object Text.UTF8Encoding($false)))
}
# Bind reads to the fixture, while evaluating through the actual WezTerm Lua API.
# The main file still resolves modules from .config/wezterm, so use test copies there.
foreach($file in Get-ChildItem -LiteralPath $evalRoot -Filter '*.lua'){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $source $file.Name) -Force}
$main=[IO.File]::ReadAllText((Join-Path $fixture '.wezterm.lua')).Replace('wezterm.home_dir',$homeLiteral)
$mainPath=Join-Path $evalRoot 'main.lua';[IO.File]::WriteAllText($mainPath,$main,(New-Object Text.UTF8Encoding($false)))
# The compatibility entry calls the root file; keep that root inside the fixture too.
[IO.File]::WriteAllText((Join-Path $fixture '.wezterm.lua'),$main,(New-Object Text.UTF8Encoding($false)))
$marker=Join-Path $evalRoot 'validated.txt'
$wrapper=@'
local wezterm = require("wezterm")
local config = dofile(MAIN)
assert(config.color_scheme == "nord-cold-grey", "wrong restored theme")
assert(math.abs(config.window_background_opacity - 0.60) < 0.001, "wrong restored opacity")
assert(config.font_size == 10, "wrong Windows font size")
assert(wezterm.GLOBAL.solid_background_mode == true, "wrong restored background mode")
local out = assert(io.open(MARKER, "w")); out:write("ok"); out:close()
return config
'@
$wrapperPath=Join-Path $evalRoot 'validate.lua'
function Check-Native([string]$Entry) {
    $scriptText=$wrapper.Replace('MAIN','"'+$Entry.Replace('\','/')+'"').Replace('MARKER','"'+$marker.Replace('\','/')+'"')
    [IO.File]::WriteAllText($wrapperPath,$scriptText,(New-Object Text.UTF8Encoding($false)))
    if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker}
    $output=& $WezTerm --config-file $wrapperPath ls-fonts --text A 2>&1
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $marker)){throw ('Native WezTerm validation failed: '+($output -join "`n"))}
}
Check-Native $mainPath
Check-Native (Join-Path $source 'wezterm.lua')
foreach($name in 'theme','active_scheme.toml','opacity','background_mode'){Remove-Item -LiteralPath (Join-Path $source $name)}
Check-Native $mainPath
Check-Native (Join-Path $source 'wezterm.lua')
foreach($name in 'theme','active_scheme.toml','opacity','background_mode'){if(Test-Path -LiteralPath (Join-Path $source $name)){throw 'Config fallback unexpectedly wrote mutable state.'}}
Write-Output 'PASS: both native WezTerm entry points load recovered and missing-state profiles as Nord Cold Grey / 0.60 / solid / font10; GUI and real profile untouched.'
