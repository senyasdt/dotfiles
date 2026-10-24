param([string]$Router, [string]$IpsetRef, [string]$KeyPath, [string]$LogPath,
      [string]$Url = '', [string]$RenderPreview = '',
      [ValidateSet('add','check')][string]$InitialMode = 'add')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'RouterVpnClient.ps1')
if (-not ('RouterDomainInput' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Windows.Forms;
public sealed class RouterDomainInput : TextBox {
    public event EventHandler Pasted;
    protected override void WndProc(ref Message message) {
        bool paste = message.Msg == 0x302;
        base.WndProc(ref message);
        if (paste && Pasted != null) Pasted(this, EventArgs.Empty);
    }
}
'@
}
[Windows.Forms.Application]::EnableVisualStyles()
$script:pending = $null; $script:jobId = ''; $script:nextPoll = Get-Date
$script:working = $false; $script:closeAt = $null; $script:credential = $null
$script:checking = $false
$form = New-Object Windows.Forms.Form
$form.Text = 'Router VPN'; $form.ClientSize = New-Object Drawing.Size(470, 237)
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
$form.StartPosition = 'Manual'; $form.TopMost = $true; $form.ShowInTaskbar = $false
$form.BackColor = [Drawing.Color]::FromArgb(32,36,50); $form.ForeColor = [Drawing.Color]::FromArgb(222,228,242)
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$title = New-Object Windows.Forms.Label
$title.Text = 'Сайт через VPN'; $title.Font = New-Object Drawing.Font('Segoe UI',12,[Drawing.FontStyle]::Bold)
$title.SetBounds(16,12,438,26)
$domainInput = New-Object RouterDomainInput
$domainInput.MaxLength = 4096
$domainInput.SetBounds(16,48,438,29); $domainInput.BackColor = [Drawing.Color]::FromArgb(26,30,42); $domainInput.ForeColor = $form.ForeColor
$status = New-Object Windows.Forms.Label
$status.SetBounds(16,88,438,59); $status.Text = 'Вставьте ссылку или домен. Перед сохранением проверим DNS и маршруты.'
$progress = New-Object Windows.Forms.ProgressBar
$progress.SetBounds(16,153,438,6); $progress.Style = 'Marquee'; $progress.Visible = $false
$add = New-Object Windows.Forms.Button
$add.Text = 'Добавить'; $add.SetBounds(342,181,112,34)
$close = New-Object Windows.Forms.Button
$close.Text = 'Закрыть'; $close.SetBounds(220,181,112,34)
$check = New-Object Windows.Forms.Button
$check.Text = 'Проверить'; $check.SetBounds(16,181,125,34)
$details = New-Object Windows.Forms.TextBox
$details.SetBounds(16,167,438,170); $details.Multiline = $true; $details.ReadOnly = $true
$details.ScrollBars = 'Vertical'; $details.Visible = $false
$details.BackColor = [Drawing.Color]::FromArgb(26,30,42); $details.ForeColor = $form.ForeColor
foreach ($button in @($add,$close,$check)) { $button.FlatStyle='Flat'; $button.BackColor=[Drawing.Color]::FromArgb(53,63,84) }
$close.Add_Click({ $form.Close() }); $form.CancelButton = $close; $form.AcceptButton = $add
$form.Controls.AddRange(@($title,$domainInput,$status,$progress,$details,$add,$close,$check))
if ($InitialMode -eq 'check') { $form.AcceptButton = $check }
function Reset-Details {
    $details.Visible = $false; $details.Text = ''
    $form.ClientSize = New-Object Drawing.Size(470,237)
    foreach ($button in @($add,$close,$check)) { $button.Top = 181 }
}
function Clean-Input {
    if (-not $domainInput.Text) { return }
    try { $domainInput.Text = [RouterVpnNative]::Normalize($domainInput.Text) } catch { }
}
$domainInput.Add_Leave({ Clean-Input })
$domainInput.add_Pasted({ Clean-Input })
$domainInput.Add_TextChanged({ if (-not $script:working) { Reset-Details } })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 200
function Finish-Request([string]$message, [bool]$ok, [bool]$keepOpen = $false) {
    $script:pending = $null; $script:working = $false
    $add.Enabled = $true; $check.Enabled = $true; $domainInput.Enabled = $true; $progress.Visible = $false
    $status.Text = $message
    $status.ForeColor = if($ok){[Drawing.Color]::FromArgb(166,227,161)}else{[Drawing.Color]::FromArgb(243,139,168)}
    if ($ok -and -not $keepOpen) { $script:closeAt = (Get-Date).AddSeconds(2) }
}
$add.Add_Click({
    if ($script:working) { return }
    try {
        $domain = [RouterVpnNative]::Normalize($domainInput.Text); $domainInput.Text = $domain
        $script:credential = Read-RouterVpnCredential
        $script:checking = $false; Reset-Details
        $script:closeAt = $null; $script:jobId = ''; $script:deadline = (Get-Date).AddSeconds(220)
        $script:pending = Start-RouterVpnRequest $script:credential 'POST' '/api/client/domains' (@{domain=$domain} | ConvertTo-Json -Compress)
        $script:working = $true; $add.Enabled = $false; $check.Enabled = $false; $domainInput.Enabled = $false; $progress.Visible = $true
        $status.ForeColor = $form.ForeColor; $status.Text = 'Сохраняем бэкап и запускаем проверку…'
    } catch { Finish-Request $_.Exception.GetBaseException().Message $false }
})
$check.Add_Click({
    if ($script:working) { return }
    try {
        $domain = [RouterVpnNative]::Normalize($domainInput.Text); $domainInput.Text = $domain
        $script:credential = Read-RouterVpnCredential; Reset-Details
        $script:checking = $true; $script:closeAt = $null; $script:jobId = ''; $script:deadline = (Get-Date).AddSeconds(50)
        $script:pending = Start-RouterVpnRequest $script:credential 'POST' '/api/client/domain-check' (@{domain=$domain} | ConvertTo-Json -Compress)
        $script:working = $true; $add.Enabled = $false; $check.Enabled = $false; $domainInput.Enabled = $false; $progress.Visible = $true
        $status.ForeColor = $form.ForeColor; $status.Text = 'Проверяем DNS и маршруты. Правила не изменяются.'
    } catch { Finish-Request $_.Exception.GetBaseException().Message $false }
})
$timer.Add_Tick({
    if ($script:closeAt -and (Get-Date) -ge $script:closeAt) { $form.Close(); return }
    if (-not $script:working) { return }
    try {
        if ((Get-Date) -gt $script:deadline) {
            if ($script:checking) { throw 'Не удалось дождаться диагностики. Правила не изменялись; попробуйте ещё раз.' }
            throw 'Проверка продолжается на Pi. Посмотрите результат в панели; автооткат работает на роутере.'
        }
        if ($script:pending) {
            if (-not $script:pending.IsCompleted) { return }
            $reply = Read-RouterVpnReply $script:pending; $script:pending = $null
            if ($script:checking) {
                $details.Text = $reply.report.Replace("`n","`r`n"); $details.Visible = $true
                $form.ClientSize = New-Object Drawing.Size(470,410)
                $screenArea = [Windows.Forms.Screen]::FromControl($form).WorkingArea
                $form.Top = [Math]::Max($screenArea.Top,[Math]::Min($form.Top,$screenArea.Bottom-$form.Height))
                foreach ($button in @($add,$close,$check)) { $button.Top = 354 }
                Finish-Request $reply.summary $true $true
                if ($reply.warnings.Count) { $status.ForeColor = [Drawing.Color]::FromArgb(240,205,120) }
                return
            }
            if (-not $script:jobId) {
                if ($reply.already) { Finish-Request $reply.stage $true; return }
                $script:jobId = $reply.job; $status.Text = 'Сохраняем настройки. Защита отката включена.'
            } else {
                $status.Text = $reply.stage
                if ($reply.state -ne 'running') {
                    Finish-Request ($reply.stage+' '+$reply.recovery).Trim() ($reply.state -eq 'success'); return
                }
            }
            $script:nextPoll = (Get-Date).AddSeconds(2)
        } elseif ((Get-Date) -ge $script:nextPoll) {
            $script:pending = Start-RouterVpnRequest $script:credential 'GET' ('/api/client/jobs/'+$script:jobId) $null
        }
    } catch { Finish-Request $_.Exception.GetBaseException().Message $false }
})
if (-not $Url -and -not $RenderPreview) { try { $Url = Get-Clipboard -Raw } catch { } }
$domainInput.Text = $Url; Clean-Input
$cursor = [Windows.Forms.Cursor]::Position; $area = [Windows.Forms.Screen]::FromPoint($cursor).WorkingArea
$form.Location = New-Object Drawing.Point([Math]::Max($area.Left,[Math]::Min($cursor.X-420,$area.Right-$form.Width)),[Math]::Max($area.Top,[Math]::Min($cursor.Y+8,$area.Bottom-$form.Height)))
if ($RenderPreview) {
    $form.TopMost = $false; $form.Location = New-Object Drawing.Point(-32000,-32000)
    $form.Show(); [Windows.Forms.Application]::DoEvents(); $form.PerformLayout()
    $bitmap = New-Object Drawing.Bitmap($form.Width,$form.Height)
    $form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
    $bitmap.Save($RenderPreview,[Drawing.Imaging.ImageFormat]::Png); $bitmap.Dispose()
} else { $form.Add_Shown({ $form.Activate(); $domainInput.Focus(); $domainInput.SelectAll(); if ($InitialMode -eq 'check' -and $domainInput.Text) { $check.PerformClick() } }); $timer.Start(); [void]$form.ShowDialog() }
$timer.Stop(); $timer.Dispose(); $form.Dispose()
