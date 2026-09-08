$ErrorActionPreference = 'Stop'

# Change this value to resize the whole pet. 1.0 = original size.
$petScale = 0.75
$script:selfTestMode = ($env:XIAOWANG_DESKTOP_PET_SELFTEST -eq '1')
if ($script:selfTestMode) { [Console]::Out.WriteLine('XIAOWANG_STAGE_START') }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class XiaoWangWindowTools
{
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
'@

$createdNew = $false
if ($script:selfTestMode) {
    $mutexName = 'Local\XiaoWangDesktopPet-selftest'
}
else {
    $mutexName = 'Local\XiaoWangDesktopPet-v1'
}
$mutex = [System.Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)

if (-not $createdNew) {
    [System.Windows.MessageBox]::Show(
        '小汪已經在桌面上了！',
        '小汪桌面寵物',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    ) | Out-Null
    $mutex.Dispose()
    exit
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="小汪"
        Width="300" Height="340"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        Topmost="True"
        ShowInTaskbar="False"
        WindowStartupLocation="Manual">
    <Viewbox Stretch="Uniform" StretchDirection="Both">
        <Grid Width="300" Height="340" Background="Transparent">
            <Canvas>
                <Image x:Name="PetImage"
                       Canvas.Left="20" Canvas.Top="38"
                       Width="260" Height="300"
                       Stretch="Uniform"
                       Cursor="Hand"
                       RenderTransformOrigin="0.5,0.86" />
                <TextBlock x:Name="Reaction"
                           Canvas.Left="132" Canvas.Top="66"
                           Text="♥"
                           FontFamily="Segoe UI Emoji"
                           FontSize="34"
                           FontWeight="Bold"
                           Foreground="#FFFF5D8F"
                           Opacity="0"
                           IsHitTestVisible="False" />
            </Canvas>
            <Border x:Name="SpeechBubble"
                    HorizontalAlignment="Center"
                    VerticalAlignment="Top"
                    Margin="12,4,12,0"
                    Padding="12,7"
                    CornerRadius="15"
                    BorderThickness="2"
                    BorderBrush="#FF0B1A2C"
                    Background="#F7FFFFFF"
                    Visibility="Collapsed"
                    IsHitTestVisible="False">
                <TextBlock x:Name="SpeechText"
                           MaxWidth="245"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontFamily="Microsoft JhengHei UI"
                           FontSize="14"
                           FontWeight="SemiBold"
                           Foreground="#FF0B1A2C" />
            </Border>
            <Border x:Name="TimerBadge"
                    HorizontalAlignment="Center"
                    VerticalAlignment="Bottom"
                    Margin="0,0,0,5"
                    Padding="10,4"
                    CornerRadius="12"
                    Background="#E60B1A2C"
                    Visibility="Collapsed"
                    IsHitTestVisible="False">
                <TextBlock x:Name="TimerText"
                           FontFamily="Microsoft JhengHei UI"
                           FontSize="13"
                           FontWeight="Bold"
                           Foreground="White" />
            </Border>
        </Grid>
    </Viewbox>
</Window>
'@

$xmlReader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
$image = $window.FindName('PetImage')
$speechBubble = $window.FindName('SpeechBubble')
$speechText = $window.FindName('SpeechText')
$reaction = $window.FindName('Reaction')
$timerBadge = $window.FindName('TimerBadge')
$timerText = $window.FindName('TimerText')

$window.Width = [Math]::Round(300 * $petScale)
$window.Height = [Math]::Round(340 * $petScale)

$assetsRoot = Join-Path $PSScriptRoot 'assets'

function Load-PetBitmap {
    param([string]$FileName)

    $path = Join-Path $assetsRoot $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        throw "找不到角色圖片：$path"
    }

    $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [Uri]::new($path, [UriKind]::Absolute)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

$sprites = @{
    Normal = (Load-PetBitmap 'xiaowang.png')
    Wave   = (Load-PetBitmap 'xiaowang-wave.png')
    Sleep  = (Load-PetBitmap 'xiaowang-sleep.png')
    Sit    = (Load-PetBitmap 'xiaowang-sit.png')
}

$image.Source = $sprites.Normal

$scale = [System.Windows.Media.ScaleTransform]::new(1, 1)
$rotate = [System.Windows.Media.RotateTransform]::new(0)
$translate = [System.Windows.Media.TranslateTransform]::new(0, 0)
$transforms = [System.Windows.Media.TransformGroup]::new()
$transforms.Children.Add($scale)
$transforms.Children.Add($rotate)
$transforms.Children.Add($translate)
$image.RenderTransform = $transforms

$random = [System.Random]::new()
$script:autoRoam = $true
$script:isSleeping = $false
$script:isDragging = $false
$script:doNotDisturb = $false
$script:contextDialogue = $true
$script:currentPose = 'Normal'
$script:poseUntil = [DateTime]::MinValue
$script:phase = 0.0
$script:pulse = 0.0
$script:walkFrames = 0
$script:pauseFrames = 65
$script:moveDirection = -1
$script:roamSpeed = 1.15
$script:reactionLife = 0
$script:hwnd = [IntPtr]::Zero
$script:hotkeyRegistered = $false
$script:hotkeySource = $null
$script:hotkeyHook = $null

$script:pomodoroMode = 'Idle'
$script:pomodoroRunning = $false
$script:pomodoroRemaining = 0

$bubbleTimer = [System.Windows.Threading.DispatcherTimer]::new()
$bubbleTimer.Interval = [TimeSpan]::FromSeconds(2.8)
$bubbleTimer.Add_Tick({
    $bubbleTimer.Stop()
    $speechBubble.Visibility = [System.Windows.Visibility]::Collapsed
})

function Show-Speech {
    param([string]$Text)

    $speechText.Text = $Text
    $speechBubble.Visibility = [System.Windows.Visibility]::Visible
    $bubbleTimer.Stop()
    $bubbleTimer.Start()
}

function Show-Balloon {
    param(
        [string]$Title,
        [string]$Text
    )

    if ($null -eq $notifyIcon) {
        return
    }

    $notifyIcon.BalloonTipTitle = $Title
    $notifyIcon.BalloonTipText = $Text
    $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $notifyIcon.ShowBalloonTip(4500)
}

function Set-Pose {
    param([ValidateSet('Normal', 'Wave', 'Sleep', 'Sit')][string]$Name)

    if ($script:currentPose -eq $Name) {
        return
    }

    $script:currentPose = $Name
    $image.Source = $sprites[$Name]
}

function Show-TemporaryPose {
    param(
        [ValidateSet('Normal', 'Wave', 'Sit')][string]$Name,
        [double]$Seconds = 1.2
    )

    if ($script:isSleeping) {
        return
    }

    Set-Pose $Name
    $script:poseUntil = [DateTime]::Now.AddSeconds($Seconds)
}

$reactionTimer = [System.Windows.Threading.DispatcherTimer]::new()
$reactionTimer.Interval = [TimeSpan]::FromMilliseconds(25)
$reactionTimer.Add_Tick({
    $script:reactionLife++
    [System.Windows.Controls.Canvas]::SetTop($reaction, 66 - ($script:reactionLife * 1.15))
    $reaction.Opacity = [Math]::Max(0, 1 - ($script:reactionLife / 32.0))

    if ($script:reactionLife -ge 32) {
        $reactionTimer.Stop()
        $reaction.Opacity = 0
    }
})

function Show-Reaction {
    $messages = @(
        '嗨！我是小汪！',
        '摸摸～',
        '汪！今天也要加油！',
        '要一起散步嗎？',
        '見到你真開心！'
    )

    Show-Speech $messages[$random.Next(0, $messages.Count)]
    Show-TemporaryPose 'Wave' 1.25
    $script:pulse = 1.0
    $script:reactionLife = 0
    [System.Windows.Controls.Canvas]::SetTop($reaction, 66)
    $reaction.Opacity = 1
    $reactionTimer.Stop()
    $reactionTimer.Start()
}

function Update-RoamMenus {
    if ($script:autoRoam) {
        $petRoamMenu.Header = '暫停自動散步'
        $trayRoamMenu.Text = '自動散步'
        $trayRoamMenu.Checked = $true
    }
    else {
        $petRoamMenu.Header = '開始自動散步'
        $trayRoamMenu.Text = '自動散步'
        $trayRoamMenu.Checked = $false
    }
}

function Set-AutoRoam {
    param([bool]$Enabled)

    $script:autoRoam = $Enabled
    Update-RoamMenus

    if ($Enabled) {
        $script:pauseFrames = 15
        Show-Speech '來散步吧！'
    }
    else {
        Show-Speech '我在這裡陪你～'
    }
}

function Set-SleepState {
    param([bool]$Sleeping)

    $script:isSleeping = $Sleeping
    $script:poseUntil = [DateTime]::MinValue

    if ($Sleeping) {
        $petSleepMenu.Header = '叫醒小汪'
        Set-Pose 'Sleep'
        Show-Speech 'Zzz…晚安～'
    }
    else {
        $petSleepMenu.Header = '讓小汪睡覺'
        Set-Pose 'Wave'
        $script:poseUntil = [DateTime]::Now.AddSeconds(1.2)
        $script:pulse = 1.0
        Show-Speech '睡飽了！出發！'
    }
}

function Update-TopmostMenus {
    $trayTopmostMenu.Checked = $window.Topmost
}

function Set-Topmost {
    param([bool]$Enabled)

    $window.Topmost = $Enabled
    Update-TopmostMenus
    if ($Enabled) {
        Show-Speech '我會待在最上面陪你！'
    }
    else {
        Show-Speech '需要我時再叫我～'
    }
}

function Update-DndMenus {
    $petDndMenu.IsChecked = $script:doNotDisturb
    $trayDndMenu.Checked = $script:doNotDisturb
}

function Set-DoNotDisturb {
    param([bool]$Enabled)

    if ($script:hwnd -eq [IntPtr]::Zero) {
        return
    }

    $script:doNotDisturb = $Enabled
    $style = [XiaoWangWindowTools]::GetWindowLong($script:hwnd, -20)

    if ($Enabled) {
        Show-Speech '勿擾模式：滑鼠可以穿過我囉！'
        $style = $style -bor 0x20
        $window.Opacity = 0.72
    }
    else {
        $style = $style -band (-bnot 0x20)
        $window.Opacity = 1.0
        Show-Speech '互動模式恢復！'
    }

    [XiaoWangWindowTools]::SetWindowLong($script:hwnd, -20, $style) | Out-Null
    Update-DndMenus
}

function Update-SizeMenus {
    foreach ($item in $traySizeItems) {
        $item.Checked = ([Math]::Abs(([double]$item.Tag) - $petScale) -lt 0.001)
    }
}

function Set-PetScale {
    param([double]$Value)

    $right = $window.Left + $window.Width
    $bottom = $window.Top + $window.Height
    $script:petScale = $Value
    Set-Variable -Name petScale -Scope Script -Value $Value
    $window.Width = [Math]::Round(300 * $Value)
    $window.Height = [Math]::Round(340 * $Value)

    $area = [System.Windows.SystemParameters]::WorkArea
    $window.Left = [Math]::Max($area.Left, [Math]::Min($right - $window.Width, $area.Right - $window.Width))
    $window.Top = [Math]::Max($area.Top, [Math]::Min($bottom - $window.Height, $area.Bottom - $window.Height))
    Update-SizeMenus
    Show-Speech "目前大小：$([int]($Value * 100))%"
}

function Update-SpeedMenus {
    foreach ($item in $traySpeedItems) {
        $item.Checked = ([Math]::Abs(([double]$item.Tag) - $script:roamSpeed) -lt 0.001)
    }
}

function Set-RoamSpeed {
    param([double]$Value)

    $script:roamSpeed = $Value
    Update-SpeedMenus
    Show-Speech '散步速度調整完成！'
}

function Format-TimeLeft {
    param([int]$Seconds)

    $minutes = [Math]::Floor($Seconds / 60)
    $remainingSeconds = $Seconds % 60
    return ('{0:00}:{1:00}' -f $minutes, $remainingSeconds)
}

function Update-PomodoroDisplay {
    if ($script:pomodoroMode -eq 'Idle') {
        $timerBadge.Visibility = [System.Windows.Visibility]::Collapsed
        $notifyIcon.Text = '小汪桌面寵物'
        $trayPomPause.Enabled = $false
        $trayPomPause.Text = '暫停／繼續'
        $petPomPause.IsEnabled = $false
        $petPomPause.Header = '暫停／繼續'
        return
    }

    $timeText = Format-TimeLeft $script:pomodoroRemaining
    if ($script:pomodoroMode -eq 'Work') {
        $label = '專注'
    }
    else {
        $label = '休息'
    }

    if (-not $script:pomodoroRunning) {
        $timerText.Text = "$label（暫停） $timeText"
        $notifyIcon.Text = "小汪 - $label 暫停 $timeText"
        $trayPomPause.Text = '繼續'
        $petPomPause.Header = '繼續'
    }
    else {
        $timerText.Text = "$label $timeText"
        $notifyIcon.Text = "小汪 - $label $timeText"
        $trayPomPause.Text = '暫停'
        $petPomPause.Header = '暫停'
    }

    $timerBadge.Visibility = [System.Windows.Visibility]::Visible
    $trayPomPause.Enabled = $true
    $petPomPause.IsEnabled = $true
}

function Start-Pomodoro {
    param([ValidateSet('Work', 'Break')][string]$Mode)

    $script:pomodoroMode = $Mode
    $script:pomodoroRunning = $true

    if ($Mode -eq 'Work') {
        $script:pomodoroRemaining = 25 * 60
        Show-Speech '專注 25 分鐘，小汪陪你！'
        Show-TemporaryPose 'Sit' 2.2
    }
    else {
        $script:pomodoroRemaining = 5 * 60
        Show-Speech '休息 5 分鐘，伸展一下吧！'
        Show-TemporaryPose 'Wave' 1.5
    }

    Update-PomodoroDisplay
}

function Toggle-PomodoroPause {
    if ($script:pomodoroMode -eq 'Idle') {
        Show-Speech '先開始一個番茄鐘吧！'
        return
    }

    $script:pomodoroRunning = -not $script:pomodoroRunning
    if ($script:pomodoroRunning) {
        Show-Speech '計時繼續！'
    }
    else {
        Show-Speech '計時暫停。'
    }
    Update-PomodoroDisplay
}

function Reset-Pomodoro {
    $script:pomodoroMode = 'Idle'
    $script:pomodoroRunning = $false
    $script:pomodoroRemaining = 0
    Update-PomodoroDisplay
    Show-Speech '番茄鐘已重設。'
}

function Get-TimeDialogue {
    $hour = (Get-Date).Hour

    if ($hour -ge 5 -and $hour -lt 11) {
        $messages = @('早安！今天也一起加油吧！', '新的一天開始了，先喝口水吧！', '早上的精神最珍貴，汪！')
    }
    elseif ($hour -ge 11 -and $hour -lt 14) {
        $messages = @('午餐時間到了，記得好好吃飯！', '休息一下再繼續吧！', '小汪也在想今天吃什麼～')
    }
    elseif ($hour -ge 14 -and $hour -lt 18) {
        $messages = @('下午辛苦了，伸展一下肩膀吧！', '記得眨眨眼，讓眼睛休息一下。', '再完成一小步就很棒了！')
    }
    elseif ($hour -ge 18 -and $hour -lt 23) {
        $messages = @('晚上好！今天辛苦了。', '忙完也要留一點時間給自己喔。', '今天做得很好，汪！')
    }
    else {
        $messages = @('已經很晚了，要記得休息喔。', '小汪陪你收尾，等等就去睡吧！', '晚睡也要記得喝水。')
    }

    return $messages[$random.Next(0, $messages.Count)]
}

function Show-ContextDialogue {
    if (-not $script:contextDialogue -or $script:doNotDisturb) {
        return
    }

    if ($script:pomodoroRunning -and $script:pomodoroMode -eq 'Work') {
        return
    }

    Show-Speech (Get-TimeDialogue)
    Show-TemporaryPose 'Wave' 1.3
}

function Show-WaterReminder {
    Show-Speech '記得喝水'
    Show-TemporaryPose 'Wave' 1.3

    if (-not $window.IsVisible) {
        Show-Balloon '小汪提醒' '記得喝水'
    }
}

function Move-Home {
    $area = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $area.Right - $window.Width - 26
    $window.Top = $area.Bottom - $window.Height - 14
    Show-Speech '我回來啦！'
}

# Pet right-click menu
$petMenu = [System.Windows.Controls.ContextMenu]::new()

$petRoamMenu = [System.Windows.Controls.MenuItem]::new()
$petRoamMenu.Header = '暫停自動散步'
$petRoamMenu.Add_Click({ Set-AutoRoam (-not $script:autoRoam) })
$petMenu.Items.Add($petRoamMenu) | Out-Null

$petSleepMenu = [System.Windows.Controls.MenuItem]::new()
$petSleepMenu.Header = '讓小汪睡覺'
$petSleepMenu.Add_Click({ Set-SleepState (-not $script:isSleeping) })
$petMenu.Items.Add($petSleepMenu) | Out-Null

$petDndMenu = [System.Windows.Controls.MenuItem]::new()
$petDndMenu.Header = '勿擾／滑鼠穿透（Ctrl+Alt+W）'
$petDndMenu.IsCheckable = $true
$petDndMenu.Add_Click({ Set-DoNotDisturb (-not $script:doNotDisturb) })
$petMenu.Items.Add($petDndMenu) | Out-Null

$petPomMenu = [System.Windows.Controls.MenuItem]::new()
$petPomMenu.Header = '番茄鐘'

$petPomWork = [System.Windows.Controls.MenuItem]::new()
$petPomWork.Header = '開始專注 25 分鐘'
$petPomWork.Add_Click({ Start-Pomodoro 'Work' })
$petPomMenu.Items.Add($petPomWork) | Out-Null

$petPomBreak = [System.Windows.Controls.MenuItem]::new()
$petPomBreak.Header = '開始休息 5 分鐘'
$petPomBreak.Add_Click({ Start-Pomodoro 'Break' })
$petPomMenu.Items.Add($petPomBreak) | Out-Null

$petPomPause = [System.Windows.Controls.MenuItem]::new()
$petPomPause.Header = '暫停／繼續'
$petPomPause.IsEnabled = $false
$petPomPause.Add_Click({ Toggle-PomodoroPause })
$petPomMenu.Items.Add($petPomPause) | Out-Null

$petPomReset = [System.Windows.Controls.MenuItem]::new()
$petPomReset.Header = '重設番茄鐘'
$petPomReset.Add_Click({ Reset-Pomodoro })
$petPomMenu.Items.Add($petPomReset) | Out-Null
$petMenu.Items.Add($petPomMenu) | Out-Null

$petHomeMenu = [System.Windows.Controls.MenuItem]::new()
$petHomeMenu.Header = '回到右下角'
$petHomeMenu.Add_Click({ Move-Home })
$petMenu.Items.Add($petHomeMenu) | Out-Null

$petMenu.Items.Add([System.Windows.Controls.Separator]::new()) | Out-Null

$petExitMenu = [System.Windows.Controls.MenuItem]::new()
$petExitMenu.Header = '關閉小汪'
$petExitMenu.Add_Click({ $window.Close() })
$petMenu.Items.Add($petExitMenu) | Out-Null

$image.ContextMenu = $petMenu

# System tray menu
$notifyIcon = [System.Windows.Forms.NotifyIcon]::new()
$iconPath = Join-Path $assetsRoot 'xiaowang.ico'
if (Test-Path -LiteralPath $iconPath) {
    $notifyIcon.Icon = [System.Drawing.Icon]::new($iconPath)
}
else {
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
}
$notifyIcon.Text = '小汪桌面寵物'
$notifyIcon.Visible = $true

$trayMenu = [System.Windows.Forms.ContextMenuStrip]::new()

$trayShowMenu = [System.Windows.Forms.ToolStripMenuItem]::new('隱藏小汪')
$trayShowMenu.Add_Click({
    if ($window.IsVisible) {
        $window.Hide()
        $trayShowMenu.Text = '顯示小汪'
    }
    else {
        $window.Show()
        $trayShowMenu.Text = '隱藏小汪'
        $window.Activate()
    }
})
$trayMenu.Items.Add($trayShowMenu) | Out-Null

$trayRoamMenu = [System.Windows.Forms.ToolStripMenuItem]::new('自動散步')
$trayRoamMenu.Checked = $true
$trayRoamMenu.Add_Click({ Set-AutoRoam (-not $script:autoRoam) })
$trayMenu.Items.Add($trayRoamMenu) | Out-Null

$traySizeMenu = [System.Windows.Forms.ToolStripMenuItem]::new('大小')
$traySizeItems = @()
$sizeOptions = @(
    @{ Label = '60%'; Value = 0.60 },
    @{ Label = '75%'; Value = 0.75 },
    @{ Label = '90%'; Value = 0.90 },
    @{ Label = '100%'; Value = 1.00 }
)
foreach ($option in $sizeOptions) {
    $item = [System.Windows.Forms.ToolStripMenuItem]::new($option.Label)
    $item.Tag = [double]$option.Value
    $item.Add_Click({ param($sender, $eventArgs) Set-PetScale ([double]$sender.Tag) })
    $traySizeMenu.DropDownItems.Add($item) | Out-Null
    $traySizeItems += $item
}
$trayMenu.Items.Add($traySizeMenu) | Out-Null

$traySpeedMenu = [System.Windows.Forms.ToolStripMenuItem]::new('散步速度')
$traySpeedItems = @()
$speedOptions = @(
    @{ Label = '慢慢走'; Value = 0.65 },
    @{ Label = '一般'; Value = 1.15 },
    @{ Label = '快步走'; Value = 1.85 }
)
foreach ($option in $speedOptions) {
    $item = [System.Windows.Forms.ToolStripMenuItem]::new($option.Label)
    $item.Tag = [double]$option.Value
    $item.Add_Click({ param($sender, $eventArgs) Set-RoamSpeed ([double]$sender.Tag) })
    $traySpeedMenu.DropDownItems.Add($item) | Out-Null
    $traySpeedItems += $item
}
$trayMenu.Items.Add($traySpeedMenu) | Out-Null

$trayTopmostMenu = [System.Windows.Forms.ToolStripMenuItem]::new('保持置頂')
$trayTopmostMenu.Checked = $true
$trayTopmostMenu.Add_Click({ Set-Topmost (-not $window.Topmost) })
$trayMenu.Items.Add($trayTopmostMenu) | Out-Null

$trayDndMenu = [System.Windows.Forms.ToolStripMenuItem]::new('勿擾／滑鼠穿透（Ctrl+Alt+W）')
$trayDndMenu.Add_Click({ Set-DoNotDisturb (-not $script:doNotDisturb) })
$trayMenu.Items.Add($trayDndMenu) | Out-Null

$trayDialogueMenu = [System.Windows.Forms.ToolStripMenuItem]::new('時段情境對話')
$trayDialogueMenu.Checked = $true
$trayDialogueMenu.Add_Click({
    $script:contextDialogue = -not $script:contextDialogue
    $trayDialogueMenu.Checked = $script:contextDialogue
    if ($script:contextDialogue) {
        Show-Speech '時段對話已開啟！'
    }
    else {
        Show-Speech '時段對話已關閉。'
    }
})
$trayMenu.Items.Add($trayDialogueMenu) | Out-Null

$trayMenu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$trayPomMenu = [System.Windows.Forms.ToolStripMenuItem]::new('番茄鐘')
$trayPomWork = [System.Windows.Forms.ToolStripMenuItem]::new('開始專注 25 分鐘')
$trayPomWork.Add_Click({ Start-Pomodoro 'Work' })
$trayPomMenu.DropDownItems.Add($trayPomWork) | Out-Null

$trayPomBreak = [System.Windows.Forms.ToolStripMenuItem]::new('開始休息 5 分鐘')
$trayPomBreak.Add_Click({ Start-Pomodoro 'Break' })
$trayPomMenu.DropDownItems.Add($trayPomBreak) | Out-Null

$trayPomPause = [System.Windows.Forms.ToolStripMenuItem]::new('暫停／繼續')
$trayPomPause.Enabled = $false
$trayPomPause.Add_Click({ Toggle-PomodoroPause })
$trayPomMenu.DropDownItems.Add($trayPomPause) | Out-Null

$trayPomReset = [System.Windows.Forms.ToolStripMenuItem]::new('重設番茄鐘')
$trayPomReset.Add_Click({ Reset-Pomodoro })
$trayPomMenu.DropDownItems.Add($trayPomReset) | Out-Null
$trayMenu.Items.Add($trayPomMenu) | Out-Null

$trayMenu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$trayExitMenu = [System.Windows.Forms.ToolStripMenuItem]::new('關閉小汪')
$trayExitMenu.Add_Click({ $window.Close() })
$trayMenu.Items.Add($trayExitMenu) | Out-Null

$notifyIcon.ContextMenuStrip = $trayMenu
$notifyIcon.Add_DoubleClick({
    if ($window.IsVisible) {
        $window.Hide()
        $trayShowMenu.Text = '顯示小汪'
    }
    else {
        $window.Show()
        $trayShowMenu.Text = '隱藏小汪'
        $window.Activate()
    }
})

Update-RoamMenus
Update-SizeMenus
Update-SpeedMenus
Update-TopmostMenus
Update-DndMenus
Update-PomodoroDisplay
if ($script:selfTestMode) { [Console]::Out.WriteLine('XIAOWANG_STAGE_UI_READY') }

$image.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)

    if ($eventArgs.ClickCount -ge 2) {
        Set-SleepState (-not $script:isSleeping)
        $eventArgs.Handled = $true
        return
    }

    $startLeft = $window.Left
    $startTop = $window.Top
    $script:isDragging = $true

    try {
        $window.DragMove()
    }
    catch {
    }
    finally {
        $script:isDragging = $false
    }

    $distance = [Math]::Abs($window.Left - $startLeft) + [Math]::Abs($window.Top - $startTop)
    if ($distance -lt 5) {
        Show-Reaction
    }

    $eventArgs.Handled = $true
})

$animationTimer = [System.Windows.Threading.DispatcherTimer]::new()
$animationTimer.Interval = [TimeSpan]::FromMilliseconds(40)
$animationTimer.Add_Tick({
    $now = [DateTime]::Now

    if ($script:isSleeping) {
        Set-Pose 'Sleep'
        $script:phase += 0.035
        $translate.Y = [Math]::Sin($script:phase) * 1.2
        $rotate.Angle = [Math]::Sin($script:phase * 0.55) * 0.35
    }
    else {
        $script:phase += 0.11
        $translate.Y = [Math]::Sin($script:phase) * 3.0
        $rotate.Angle = [Math]::Sin($script:phase * 0.55) * 1.45

        if ($now -ge $script:poseUntil) {
            if ($script:pomodoroRunning -and $script:pomodoroMode -eq 'Work') {
                Set-Pose 'Sit'
            }
            else {
                Set-Pose 'Normal'
            }
        }
    }

    $pulseScale = 1.0 + ($script:pulse * 0.08)
    $scale.ScaleX = $pulseScale
    $scale.ScaleY = $pulseScale + ([Math]::Sin($script:phase * 2.0) * 0.01)
    if ($script:pulse -gt 0.005) {
        $script:pulse *= 0.84
    }
    else {
        $script:pulse = 0.0
    }

    $focusActive = $script:pomodoroRunning -and $script:pomodoroMode -eq 'Work'
    if (-not $script:autoRoam -or $script:isSleeping -or $script:isDragging -or $script:doNotDisturb -or $focusActive) {
        return
    }

    if ($script:walkFrames -gt 0) {
        $area = [System.Windows.SystemParameters]::WorkArea
        $newLeft = $window.Left + ($script:moveDirection * $script:roamSpeed)
        $minLeft = $area.Left
        $maxLeft = $area.Right - $window.Width

        if ($newLeft -le $minLeft) {
            $newLeft = $minLeft
            $script:moveDirection = 1
        }
        elseif ($newLeft -ge $maxLeft) {
            $newLeft = $maxLeft
            $script:moveDirection = -1
        }

        $window.Left = $newLeft
        $script:walkFrames--
        if ($script:walkFrames -eq 0) {
            $script:pauseFrames = $random.Next(55, 150)
        }
    }
    elseif ($script:pauseFrames -gt 0) {
        $script:pauseFrames--
    }
    else {
        $script:walkFrames = $random.Next(90, 230)
        if ($random.Next(0, 2) -eq 0) {
            $script:moveDirection = -1
        }
        else {
            $script:moveDirection = 1
        }
    }
})

$pomodoroTimer = [System.Windows.Threading.DispatcherTimer]::new()
$pomodoroTimer.Interval = [TimeSpan]::FromSeconds(1)
$pomodoroTimer.Add_Tick({
    if (-not $script:pomodoroRunning -or $script:pomodoroMode -eq 'Idle') {
        return
    }

    $script:pomodoroRemaining--
    if ($script:pomodoroRemaining -le 0) {
        if ($script:pomodoroMode -eq 'Work') {
            $script:pomodoroMode = 'Break'
            $script:pomodoroRemaining = 5 * 60
            $script:pomodoroRunning = $true
            Show-Speech '專注完成！休息 5 分鐘吧！'
            Show-Balloon '小汪番茄鐘' '專注完成！現在休息 5 分鐘。'
            Show-TemporaryPose 'Wave' 2.0
        }
        else {
            $script:pomodoroMode = 'Idle'
            $script:pomodoroRemaining = 0
            $script:pomodoroRunning = $false
            Show-Speech '休息結束！準備好再開始吧！'
            Show-Balloon '小汪番茄鐘' '五分鐘休息結束了。'
            Show-TemporaryPose 'Wave' 2.0
        }
    }
    Update-PomodoroDisplay
})

$contextTimer = [System.Windows.Threading.DispatcherTimer]::new()
$contextTimer.Interval = [TimeSpan]::FromMinutes(45)
$contextTimer.Add_Tick({ Show-ContextDialogue })

$waterTimer = [System.Windows.Threading.DispatcherTimer]::new()
$waterTimer.Interval = [TimeSpan]::FromMinutes(30)
$waterTimer.Add_Tick({ Show-WaterReminder })

$window.Add_SourceInitialized({
    if ($script:selfTestMode) { [Console]::Out.WriteLine('XIAOWANG_STAGE_SOURCE_INITIALIZED') }
    $helper = [System.Windows.Interop.WindowInteropHelper]::new($window)
    $script:hwnd = $helper.Handle
    $script:hotkeySource = [System.Windows.Interop.HwndSource]::FromHwnd($script:hwnd)
    $script:hotkeyHook = [System.Windows.Interop.HwndSourceHook]{
        param([IntPtr]$handle, [int]$message, [IntPtr]$wParam, [IntPtr]$lParam, [ref]$handled)

        if ($message -eq 0x0312 -and $wParam.ToInt32() -eq 7402) {
            Set-DoNotDisturb (-not $script:doNotDisturb)
            $handled.Value = $true
        }
        return [IntPtr]::Zero
    }
    $script:hotkeySource.AddHook($script:hotkeyHook)
    $script:hotkeyRegistered = [XiaoWangWindowTools]::RegisterHotKey($script:hwnd, 7402, 0x0003, 0x57)
})

$window.Add_Loaded({
    if ($script:selfTestMode) { [Console]::Out.WriteLine('XIAOWANG_STAGE_LOADED') }
    Move-Home
    $animationTimer.Start()
    $pomodoroTimer.Start()
    $contextTimer.Start()
    $waterTimer.Start()
    Show-Speech (Get-TimeDialogue)

    if (-not $script:hotkeyRegistered) {
        Show-Balloon '小汪桌面寵物' 'Ctrl+Alt+W 已被其他程式使用，勿擾模式仍可從系統匣切換。'
    }

    if ($script:selfTestMode) {
        $script:selfTestTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:selfTestTimer.Interval = [TimeSpan]::FromMilliseconds(700)
        $script:selfTestTimer.Add_Tick({
            $script:selfTestTimer.Stop()
            try {
                Start-Pomodoro 'Work'
                if ($script:pomodoroMode -ne 'Work' -or $script:pomodoroRemaining -lt 1499) {
                    throw 'Pomodoro start failed.'
                }
                Toggle-PomodoroPause
                if ($script:pomodoroRunning) {
                    throw 'Pomodoro pause failed.'
                }
                Toggle-PomodoroPause
                Set-PetScale 0.60
                Set-RoamSpeed 0.65
                Set-SleepState $true
                if ($script:currentPose -ne 'Sleep') {
                    throw 'Sleep pose failed.'
                }
                Set-SleepState $false
                Set-DoNotDisturb $true
                if (-not $script:doNotDisturb) {
                    throw 'DND enable failed.'
                }
                Set-DoNotDisturb $false
                Reset-Pomodoro
                Set-Pose 'Normal'
                if ($script:currentPose -ne 'Normal') {
                    throw 'Default original pose failed.'
                }
                Show-WaterReminder
                if ($speechText.Text -ne '記得喝水') {
                    throw 'Water reminder failed.'
                }
                [Console]::Out.WriteLine('XIAOWANG_SELFTEST_OK')
            }
            catch {
                [Console]::Error.WriteLine('XIAOWANG_SELFTEST_FAILED: ' + $_.Exception.Message)
            }
            $window.Close()
        })
        $script:selfTestTimer.Start()
    }
})

$window.Add_Closing({
    $animationTimer.Stop()
    $pomodoroTimer.Stop()
    $contextTimer.Stop()
    $waterTimer.Stop()
    $bubbleTimer.Stop()
    $reactionTimer.Stop()

    if ($script:hotkeyRegistered -and $script:hwnd -ne [IntPtr]::Zero) {
        [XiaoWangWindowTools]::UnregisterHotKey($script:hwnd, 7402) | Out-Null
    }
    if ($null -ne $script:hotkeySource -and $null -ne $script:hotkeyHook) {
        $script:hotkeySource.RemoveHook($script:hotkeyHook)
    }

    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $trayMenu.Dispose()

    try {
        $mutex.ReleaseMutex()
    }
    catch {
    }
    $mutex.Dispose()
})

$app = [System.Windows.Application]::new()
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
if ($script:selfTestMode) { [Console]::Out.WriteLine('XIAOWANG_STAGE_APP_RUN') }
$app.Run($window) | Out-Null
