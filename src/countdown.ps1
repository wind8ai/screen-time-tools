#requires -Version 5.1
<#
Shared Windows countdown for shutdown-timer.ps1 and lock-timer.ps1.
The launcher opens a duration picker and starts one hidden STA worker of this file.
Only the worker owns the countdown window and the eventual action.
锁屏与关机共用设置、倒计时及语言资源；只有工作进程执行到期动作。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Shutdown', 'Lock')]
    [string]$Action,
    [ValidateRange(1, 2147483647)]
    [int]$Minutes = 60,
    [switch]$DryRun,
    [switch]$Worker,
    [ValidateSet('auto', 'zh-CN', 'en-US')]
    [string]$Language
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'localization.ps1')
Set-ScreenTimeLanguage (Resolve-ScreenTimeLanguage -RequestedLanguage $Language)

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
        $day = if ($due.Date -eq [DateTime]::Today) { Get-ScreenTimeText 'Today' } else {
            $due.ToString((Get-ScreenTimeText 'DateFormat'), $script:uiCulture)
        }
        $state.Estimate.Text = Get-ScreenTimeText 'EstimateTime' @($day, $due.ToString('HH:mm', $script:uiCulture))
    }
    else {
        $state.Error.Text = Get-ScreenTimeText 'MinutesInvalid'
        $state.InputBorder.BorderBrush = $state.WarningBrush
        $state.Estimate.Text = Get-ScreenTimeText 'EstimateEmpty'
    }
    foreach ($button in $state.Presets) {
        $selected = $valid -and [int]$button.Tag -eq $value
        $button.Background = if ($selected) { $state.AccentSoft } else { $state.NeutralSoft }
        $button.Foreground = if ($selected) { $state.AccentBrush } else { $state.TextBrush }
        $button.BorderBrush = if ($selected) { $state.AccentBrush } else { $state.BorderBrush }
    }
}

function Update-SetupLanguage {
    $state = $script:setupState
    $window = $state.Window
    $mode = $state.Mode
    $window.Title = Get-ScreenTimeText 'WindowTitle' @((Get-ScreenTimeText ($mode + 'Caption')))
    $window.FontFamily = [System.Windows.Media.FontFamily]::new(
        $(if ($script:uiLanguage -eq 'zh-CN') { 'Microsoft YaHei UI' } else { 'Segoe UI' }))
    $window.FindName('AppLabel').Text = Get-ScreenTimeText $(if ($state.TestMode) { 'TestAppName' } else { 'AppName' })
    $window.FindName('HeadingText').Text = Get-ScreenTimeText ($mode + $(if ($state.TestMode) { 'TestHeading' } else { 'Heading' }))
    $window.FindName('SubtitleText').Text = Get-ScreenTimeText ($mode + $(if ($state.TestMode) { 'TestSubtitle' } else { 'Subtitle' }))
    $window.FindName('HintText').Text = Get-ScreenTimeText $(if ($state.TestMode) { 'TestHint' } else { $mode + 'Hint' })
    $window.FindName('EstimateLabel').Text = Get-ScreenTimeText $(if ($state.TestMode) { 'TestEstimateLabel' } else { $mode + 'EstimateLabel' })
    $window.FindName('CustomDurationLabel').Text = Get-ScreenTimeText 'CustomDuration'
    $window.FindName('MinutesUnitLabel').Text = Get-ScreenTimeText 'MinutesUnit'
    $window.FindName('CancelButton').Content = Get-ScreenTimeText 'Cancel'
    $state.Start.Content = Get-ScreenTimeText 'Start'
    [System.Windows.Automation.AutomationProperties]::SetName($state.Input, (Get-ScreenTimeText 'MinutesInputName'))
    [System.Windows.Automation.AutomationProperties]::SetName($window.FindName('CloseButton'), (Get-ScreenTimeText 'CloseName'))
    [System.Windows.Automation.AutomationProperties]::SetName($window.FindName('LanguagePicker'), (Get-ScreenTimeText 'LanguagePickerName'))
    foreach ($button in $state.Presets) {
        $button.Content = Get-ScreenTimeText 'MinutesPreset' @([int]$button.Tag)
    }
    Update-DurationPreview
}

function Show-DurationPicker {
    param([string]$Mode, [bool]$TestMode)
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw (Get-ScreenTimeText 'NeedsSTA')
    }
    $accent = if ($Mode -eq 'Shutdown') { '#D97845' } else { '#4F6BF0' }
    $soft = if ($Mode -eq 'Shutdown') { '#FFF3EB' } else { '#EEF2FF' }
    [xml]$setupXaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ui\duration-picker.xaml') -Raw -Encoding UTF8
    $reader = [System.Xml.XmlNodeReader]::new($setupXaml)
    try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }
    # Initialize every field before attaching callbacks to the modal dialog.
    # 注册设置窗口回调前，初始化全部状态。
    $script:setupState = [pscustomobject]@{
        Window = $window
        Mode = $Mode
        TestMode = $TestMode
        Input = $window.FindName('MinutesInput')
        InputBorder = $window.FindName('MinutesBorder')
        Error = $window.FindName('ValidationText')
        Estimate = $window.FindName('EstimateText')
        Start = $window.FindName('StartButton')
        Presets = @(10, 15, 20, 25, 30, 45, 60, 90 | ForEach-Object {
            $window.FindName('Preset' + $_)
        })
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
        $window.FindName('EstimatePanel').Background = $state.AccentSoft
        $state.Estimate.Foreground = $state.AccentBrush
        $state.Start.Background = $state.AccentBrush
        $state.Start.BorderBrush = $state.AccentBrush
        $languagePicker = $window.FindName('LanguagePicker')
        $languagePicker.SelectedIndex = if ($script:uiLanguage -eq 'zh-CN') { 0 } else { 1 }
        $languagePicker.Add_SelectionChanged({
            param($sender, $eventArgs)
            if ($null -ne $sender.SelectedItem) {
                Set-ScreenTimeLanguage ([string]$sender.SelectedItem.Tag)
                Update-SetupLanguage
            }
        })
        Update-SetupLanguage
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
            throw (Get-ScreenTimeText 'NeedsWindows')
        }
        if (-not $PSBoundParameters.ContainsKey('Minutes')) {
            $pickedMinutes = Show-DurationPicker -Mode $Action -TestMode ([bool]$DryRun)
            if ($null -eq $pickedMinutes) { exit 0 }
            $Minutes = [int]$pickedMinutes
        }
        $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = '-NoLogo -NoProfile -STA -WindowStyle Hidden -File "{0}" -Action {1} -Minutes {2} -Language {3} -Worker' -f $PSCommandPath, $Action, $Minutes, $script:uiLanguage
        if ($DryRun) { $arguments += ' -DryRun' }
        $null = Start-Process -FilePath $powerShellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Write-Host (Get-ScreenTimeText 'Opening')
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
        if ($state.DryRun) { Get-ScreenTimeText 'StatusTestFinished' } else { Get-ScreenTimeText ($state.Action + 'StatusEnding') }
    }
    elseif ($warning) {
        if ($state.DryRun) { Get-ScreenTimeText 'StatusTestEnding' } else { Get-ScreenTimeText ($state.Action + 'StatusFinishing') }
    }
    else {
        Get-ScreenTimeText $(if ($state.DryRun) { 'StatusTestRunning' } else { 'StatusRunning' })
    }
}

function Update-CountdownLanguage {
    $state = $script:timerState
    $window = $state.Window
    $state.ActionText = Get-ScreenTimeText ($state.Action + 'Action')
    $window.Title = Get-ScreenTimeText 'WindowTitle' @((Get-ScreenTimeText ($state.Action + 'Caption')))
    $window.FontFamily = [System.Windows.Media.FontFamily]::new(
        $(if ($script:uiLanguage -eq 'zh-CN') { 'Microsoft YaHei UI' } else { 'Segoe UI' }))
    $window.FindName('ActionText').Text = $state.ActionText
    $window.ToolTip = Get-ScreenTimeText 'DragHint'
    if ($state.DryRun) {
        $window.Title = Get-ScreenTimeText 'TestTitle' @($window.Title)
        $window.FindName('ActionText').Text = Get-ScreenTimeText 'TestBadge' @($state.ActionText)
        $window.ToolTip = Get-ScreenTimeText 'TestTooltip' @($window.ToolTip)
    }
    if ($null -ne $state.DueTime) {
        $state.Due.Text = Get-ScreenTimeText 'DueTime' @($state.DueTime.ToString('HH:mm', $script:uiCulture))
    }
    foreach ($item in $window.ContextMenu.Items) {
        $item.IsChecked = $item.Tag -eq $script:uiLanguage
    }
    Set-CountdownDisplay ([long][math]::Max(0.0, [math]::Ceiling($state.DurationSeconds - $state.Clock.Elapsed.TotalSeconds)))
}

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw (Get-ScreenTimeText 'NeedsSTA')
    }

    # Reuse the previous shutdown timer's mutex for running-copy compatibility.

    # 沿用旧版互斥锁，防止旧版和新版同时运行计时。
    # Shutdown, lock and DryRun all share one timer per Windows session.
    # 关机、锁屏和测试模式在同一 Windows 会话中共用一个计时任务。
    $mutex = [System.Threading.Mutex]::new($false, 'Local\Wind8ai.WindowsShutdownTimer.v1')
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) {
        $null = [System.Windows.MessageBox]::Show(
            (Get-ScreenTimeText 'OnlyOne'), (Get-ScreenTimeText 'AppName'),
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        exit 1
    }

    # Compile before starting the clock. DryRun never loads the native wrapper.

    # 开始计时前编译原生接口；测试模式不加载原生接口。
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

    # 用数值设置位置，避免区域格式影响 XAML。
    [xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ui\countdown.xaml') -Raw -Encoding UTF8
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }

    # Callbacks use this script's state, independent of either entry script.

    # 回调使用当前脚本状态，不依赖锁屏或关机入口。
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
        ActionText = (Get-ScreenTimeText ($Action + 'Action'))
        DueTime = $null
        Failure = $null
    }
    $state = $script:timerState
    $window.FindName('ActionText').Foreground = $state.AccentBrush
    $window.FindName('ActionBadge').Background = New-CountdownBrush $(if ($Action -eq 'Shutdown') { '#FFF3EB' } else { '#EEF2FF' })
    $window.ContextMenu = [System.Windows.Controls.ContextMenu]::new()
    foreach ($locale in @('zh-CN', 'en-US')) {
        $item = [System.Windows.Controls.MenuItem]::new()
        $item.Header = if ($locale -eq 'zh-CN') { '中文' } else { 'English' }
        $item.Tag = $locale
        $item.IsCheckable = $true
        $item.Add_Click({
            param($sender, $eventArgs)
            Set-ScreenTimeLanguage ([string]$sender.Tag)
            Update-CountdownLanguage
        })
        $null = $window.ContextMenu.Items.Add($item)
    }
    Update-CountdownLanguage
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

    # 第一次完成渲染后开始计时。
    $window.Add_ContentRendered({
        $state = $script:timerState
        if (-not $state.Started) {
            $state.Started = $true
            $state.DueTime = [DateTime]::Now.AddSeconds($state.DurationSeconds)
            $state.Due.Text = Get-ScreenTimeText 'DueTime' @($state.DueTime.ToString('HH:mm', $script:uiCulture))
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
                # 为窗口留出显示 00:00 的时间，然后执行到期动作。
                $state.FinishTimer.Start()
            }
        }
        catch {
            $state = $script:timerState
            $state.Failure = Get-ScreenTimeText 'TimingFailed' @($state.ActionText, $_.Exception.Message)
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
                    default { throw (Get-ScreenTimeText 'UnknownAction') }
                }
            }
        }
        catch { $state.Failure = Get-ScreenTimeText 'RequestFailed' @($state.ActionText, $_.Exception.Message) }
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
    try { $null = [System.Windows.MessageBox]::Show($_.Exception.Message, (Get-ScreenTimeText 'ErrorTitle')) }
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
