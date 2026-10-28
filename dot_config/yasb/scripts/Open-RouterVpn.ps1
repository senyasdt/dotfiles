param(
    [string]$Url = '',
    [string]$UrlFile = '',
    [switch]$Clipboard,
    [switch]$Quiet,
    [switch]$Preview
)
$ErrorActionPreference = 'Stop'
# Browser login and explicit Add are required. This launcher never writes UCI,
# stores credentials, or sends clipboard contents to the router over SSH.
if ($UrlFile) {
    $Url = Get-Content -LiteralPath $UrlFile -Raw
} elseif (-not $Url) {
    try { $Url = Get-Clipboard -Raw } catch { $Url = '' }
}
if (-not $Url -or $Url.Length -gt 4096) { $Url = '' }
$target = 'https://192.168.1.132:8443/#tab=domains'
if ($Url) { $target += '&domain=' + [Uri]::EscapeDataString($Url.Trim()) }
# The fragment stays in the browser; app.js removes it from the address and
# normalizes the input. No automatic submission is performed.
if ($Preview) { $target } else { Start-Process -FilePath $target }
