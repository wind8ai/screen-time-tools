#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) {
        throw ('{0}: expected [{1}], got [{2}]' -f $Message, $Expected, $Actual)
    }
}

$source = Join-Path $root 'src\countdown.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $source, [ref]$tokens, [ref]$parseErrors)

# Load only the display functions. Never dot-source a timer entry point.
foreach ($name in @('Update-DurationPreview', 'Set-CountdownDisplay')) {
    $function = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $function) { throw ('Missing function: ' + $name) }
    Invoke-Expression $function.Extent.Text
}

[xml]$picker = Get-Content -LiteralPath (Join-Path $root 'src\ui\duration-picker.xaml') -Raw -Encoding UTF8
[xml]$countdown = Get-Content -LiteralPath (Join-Path $root 'src\ui\countdown.xaml') -Raw -Encoding UTF8
$grid = $picker.SelectSingleNode('//*[local-name()="UniformGrid"]')
$presets = @($grid.SelectNodes('*[local-name()="Button"]'))
Assert-Equal (($presets | ForEach-Object { $_.Tag }) -join ',') '10,15,20,25,30,45,60,90' 'Preset order'
Assert-Equal $grid.Rows '2' 'Preset rows'
Assert-Equal $grid.Columns '4' 'Preset columns'
foreach ($preset in $presets) {
    Assert-Equal $preset.Name ('Preset' + $preset.Tag) 'Preset binding'
}

# Every FindName reference must resolve to a control in the external layouts.
$names = @($picker.SelectNodes('//*[@Name]') | ForEach-Object { $_.Name })
$names += @($countdown.SelectNodes('//*[@Name]') | ForEach-Object { $_.Name })
$sourceText = Get-Content -LiteralPath $source -Raw -Encoding UTF8
foreach ($match in [regex]::Matches($sourceText, "FindName\('([^']+)'\)")) {
    if ($names -notcontains $match.Groups[1].Value) { throw ('Missing XAML control: ' + $match.Groups[1].Value) }
}

foreach ($mode in @('lock', 'shutdown')) {
    $launcher = Get-Content -LiteralPath (Join-Path $root ('start-' + $mode + '.bat')) -Raw
    $match = [regex]::Match($launcher, '-File "%~dp0([^"]+)"')
    if (-not $match.Success -or -not (Test-Path -LiteralPath (Join-Path $root $match.Groups[1].Value))) {
        throw ('Broken launcher path: ' + $mode)
    }
}

# Fake controls exercise real callbacks without WPF or a worker process.
$script:setupState = [pscustomobject]@{
    Submitted = $false
    Input = [pscustomobject]@{ Text = '60' }
    InputBorder = [pscustomobject]@{ BorderBrush = '' }
    Error = [pscustomobject]@{ Text = '' }
    Estimate = [pscustomobject]@{ Text = '' }
    Start = [pscustomobject]@{ IsEnabled = $false }
    Presets = @($presets | ForEach-Object {
        [pscustomobject]@{ Tag = $_.Tag; Background = ''; Foreground = ''; BorderBrush = '' }
    })
    AccentSoft = 'selected-background'
    AccentBrush = 'accent'
    NeutralSoft = 'neutral'
    TextBrush = 'text'
    BorderBrush = 'border'
    WarningBrush = 'warning'
}
foreach ($value in @(10, 15, 20, 25, 30, 45, 60, 90, 1, 37, 1440)) {
    $script:setupState.Input.Text = [string]$value
    Update-DurationPreview
    Assert-Equal $script:setupState.Start.IsEnabled $true ('Accept minutes: ' + $value)
    Assert-Equal $script:setupState.Error.Text '' 'Clear validation error'
    foreach ($button in $script:setupState.Presets) {
        $expected = if ([int]$button.Tag -eq $value) { 'selected-background' } else { 'neutral' }
        Assert-Equal $button.Background $expected ('Selected preset for ' + $value)
    }
}
foreach ($value in @('', '0', '-1', '1.5', 'abc', '2147483648')) {
    $script:setupState.Input.Text = $value
    Update-DurationPreview
    Assert-Equal $script:setupState.Start.IsEnabled $false ('Reject minutes: ' + $value)
    Assert-Equal $script:setupState.InputBorder.BorderBrush 'warning' 'Invalid input border'
}

$script:timerState = [pscustomobject]@{
    Text = [pscustomobject]@{ Text = ''; Foreground = '' }
    Progress = [pscustomobject]@{ Value = 0; Foreground = '' }
    Status = [pscustomobject]@{ Text = ''; Foreground = '' }
    DurationSeconds = 3600.0
    DryRun = $false
    ActionText = 'lock'
    TextBrush = 'text'
    WarningBrush = 'warning'
    AccentBrush = 'accent'
    MutedBrush = 'muted'
}
Set-CountdownDisplay 301
Assert-Equal $script:timerState.Text.Text '05:01' 'Countdown formatting'
Assert-Equal $script:timerState.Text.Foreground 'text' 'Before warning threshold'
Set-CountdownDisplay 300
Assert-Equal $script:timerState.Text.Foreground 'warning' 'Five-minute warning'
Set-CountdownDisplay 0
Assert-Equal $script:timerState.Text.Text '00:00' 'Finished display'
Assert-Equal $script:timerState.Progress.Value 0 'Finished progress'
$normalStatus = $script:timerState.Status.Text
$script:timerState.DryRun = $true
Set-CountdownDisplay 0
if ($script:timerState.Status.Text -eq $normalStatus) { throw 'DryRun must show its own completion status.' }

$script:setupState = $null
$script:timerState = $null
