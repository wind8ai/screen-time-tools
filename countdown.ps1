#requires -Version 5.1
<#
Shared Windows countdown for shutdown-timer.ps1 and lock-timer.ps1.
The visible launcher reads minutes and starts one hidden STA worker of this file.
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

if (-not $Worker) {
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            throw '本工具需要 Windows 10/11 和 Windows PowerShell 5.1。'
        }
        if (-not $PSBoundParameters.ContainsKey('Minutes')) {
            $inputMinutes = (Read-Host ($caption + '分钟数（回车默认 60）')).Trim()
            if ($inputMinutes -eq '') { $inputMinutes = '60' }
            [int]$parsedMinutes = 0
            if ($inputMinutes -notmatch '^[0-9]+$' -or
                -not [int]::TryParse($inputMinutes, [ref]$parsedMinutes) -or
                $parsedMinutes -le 0) {
                throw '请输入大于 0 的整数分钟数。'
            }
            $Minutes = $parsedMinutes
        }
        $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = '-NoLogo -NoProfile -STA -WindowStyle Hidden -File "{0}" -Action {1} -Minutes {2} -Worker' -f $PSCommandPath, $Action, $Minutes
        if ($DryRun) { $arguments += ' -DryRun' }
        $null = Start-Process -FilePath $powerShellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Write-Host ('已启动{0}计时进程，请确认屏幕顶部出现对应倒计时窗口。' -f $actionText)
        if ($DryRun) { Write-Host ('测试模式：倒计时结束不会{0}。' -f $actionText) }
        elseif ($Action -eq 'Shutdown') { Write-Host '到零后将强制关机，请提前保存工作。' }
        else { Write-Host '到零后将锁定当前 Windows 会话，解锁需要 Windows 登录验证。' }
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
    if ($RemainingSeconds -le 300) {
        $state.Text.Foreground = [System.Windows.Media.Brushes]::Red
    }
    else {
        $state.Text.Foreground = [System.Windows.Media.Brushes]::LimeGreen
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
        $null = [System.Windows.MessageBox]::Show('已有倒计时正在运行。本次不会创建新的关机或锁屏任务。', $caption)
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
        WindowStyle="None" AllowsTransparency="True" Background="#00FFFFFF"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        SizeToContent="Width" MinWidth="110" Height="40" Top="10"
        Title="Screen Time Tools">
    <Grid>
        <Border CornerRadius="8" Background="#B3FFFFFF" BorderBrush="#FFAAAAAA"
                BorderThickness="0.6" Padding="8,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock Name="ActionText" Foreground="#FF666666" FontSize="12"
                           Margin="0,0,7,0" VerticalAlignment="Center"/>
                <TextBlock Name="CountdownText" Foreground="LimeGreen" FontSize="20"
                           FontWeight="Bold" VerticalAlignment="Center"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
'@
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }

    # Callbacks use this script's state, independent of either entry script.
    $script:timerState = [pscustomobject]@{
        Window = $window
        Text = $window.FindName('CountdownText')
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
    $window.Title = $caption
    $window.FindName('ActionText').Text = $actionText
    if ($DryRun) {
        $window.Title += ' - 测试模式'
        $window.FindName('ActionText').Text += '（测试）'
        $window.ToolTip = '测试模式：结束不会' + $actionText
    }
    elseif ($Action -eq 'Shutdown') { $window.ToolTip = '倒计时结束将强制关机，请保存工作' }
    else { $window.ToolTip = '倒计时结束将锁定当前 Windows 会话' }

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
            $state.Window.Left = [math]::Max(0.0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - $state.Window.ActualWidth) / 2.0)
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

    $window.Left = [math]::Max(0.0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - 110.0) / 2.0)
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
