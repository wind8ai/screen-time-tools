#requires -Version 5.1
# Shared language resources; no WPF or timer side effects.
# 共用语言资源；不会加载窗口或启动计时。
Set-StrictMode -Version 2.0

function Resolve-ScreenTimeLanguage {
    param(
        [string]$RequestedLanguage,
        [string]$SettingsPath = (Join-Path $PSScriptRoot '..\config\settings.json'),
        [string]$SystemLanguage = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    )
    $choice = $RequestedLanguage
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $choice = $settings.language
    }
    if ($choice -notin @('auto', 'zh-CN', 'en-US')) {
        throw 'Invalid language: use auto, zh-CN or en-US. / 无效语言：请使用 auto、zh-CN 或 en-US。'
    }
    if ($choice -eq 'auto') {
        if ($SystemLanguage -match '^zh(?:-|$)') { return 'zh-CN' }
        return 'en-US'
    }
    return $choice
}

function Set-ScreenTimeLanguage {
    param([ValidateSet('zh-CN', 'en-US')][string]$Language)
    $script:strings = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot ('locales\' + $Language + '.psd1'))
    $script:uiLanguage = $Language
    $script:uiCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Language)
}

function Get-ScreenTimeText {
    param([string]$Key, [object[]]$Arguments = @())
    if (-not $script:strings.ContainsKey($Key)) {
        throw ('Missing translation / 缺少翻译: ' + $Key)
    }
    return ($script:strings[$Key] -f $Arguments)
}
