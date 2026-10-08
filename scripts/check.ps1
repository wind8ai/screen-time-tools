#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Parse without executing any timer or native Windows action.
$files = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.ps1' -Recurse)
$files += @(Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter '*.ps1' -Recurse)
$files += Get-Item -LiteralPath $PSCommandPath
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw ('PowerShell syntax errors in {0}: {1}' -f $file.Name, ($parseErrors.Message -join '; '))
    }
}

& (Join-Path $root 'tests\countdown.tests.ps1')
Write-Host 'PASS: PowerShell syntax, resource paths, presets and countdown behavior.'
