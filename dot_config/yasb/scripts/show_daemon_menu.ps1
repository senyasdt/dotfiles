Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Drawing.Drawing2D

$startScript = Join-Path $env:USERPROFILE ".config\start-daemons.cmd"
$stopScript = Join-Path $env:USERPROFILE ".config\stop-daemons.cmd"
$restartScript = Join-Path $env:USERPROFILE ".config\restart-daemons.cmd"
$startAhkScript = Join-Path $env:USERPROFILE ".config\start-autohotkey.cmd"
$stopAhkScript = Join-Path $env:USERPROFILE ".config\stop-autohotkey.cmd"
$openVialScript = Join-Path $env:USERPROFILE ".config\vial\scripts\open_vial_safely.cmd"
$hiddenRunner = Join-Path $env:USERPROFILE ".config\run-hidden.vbs"
$wscriptExe = Join-Path $env:WINDIR "System32\wscript.exe"

$bgColor = [System.Drawing.Color]::FromArgb(32, 36, 50)
$borderColor = [System.Drawing.Color]::FromArgb(76, 88, 114)
$textColor = [System.Drawing.Color]::FromArgb(222, 228, 242)
$mutedColor = [System.Drawing.Color]::FromArgb(170, 181, 207)
$hoverColor = [System.Drawing.Color]::FromArgb(48, 54, 72)
$buttonColor = [System.Drawing.Color]::FromArgb(36, 41, 56)
$activeBorderColor = [System.Drawing.Color]::FromArgb(86, 102, 132)
$radius = 14

function Set-RoundedRegion {
    param(
        [System.Windows.Forms.Form]$TargetForm,
        [int]$CornerRadius
    )

    $rect = New-Object System.Drawing.Rectangle 0, 0, $TargetForm.Width, $TargetForm.Height
    $diameter = $CornerRadius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.StartFigure()
    $path.AddArc($rect.X, $rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($rect.Right - $diameter, $rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($rect.Right - $diameter, $rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    $TargetForm.Region = New-Object System.Drawing.Region($path)
}

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.BackColor = $bgColor
$form.KeyPreview = $true
$form.ClientSize = New-Object System.Drawing.Size(220, 182)
$form.Opacity = 0.94

$borderPanel = New-Object System.Windows.Forms.Panel
$borderPanel.BackColor = $borderColor
$borderPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$borderPanel.Padding = New-Object System.Windows.Forms.Padding(1)
$form.Controls.Add($borderPanel)

$content = New-Object System.Windows.Forms.Panel
$content.Dock = [System.Windows.Forms.DockStyle]::Fill
$content.BackColor = $bgColor
$borderPanel.Controls.Add($content)

function New-MenuButton {
    param(
        [string]$Text,
        [scriptblock]$OnClick,
        [int]$Top
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = 202
    $button.Height = 32
    $button.Location = New-Object System.Drawing.Point(8, $Top)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = $buttonColor
    $button.ForeColor = $textColor
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Add_MouseEnter({
        $this.BackColor = $hoverColor
        $this.FlatAppearance.BorderSize = 1
        $this.FlatAppearance.BorderColor = $activeBorderColor
    })
    $button.Add_MouseLeave({
        $this.BackColor = $buttonColor
        $this.FlatAppearance.BorderSize = 0
    })
    $button.FlatAppearance.MouseDownBackColor = $hoverColor
    $button.FlatAppearance.MouseOverBackColor = $hoverColor
    $label = $Text
    $clickAction = $OnClick
    $button.Add_Click({
        try {
            & $clickAction
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to run '$label': $($_.Exception.Message)",
                "YASB Daemon Menu",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        } finally {
            $form.Close()
        }
    }.GetNewClosure())
    return $button
}

function Start-HiddenScript {
    param([string]$ScriptPath)

    Start-Process -FilePath $wscriptExe `
        -ArgumentList @(
            "`"$hiddenRunner`"",
            "`"$ScriptPath`""
        ) `
        -WorkingDirectory $env:USERPROFILE `
        -WindowStyle Hidden
}

function Test-AhkRunning {
    return [bool](Get-Process AutoHotkey64, AutoHotkey32, AutoHotkey -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Test-DaemonsRunning {
    return [bool](Get-Process komorebi -ErrorAction SilentlyContinue | Select-Object -First 1)
}

$daemonToggleLabel = if (Test-DaemonsRunning) { "Stop daemons" } else { "Start daemons" }
$daemonToggleScript = if (Test-DaemonsRunning) { $stopScript } else { $startScript }
$daemonToggleButton = New-MenuButton $daemonToggleLabel {
    Start-HiddenScript -ScriptPath $daemonToggleScript
} 8

$restartButton = New-MenuButton "Restart daemons" {
    Start-HiddenScript -ScriptPath $restartScript
} 46

$ahkToggleLabel = if (Test-AhkRunning) { "Stop AHK" } else { "Start AHK" }
$ahkToggleScript = if (Test-AhkRunning) { $stopAhkScript } else { $startAhkScript }
$ahkToggleButton = New-MenuButton $ahkToggleLabel {
    Start-HiddenScript -ScriptPath $ahkToggleScript
} 84

$openVialButton = New-MenuButton "Open Vial safely" {
    Start-HiddenScript -ScriptPath $openVialScript
} 122

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Text = "YASB stays running"
$hintLabel.ForeColor = $mutedColor
$hintLabel.BackColor = $bgColor
$hintLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$hintLabel.AutoSize = $true
$hintLabel.Location = New-Object System.Drawing.Point(12, 155)

[void]$content.Controls.AddRange(@($daemonToggleButton, $restartButton, $ahkToggleButton, $openVialButton, $hintLabel))

$cursor = [System.Windows.Forms.Cursor]::Position
$form.Add_SizeChanged({ Set-RoundedRegion -TargetForm $form -CornerRadius $radius })
$form.Add_Shown({
    Set-RoundedRegion -TargetForm $form -CornerRadius $radius
    $x = $cursor.X - 40
    $y = $cursor.Y + 8

    $workingArea = [System.Windows.Forms.Screen]::FromPoint($cursor).WorkingArea
    if ($x + $form.Width -gt $workingArea.Right) {
        $x = $workingArea.Right - $form.Width - 8
    }
    if ($x -lt $workingArea.Left) {
        $x = $workingArea.Left + 8
    }
    if ($y + $form.Height -gt $workingArea.Bottom) {
        $y = $cursor.Y - $form.Height - 8
    }
    if ($y -lt $workingArea.Top) {
        $y = $workingArea.Top + 8
    }

    $form.Location = New-Object System.Drawing.Point([int]$x, [int]$y)
    $form.Activate()
})

$form.Add_Deactivate({ $form.Close() })
$form.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $form.Close()
    }
})

[void]$form.ShowDialog()
$form.Dispose()
