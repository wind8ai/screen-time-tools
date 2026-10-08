#requires -Version 5.1
# Verify language behavior without loading WPF or executing native actions.
# 不加载 WPF、不执行锁屏或关机，验证语言资源和选择规则。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\localization.ps1')

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) {
        throw ('{0}: expected [{1}], got [{2}]' -f $Message, $Expected, $Actual)
    }
}

$english = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'src\locales\en-US.psd1')
$chinese = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'src\locales\zh-CN.psd1')
Assert-Equal (($english.Keys | Sort-Object) -join ',') (($chinese.Keys | Sort-Object) -join ',') 'Translation key parity'
foreach ($key in $english.Keys) {
    if ([string]::IsNullOrWhiteSpace($english[$key]) -or [string]::IsNullOrWhiteSpace($chinese[$key])) {
        throw ('Empty translation: ' + $key)
    }
    $pattern = '\{[0-9]+\}'
    Assert-Equal (([regex]::Matches($english[$key], $pattern) | ForEach-Object { $_.Value } | Sort-Object) -join ',') `
        (([regex]::Matches($chinese[$key], $pattern) | ForEach-Object { $_.Value } | Sort-Object) -join ',') ('Format placeholders: ' + $key)
}
Assert-Equal (Resolve-ScreenTimeLanguage -RequestedLanguage 'auto' -SystemLanguage 'zh-TW') 'zh-CN' 'Chinese system locale'
Assert-Equal (Resolve-ScreenTimeLanguage -RequestedLanguage 'auto' -SystemLanguage 'en-GB') 'en-US' 'English system locale'
Assert-Equal (Resolve-ScreenTimeLanguage -RequestedLanguage 'auto' -SystemLanguage 'fr-FR') 'en-US' 'Other system locale'
Assert-Equal (Resolve-ScreenTimeLanguage -RequestedLanguage 'en-US' -SystemLanguage 'zh-CN') 'en-US' 'CLI overrides system'

$settingsPath = Join-Path ([System.IO.Path]::GetTempPath()) ('screen-time-language-' + [Guid]::NewGuid().ToString('N') + '.json')
try {
    Set-Content -LiteralPath $settingsPath -Value '{"language":"zh-CN"}' -Encoding UTF8
    Assert-Equal (Resolve-ScreenTimeLanguage -SettingsPath $settingsPath -SystemLanguage 'en-US') 'zh-CN' 'Config overrides system'
    Assert-Equal (Resolve-ScreenTimeLanguage -RequestedLanguage 'en-US' -SettingsPath $settingsPath) 'en-US' 'CLI overrides config'
    Assert-Equal (Resolve-ScreenTimeLanguage -RequestedLanguage 'auto' -SettingsPath $settingsPath -SystemLanguage 'en-US') 'en-US' 'Explicit auto overrides config'
    Set-Content -LiteralPath $settingsPath -Value '{"language":"invalid"}' -Encoding UTF8
    $rejected = $false
    try { $null = Resolve-ScreenTimeLanguage -SettingsPath $settingsPath }
    catch { $rejected = $true }
    Assert-Equal $rejected $true 'Reject invalid config language'
}
finally { Remove-Item -LiteralPath $settingsPath -ErrorAction SilentlyContinue }

foreach ($locale in @('zh-CN', 'en-US')) {
    Set-ScreenTimeLanguage $locale
    $expected = if ($locale -eq 'zh-CN') { '60 分钟' } else { '60 min' }
    Assert-Equal (Get-ScreenTimeText 'MinutesPreset' @(60)) $expected 'Localized preset'
    $expected = if ($locale -eq 'zh-CN') { '预计 15:00' } else { 'Due 15:00' }
    Assert-Equal (Get-ScreenTimeText 'DueTime' @('15:00')) $expected 'Localized due time'
    # A missing key must fail instead of displaying a resource identifier.
    # 翻译缺失必须报错，不能在界面中显示资源键。
    $rejected = $false
    try { $null = Get-ScreenTimeText 'NoSuchTranslation' }
    catch { $rejected = $true }
    Assert-Equal $rejected $true 'Reject missing translation'
}

# Inspect the real functions without executing the timer program.
# 提取真实显示函数进行检查，不执行整个计时程序。
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'src\countdown.ps1'), [ref]$tokens, [ref]$errors)
foreach ($name in @('Update-DurationPreview', 'Set-CountdownDisplay')) {
    $function = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    Invoke-Expression $function.Extent.Text
}
$script:setupState = [pscustomobject]@{
    Submitted = $false
    Input = [pscustomobject]@{ Text = 'invalid' }
    InputBorder = [pscustomobject]@{ BorderBrush = '' }
    Error = [pscustomobject]@{ Text = '' }
    Estimate = [pscustomobject]@{ Text = '' }
    Start = [pscustomobject]@{ IsEnabled = $false }
    Presets = @()
    BorderBrush = 'border'
    WarningBrush = 'warning'
}
$script:timerState = [pscustomobject]@{
    Text = [pscustomobject]@{ Text = ''; Foreground = '' }
    Progress = [pscustomobject]@{ Value = 0; Foreground = '' }
    Status = [pscustomobject]@{ Text = ''; Foreground = '' }
    DurationSeconds = 3600.0
    DryRun = $false
    Action = 'Lock'
    TextBrush = 'text'
    WarningBrush = 'warning'
    AccentBrush = 'accent'
    MutedBrush = 'muted'
}
foreach ($locale in @('zh-CN', 'en-US')) {
    Set-ScreenTimeLanguage $locale
    Update-DurationPreview
    Assert-Equal $script:setupState.Error.Text (Get-ScreenTimeText 'MinutesInvalid') 'Localized validation error'
    foreach ($action in @('Lock', 'Shutdown')) {
        $script:timerState.Action = $action
        $script:timerState.DryRun = $false
        Set-CountdownDisplay 300
        Assert-Equal $script:timerState.Status.Text (Get-ScreenTimeText ($action + 'StatusFinishing')) 'Localized warning'
        Assert-Equal $script:timerState.Text.Text '05:00' 'Language does not change duration'
        $script:timerState.DryRun = $true
        Set-CountdownDisplay 0
        Assert-Equal $script:timerState.Status.Text (Get-ScreenTimeText 'StatusTestFinished') 'Localized test completion'
    }
}
$script:setupState = $null
$script:timerState = $null
