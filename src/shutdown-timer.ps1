#requires -Version 5.1
<#
Windows shutdown timer entry point.
Without -Minutes, open the settings dialog with a default of 60 minutes.
Use -DryRun to test without performing the action.
Keep countdown.ps1 in the same directory.
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

try {
    $component = Join-Path $PSScriptRoot 'countdown.ps1'
    if (-not (Test-Path -LiteralPath $component -PathType Leaf)) {
        throw '缺少 countdown.ps1，请将整个工具目录解压后再运行。'
    }
    # Forward only bound arguments so omitted Minutes opens the settings dialog.
    & $component -Action 'Shutdown' @PSBoundParameters
    exit $LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
