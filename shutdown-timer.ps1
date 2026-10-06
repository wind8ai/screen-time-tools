#requires -Version 5.1
<#
Single-file Windows shutdown timer.
Test: powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1 -Minutes 1 -DryRun
Run:  powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1
The visible launcher starts one hidden STA worker of this same file.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 2147483647)]
    [int]$Minutes = 60,
    [switch]$DryRun,
    [switch]$Worker
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $Worker) {
    try {
        if (-not $PSBoundParameters.ContainsKey('Minutes')) {
            $inputMinutes = (Read-Host '倒计时分钟数（回车默认 60）').Trim()
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
        $arguments = '-NoLogo -NoProfile -STA -WindowStyle Hidden -File "{0}" -Minutes {1} -Worker' -f $PSCommandPath, $Minutes
        if ($DryRun) { $arguments += ' -DryRun' }
        $null = Start-Process -FilePath $powerShellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Write-Host '已启动计时进程，请确认屏幕顶部出现倒计时窗口。'
        if ($DryRun) { Write-Host '测试模式：倒计时结束不会关机。' }
        else { Write-Host '到零后将强制关机，请提前保存工作。' }
        return
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}

$mutex = $null
$ownsMutex = $false
$script:timerState = $null

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
        throw '窗口需要 STA 模式，请按说明启动脚本。'
    }

    # One instance per Windows session. This also covers copies in other folders.
    $mutex = [System.Threading.Mutex]::new($false, 'Local\Wind8ai.WindowsShutdownTimer.v1')
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) {
        $null = [System.Windows.MessageBox]::Show('已有倒计时正在运行。本次不会再创建关机计时器。', '定时关机')
        return
    }

    # Position is assigned as a numeric property, avoiding locale-sensitive XAML.
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None" AllowsTransparency="True" Background="#00FFFFFF"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        SizeToContent="Width" MinWidth="110" Height="40" Top="10"
        Title="Shutdown Timer">
    <Grid>
        <Border CornerRadius="8" Background="#B3FFFFFF" BorderBrush="#FFAAAAAA"
                BorderThickness="0.6" Padding="8,0">
            <TextBlock Name="CountdownText" Foreground="LimeGreen" FontSize="20"
                       FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
    </Grid>
</Window>
'@
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }

    # Shared mutable state avoids event-handler local/global variable confusion.
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
        DryRun = [bool]$DryRun
        Failure = $null
    }
    $state = $script:timerState
    if ($DryRun) {
        $window.Title = 'Shutdown Timer - DRY RUN'
        $window.ToolTip = '测试模式：结束不会关机'
    }
    else { $window.ToolTip = '倒计时结束将强制关机，请保存工作' }

    Set-CountdownDisplay ([long]$state.DurationSeconds)
    $state.Timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $state.FinishTimer.Interval = [TimeSpan]::FromSeconds(1)

    $window.Add_Closing({
        param($sender, $eventArgs)
        if (-not $script:timerState.AllowClose) { $eventArgs.Cancel = $true }
    })

    # Begin timing only after the window is rendered, rather than during startup.
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
            [long]$remaining = [math]::Max(0.0, [math]::Ceiling(
                $state.DurationSeconds - $state.Clock.Elapsed.TotalSeconds))
            Set-CountdownDisplay $remaining
            $state.Window.Left = [math]::Max(0.0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - $state.Window.ActualWidth) / 2.0)
            if ($remaining -eq 0 -and -not $state.Finishing) {
                $state.Finishing = $true
                $state.Timer.Stop()
                # Return to the dispatcher so 00:00 can render before shutdown.
                $state.FinishTimer.Start()
            }
        }
        catch {
            $state = $script:timerState
            $state.Failure = '计时失败，未执行关机：' + $_.Exception.Message
            $state.Timer.Stop()
            $state.FinishTimer.Stop()
            $state.AllowClose = $true
            $state.Window.Close()
        }
    })

    $state.FinishTimer.Add_Tick({
        $state = $script:timerState
        $state.FinishTimer.Stop()
        try {
            if (-not $state.DryRun) {
                Stop-Computer -Force -ErrorAction Stop
            }
        }
        catch { $state.Failure = '关机失败：' + $_.Exception.Message }
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
    try { $null = [System.Windows.MessageBox]::Show($_.Exception.Message, '定时关机错误') }
    catch { [Console]::Error.WriteLine($_.Exception.Message) }
    exit 1
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
