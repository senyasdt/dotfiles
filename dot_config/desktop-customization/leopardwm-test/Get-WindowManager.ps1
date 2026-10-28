# Explicit local selection wins, including an intentional return to komorebi.
$selection=Join-Path $PSScriptRoot 'runtime\selection.json'
if(Test-Path -LiteralPath $selection){
    $choice=[IO.File]::ReadAllText($selection)|ConvertFrom-Json
    if($choice.enabled -isnot [bool]){throw 'Invalid window-manager selection; refusing to start a different manager.'}
    if($choice.enabled){return 'Leopard'}else{return 'Komorebi'}
}
$desktop=Join-Path (Split-Path $PSScriptRoot) 'desktop.json'
$preferred='Komorebi'
if(Test-Path -LiteralPath $desktop){$preferred=([IO.File]::ReadAllText($desktop)|ConvertFrom-Json).windowManager}
if(-not $preferred -or -not (Test-Path -LiteralPath $desktop)){
    $legacy=Join-Path $PSScriptRoot 'settings.json'
    if(Test-Path -LiteralPath $legacy){$preferred=([IO.File]::ReadAllText($legacy)|ConvertFrom-Json).defaultManager}
}
if($preferred -notin @('Leopard','Komorebi')){throw 'Unknown default window manager.'}
# Preserve the classic recovery profile until the portable release is installed.
if($preferred -eq 'Leopard' -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'runtime\release.json'))){return 'Leopard'}
return 'Komorebi'
