# Explicit local selection wins, including an intentional return to komorebi.
$selection=Join-Path $PSScriptRoot 'runtime\selection.json'
if(Test-Path -LiteralPath $selection){
    $choice=[IO.File]::ReadAllText($selection)|ConvertFrom-Json
    if($choice.enabled -isnot [bool]){throw 'Invalid window-manager selection; refusing to start a different manager.'}
    if($choice.enabled){return 'Leopard'}else{return 'Komorebi'}
}
$settings=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'settings.json'))|ConvertFrom-Json
if($settings.defaultManager -notin @('Leopard','Komorebi')){throw 'Unknown default window manager.'}
# Preserve the classic recovery profile until the portable release is installed.
if($settings.defaultManager -eq 'Leopard' -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'runtime\release.json'))){return 'Leopard'}
return 'Komorebi'
