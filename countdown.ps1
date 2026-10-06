#requires -Version 5.1
<#
Shared Windows countdown for shutdown-timer.ps1 and lock-timer.ps1.
The launcher opens a duration picker and starts one hidden STA worker of this file.
Only the worker owns the countdown window and the eventual action.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Shutdown', 'Lock')]
    [string]$Action,
    [ValidateRange(1, 2147483647)]
    [int]$Minutes = 60,
    [switch]$DryRun,
    [switch]$Worker
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$actionText = if ($Action -eq 'Shutdown') { '关机' } else { '锁屏' }
$caption = '定时' + $actionText

function New-CountdownBrush {
    param([string]$Color)
    $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $brush.Freeze()
    return $brush
}

function Update-DurationPreview {
    $state = $script:setupState
    if ($null -eq $state -or $state.Submitted) { return }
    $text = $state.Input.Text.Trim()
    [int]$value = 0
    $valid = $text -match '^[0-9]+$' -and
        [int]::TryParse($text, [ref]$value) -and $value -gt 0
    $state.Start.IsEnabled = $valid
    if ($valid) {
        $state.Error.Text = ''
        $state.InputBorder.BorderBrush = $state.BorderBrush
        $due = [DateTime]::Now.AddMinutes($value)
        $day = if ($due.Date -eq [DateTime]::Today) { '今天' } else { $due.ToString('M月d日') }
        $state.Estimate.Text = $day + ' ' + $due.ToString('HH:mm')
    }
    else {
        $state.Error.Text = '请输入大于 0 的整数分钟数。'
        $state.InputBorder.BorderBrush = $state.WarningBrush
        $state.Estimate.Text = '填写时长后显示预计时间'
    }
    foreach ($button in $state.Presets) {
        $selected = $valid -and [int]$button.Tag -eq $value
        $button.Background = if ($selected) { $state.AccentSoft } else { $state.NeutralSoft }
        $button.Foreground = if ($selected) { $state.AccentBrush } else { $state.TextBrush }
        $button.BorderBrush = if ($selected) { $state.AccentBrush } else { $state.BorderBrush }
    }
}

function Show-DurationPicker {
    param([string]$Mode, [bool]$TestMode)
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw '窗口需要 STA 模式，请使用 BAT 启动器或按说明启动脚本。'
    }
    $label = if ($Mode -eq 'Shutdown') { '关机' } else { '锁屏' }
    $accent = if ($Mode -eq 'Shutdown') { '#D97845' } else { '#4F6BF0' }
    $soft = if ($Mode -eq 'Shutdown') { '#FFF3EB' } else { '#EEF2FF' }
    [xml]$setupXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="440" MinHeight="520" SizeToContent="Height" WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" FontFamily="Microsoft YaHei UI"
        UseLayoutRounding="True" SnapsToDevicePixels="True" Title="屏幕时间">
    <Window.Resources>
        <Style x:Key="SoftButton" TargetType="Button">
            <Setter Property="Height" Value="42"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="#172033"/>
            <Setter Property="Background" Value="#F6F8FC"/>
            <Setter Property="BorderBrush" Value="#E5EAF3"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder" CornerRadius="9"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.84"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBorder" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Margin="12" CornerRadius="18" Background="White" BorderBrush="#E5EAF3" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect Color="#1D2A45" BlurRadius="20" ShadowDepth="3" Opacity="0.13"/>
        </Border.Effect>
        <Grid Margin="28,20,28,24">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Grid Name="TitleBar" Background="Transparent" Margin="0,0,0,22">
                <TextBlock Name="AppLabel" Text="屏幕时间" FontSize="12" Foreground="#6B7280" VerticalAlignment="Center"/>
                <Button Name="CloseButton" Content="&#x00D7;" Width="28" Height="28"
                        HorizontalAlignment="Right" FontSize="19"
                        Style="{StaticResource SoftButton}" AutomationProperties.Name="关闭设置"/>
            </Grid>
            <StackPanel Grid.Row="1" Margin="0,0,0,24">
                <TextBlock Name="HeadingText" FontSize="25" FontWeight="SemiBold" Foreground="#172033"/>
                <TextBlock Name="SubtitleText" FontSize="12" Foreground="#6B7280" Margin="0,8,0,0"/>
            </StackPanel>
            <UniformGrid Grid.Row="2" Columns="4" Margin="-3,0,-3,18">
                <Button Name="Preset15" Tag="15" Content="15 分钟" Margin="3,0" Style="{StaticResource SoftButton}"/>
                <Button Name="Preset30" Tag="30" Content="30 分钟" Margin="3,0" Style="{StaticResource SoftButton}"/>
                <Button Name="Preset60" Tag="60" Content="60 分钟" Margin="3,0" Style="{StaticResource SoftButton}"/>
                <Button Name="Preset90" Tag="90" Content="90 分钟" Margin="3,0" Style="{StaticResource SoftButton}"/>
            </UniformGrid>
            <StackPanel Grid.Row="3">
                <TextBlock Text="自定义时长" FontSize="12" Foreground="#6B7280" Margin="0,0,0,8"/>
                <Border Name="MinutesBorder" CornerRadius="10" Background="#F8FAFD"
                        BorderBrush="#E5EAF3" BorderThickness="1" Height="58">
                    <Grid Margin="16,0">
                        <TextBox Name="MinutesInput" Text="60" MaxLength="10" FontSize="25"
                                 FontFamily="Segoe UI" Foreground="#172033" Background="Transparent"
                                 BorderThickness="0" Margin="0,0,42,0" VerticalContentAlignment="Center"
                                 AcceptsReturn="False" AutomationProperties.Name="分钟数"/>
                        <TextBlock Text="分钟" FontSize="12" Foreground="#6B7280"
                                   HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>
                </Border>
                <TextBlock Name="ValidationText" Height="25" Padding="0,5,0,0" FontSize="11" Foreground="#DC5656"/>
            </StackPanel>
            <Border Name="EstimatePanel" Grid.Row="4" CornerRadius="10" Padding="14,11" Background="#EEF2FF">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Name="EstimateLabel" FontSize="12" Foreground="#6B7280" VerticalAlignment="Center"/>
                    <TextBlock Name="EstimateText" Grid.Column="1" FontSize="15" FontWeight="SemiBold"
                               Foreground="#4F6BF0" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
            </Border>
            <TextBlock Name="HintText" Grid.Row="5" Margin="0,14,0,0" FontSize="11" Foreground="#6B7280" TextWrapping="Wrap"/>
            <Grid Grid.Row="7" Margin="0,18,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="96"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Button Name="CancelButton" Content="取消" IsCancel="True" Style="{StaticResource SoftButton}"/>
                <Button Name="StartButton" Grid.Column="2" Content="开始计时" IsDefault="True"
                        FontWeight="SemiBold" Style="{StaticResource SoftButton}" Background="#4F6BF0" Foreground="White"/>
            </Grid>
        </Grid>
    </Border>
</Window>
'@
    $reader = [System.Xml.XmlNodeReader]::new($setupXaml)
    try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }
    # Initialize every field before attaching callbacks to the modal dialog.
    $script:setupState = [pscustomobject]@{
        Window = $window
        Input = $window.FindName('MinutesInput')
        InputBorder = $window.FindName('MinutesBorder')
        Error = $window.FindName('ValidationText')
        Estimate = $window.FindName('EstimateText')
        Start = $window.FindName('StartButton')
        Presets = @($window.FindName('Preset15'), $window.FindName('Preset30'),
            $window.FindName('Preset60'), $window.FindName('Preset90'))
        PreviewTimer = [System.Windows.Threading.DispatcherTimer]::new()
        AccentBrush = (New-CountdownBrush $accent)
        AccentSoft = (New-CountdownBrush $soft)
        NeutralSoft = (New-CountdownBrush '#F6F8FC')
        BorderBrush = (New-CountdownBrush '#E5EAF3')
        TextBrush = (New-CountdownBrush '#172033')
        WarningBrush = (New-CountdownBrush '#DC5656')
        ResultMinutes = $null
        Submitted = $false
    }
    $state = $script:setupState
    $result = $null
    try {
        $window.Title = '定时' + $label + ' · 屏幕时间'
        $window.FindName('HeadingText').Text = '多久后' + $label + '？'
        $window.FindName('SubtitleText').Text = if ($Mode -eq 'Shutdown') {
            '选择时长，到时自动关闭电脑。'
        } else { '选择时长，到时自动锁定电脑。' }
        $window.FindName('HintText').Text = if ($Mode -eq 'Shutdown') {
            '到时将强制关闭应用，请提前保存工作。'
        } else { '解锁时使用 Windows 登录方式。' }
        $window.FindName('EstimateLabel').Text = '预计' + $label
        $window.FindName('EstimatePanel').Background = $state.AccentSoft
        $state.Estimate.Foreground = $state.AccentBrush
        $state.Start.Background = $state.AccentBrush
        $state.Start.BorderBrush = $state.AccentBrush
        if ($TestMode) {
            $window.FindName('AppLabel').Text += ' · 测试模式'
            $window.FindName('HeadingText').Text = '测试' + $label + '倒计时'
            $window.FindName('SubtitleText').Text = '完整体验倒计时，不会执行' + $label + '。'
            $window.FindName('HintText').Text = '测试结束后，计时窗口会自动关闭。'
            $window.FindName('EstimateLabel').Text = '预计结束'
        }
        $window.FindName('CloseButton').Add_Click({
            if ($null -ne $script:setupState) {
                $script:setupState.Window.DialogResult = $false
            }
        })
        $state.Input.Add_TextChanged({ Update-DurationPreview })
        foreach ($button in $state.Presets) {
            $button.Add_Click({
                param($sender, $eventArgs)
                $script:setupState.Input.Text = [string]$sender.Tag
            })
        }
        $state.Start.Add_Click({
            $current = $script:setupState
            if ($current.Submitted) { return }
            Update-DurationPreview
            if (-not $current.Start.IsEnabled) { return }
            $current.ResultMinutes = [int]$current.Input.Text.Trim()
            $current.Submitted = $true
            $current.Window.DialogResult = $true
        })
        $window.FindName('TitleBar').Add_MouseLeftButtonDown({
            if ($null -ne $script:setupState) {
                try { $script:setupState.Window.DragMove() }
                catch [System.InvalidOperationException] { }
            }
        })
        $window.Add_ContentRendered({
            $null = $script:setupState.Input.Focus()
            $script:setupState.Input.SelectAll()
        })
        $state.PreviewTimer.Interval = [TimeSpan]::FromSeconds(1)
        $state.PreviewTimer.Add_Tick({ Update-DurationPreview })
        Update-DurationPreview
        $state.PreviewTimer.Start()
        $accepted = $window.ShowDialog()
        if ($accepted -eq $true) { $result = $state.ResultMinutes }
    }
    finally {
        $state.PreviewTimer.Stop()
        $script:setupState = $null
    }
    return $result
}

if (-not $Worker) {
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            throw '本工具需要 Windows 10/11 和 Windows PowerShell 5.1。'
        }
        if (-not $PSBoundParameters.ContainsKey('Minutes')) {
            $pickedMinutes = Show-DurationPicker -Mode $Action -TestMode ([bool]$DryRun)
            if ($null -eq $pickedMinutes) { exit 0 }
            $Minutes = [int]$pickedMinutes
        }
        $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = '-NoLogo -NoProfile -STA -WindowStyle Hidden -File "{0}" -Action {1} -Minutes {2} -Worker' -f $PSCommandPath, $Action, $Minutes
        if ($DryRun) { $arguments += ' -DryRun' }
        $null = Start-Process -FilePath $powerShellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Write-Host '计时窗口正在打开。'
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
    exit 0
}

$mutex = $null
$ownsMutex = $false
$script:timerState = $null
$workerExitCode = 0

function Set-CountdownDisplay {
    param([long]$RemainingSeconds)
    $state = $script:timerState
    [long]$displayMinutes = [math]::Floor($RemainingSeconds / 60.0)
    [long]$displaySeconds = $RemainingSeconds % 60
    $state.Text.Text = '{0:D2}:{1:D2}' -f $displayMinutes, $displaySeconds
    $warning = $RemainingSeconds -le 300
    $state.Text.Foreground = if ($warning) { $state.WarningBrush } else { $state.TextBrush }
    $state.Progress.Foreground = if ($warning) { $state.WarningBrush } else { $state.AccentBrush }
    $state.Status.Foreground = if ($warning) { $state.WarningBrush } else { $state.MutedBrush }
    $state.Progress.Value = [math]::Max(0.0, [math]::Min(100.0,
        100.0 * $RemainingSeconds / $state.DurationSeconds))
    $state.Status.Text = if ($RemainingSeconds -eq 0) {
        if ($state.DryRun) { '测试完成' } else { '准备' + $state.ActionText }
    }
    elseif ($warning) {
        if ($state.DryRun) { '即将结束' } else { '即将' + $state.ActionText }
    }
    else {
        if ($state.DryRun) { '测试中' } else { '计时中' }
    }
}

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw '窗口需要 STA 模式，请使用 BAT 启动器或按说明启动脚本。'
    }

    # Reuse the previous shutdown timer's mutex for running-copy compatibility.
    # Shutdown, lock and DryRun all share one timer per Windows session.
    $mutex = [System.Threading.Mutex]::new($false, 'Local\Wind8ai.WindowsShutdownTimer.v1')
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) {
        $null = [System.Windows.MessageBox]::Show(
            '已有计时在运行，请先结束当前计时，再开始新任务。', '屏幕时间',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        exit 1
    }

    # Compile before starting the clock. DryRun never loads the native wrapper.
    if ($Action -eq 'Lock' -and -not $DryRun) {
        if (-not ('ScreenTimeTools.Workstation' -as [type])) {
            Add-Type -TypeDefinition @'
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ScreenTimeTools
{
    public static class Workstation
    {
        [DllImport("user32.dll", SetLastError = true, ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool LockWorkStation();

        public static void Lock()
        {
            if (!LockWorkStation())
            {
                int error = Marshal.GetLastWin32Error();
                throw new Win32Exception(error, "Could not initiate workstation lock.");
            }
        }
    }
}
'@
        }
    }

    # Assign position numerically rather than inserting locale-sensitive XAML.
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize"
        SizeToContent="Width" MinWidth="248" Height="120" Top="10"
        FontFamily="Microsoft YaHei UI" UseLayoutRounding="True" SnapsToDevicePixels="True"
        Title="屏幕时间">
    <Border Margin="9" CornerRadius="14" Background="#FAFFFFFF"
            BorderBrush="#E5EAF3" BorderThickness="1" Padding="16,12">
        <Border.Effect>
            <DropShadowEffect Color="#1D2A45" BlurRadius="16" ShadowDepth="2" Opacity="0.14"/>
        </Border.Effect>
        <StackPanel>
            <Grid>
                <Border Name="ActionBadge" HorizontalAlignment="Left" CornerRadius="5" Padding="7,3" Background="#EEF2FF">
                    <TextBlock Name="ActionText" FontSize="11" FontWeight="SemiBold" Foreground="#4F6BF0"/>
                </Border>
                <TextBlock Name="StatusText" Text="计时中" HorizontalAlignment="Right" VerticalAlignment="Center"
                           Margin="90,0,0,0" FontSize="11" Foreground="#6B7280"/>
            </Grid>
            <Grid Margin="0,4,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Name="CountdownText" FontFamily="Consolas" FontSize="30"
                           FontWeight="Bold" Foreground="#172033"/>
                <TextBlock Name="DueText" Grid.Column="1" Margin="18,0,0,6" FontSize="10"
                           Foreground="#6B7280" VerticalAlignment="Bottom"/>
            </Grid>
            <ProgressBar Name="RemainingProgress" Height="3" Minimum="0" Maximum="100" Value="100"
                         Background="#EDF1F7" Foreground="#4F6BF0" Margin="0,6,0,0">
                <ProgressBar.Template>
                    <ControlTemplate TargetType="ProgressBar">
                        <Border CornerRadius="2" Background="{TemplateBinding Background}">
                            <Grid x:Name="PART_Track">
                                <Border x:Name="PART_Indicator" CornerRadius="2"
                                        Background="{TemplateBinding Foreground}" HorizontalAlignment="Left"/>
                            </Grid>
                        </Border>
                    </ControlTemplate>
                </ProgressBar.Template>
            </ProgressBar>
        </StackPanel>
    </Border>
</Window>
'@
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }

    # Callbacks use this script's state, independent of either entry script.
    $script:timerState = [pscustomobject]@{
        Window = $window
        Text = $window.FindName('CountdownText')
        Progress = $window.FindName('RemainingProgress')
        Status = $window.FindName('StatusText')
        Due = $window.FindName('DueText')
        AccentBrush = (New-CountdownBrush $(if ($Action -eq 'Shutdown') { '#D97845' } else { '#4F6BF0' }))
        TextBrush = (New-CountdownBrush '#172033')
        MutedBrush = (New-CountdownBrush '#6B7280')
        WarningBrush = (New-CountdownBrush '#DC5656')
        UserMoved = $false
        Clock = [System.Diagnostics.Stopwatch]::new()
        DurationSeconds = ([double]$Minutes * 60.0)
        Timer = [System.Windows.Threading.DispatcherTimer]::new()
        FinishTimer = [System.Windows.Threading.DispatcherTimer]::new()
        AllowClose = $false
        Started = $false
        Finishing = $false
        Completed = $false
        DryRun = [bool]$DryRun
        Action = $Action
        ActionText = $actionText
        Failure = $null
    }
    $state = $script:timerState
    $window.Title = $caption + ' · 屏幕时间'
    $window.FindName('ActionText').Text = $actionText
    $window.FindName('ActionText').Foreground = $state.AccentBrush
    $window.FindName('ActionBadge').Background = New-CountdownBrush $(if ($Action -eq 'Shutdown') { '#FFF3EB' } else { '#EEF2FF' })
    $window.ToolTip = '拖动可调整位置'
    if ($DryRun) {
        $window.Title += ' · 测试模式'
        $window.FindName('ActionText').Text += ' · 测试'
        $window.ToolTip += '；测试结束不会' + $actionText
    }
    $window.Add_MouseLeftButtonDown({
        $current = $script:timerState
        if (-not $current.Completed) {
            try {
                $current.Window.DragMove()
                $current.UserMoved = $true
            }
            catch [System.InvalidOperationException] { }
        }
    })

    Set-CountdownDisplay ([long]$state.DurationSeconds)
    $state.Timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $state.FinishTimer.Interval = [TimeSpan]::FromSeconds(1)

    $window.Add_Closing({
        param($sender, $eventArgs)
        if (-not $script:timerState.AllowClose) { $eventArgs.Cancel = $true }
    })

    # Start after the first render, not when the process is created.
    $window.Add_ContentRendered({
        $state = $script:timerState
        if (-not $state.Started) {
            $state.Started = $true
            $state.Due.Text = '预计 ' + [DateTime]::Now.AddSeconds($state.DurationSeconds).ToString('HH:mm')
            $state.Window.Left = [math]::Max(0.0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - $state.Window.ActualWidth) / 2.0)
            $state.Clock.Start()
            $state.Timer.Start()
        }
    })

    $state.Timer.Add_Tick({
        try {
            $state = $script:timerState
            if ($state.Finishing -or $state.Completed) { return }
            [long]$remaining = [math]::Max(0.0, [math]::Ceiling(
                $state.DurationSeconds - $state.Clock.Elapsed.TotalSeconds))
            Set-CountdownDisplay $remaining
            if (-not $state.UserMoved) {
                $state.Window.Left = [math]::Max(0.0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - $state.Window.ActualWidth) / 2.0)
            }
            if ($remaining -eq 0) {
                $state.Finishing = $true
                $state.Timer.Stop()
                # Give the dispatcher time to render 00:00 before either action.
                $state.FinishTimer.Start()
            }
        }
        catch {
            $state = $script:timerState
            $state.Failure = '计时失败，未执行' + $state.ActionText + '：' + $_.Exception.Message
            $state.Timer.Stop()
            $state.FinishTimer.Stop()
            $state.Completed = $true
            $state.AllowClose = $true
            $state.Window.Close()
        }
    })

    $state.FinishTimer.Add_Tick({
        $state = $script:timerState
        $state.FinishTimer.Stop()
        if ($state.Completed) { return }
        $state.Completed = $true
        try {
            if (-not $state.DryRun) {
                switch ($state.Action) {
                    'Shutdown' { Stop-Computer -Force -ErrorAction Stop }
                    'Lock' { [ScreenTimeTools.Workstation]::Lock() }
                    default { throw '未知的到期动作。' }
                }
            }
        }
        catch { $state.Failure = $state.ActionText + '请求失败：' + $_.Exception.Message }
        finally {
            $state.AllowClose = $true
            $state.Window.Close()
        }
    })

    $window.Left = [math]::Max(0.0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - 248.0) / 2.0)
    $null = $window.ShowDialog()
    if ($null -ne $state.Failure) { throw $state.Failure }
}
catch {
    $workerExitCode = 1
    try { $null = [System.Windows.MessageBox]::Show($_.Exception.Message, $caption + '错误') }
    catch { [Console]::Error.WriteLine($_.Exception.Message) }
}
finally {
    if ($null -ne $script:timerState) {
        $script:timerState.Timer.Stop()
        $script:timerState.FinishTimer.Stop()
        $script:timerState.Clock.Stop()
    }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $workerExitCode
