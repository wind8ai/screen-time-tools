#requires -Version 5.1
<#
Windows lock-screen timer entry point.
Without -Minutes, open the settings dialog with a default of 60 minutes.
Use -DryRun to test without performing the action.
Keep countdown.ps1 and language resources in the same tool folder.
语言可通过 -Language 或 config/settings.json 指定；省略时跟随配置。
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 2147483647)]
    [int]$Minutes = 60,
    [switch]$DryRun,
    [switch]$Worker,
    [ValidateSet('auto', 'zh-CN', 'en-US')]
    [string]$Language
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

try {
    . (Join-Path $PSScriptRoot 'localization.ps1')
    Set-ScreenTimeLanguage (Resolve-ScreenTimeLanguage -RequestedLanguage $Language)
    $component = Join-Path $PSScriptRoot 'countdown.ps1'
    if (-not (Test-Path -LiteralPath $component -PathType Leaf)) {
        throw (Get-ScreenTimeText 'MissingCountdown')
    }
    # Forward only bound arguments so omitted Minutes opens the settings dialog.
    # 只转发显式参数，确保省略 Minutes 时打开设置窗口。
    & $component -Action 'Lock' @PSBoundParameters
    exit $LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
