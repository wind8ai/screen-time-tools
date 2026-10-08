# Development and validation

[English](DEVELOPMENT.md) | [简体中文](DEVELOPMENT.zh-CN.md) · [User guide](../README.md)

## Responsibilities

- Root: bilingual README files, Git settings and the two user-facing BAT launchers.
- `config/`: the default UI language, documented in the bilingual [configuration guide](CONFIGURATION.md).
- `src/`: PowerShell entry points, shared countdown behavior and localization functions.
- `src/locales/`: matching `en-US.psd1` and `zh-CN.psd1` text dictionaries.
- `src/ui/`: language-neutral WPF XAML layouts, with no countdown logic.
- `scripts/` and `tests/`: dependency-free PowerShell syntax and regression checks.
- `docs/`: paired English/Chinese guides and preview illustrations.

BAT launchers resolve `src/` through `%~dp0`. Scripts resolve UI resources, locale dictionaries and configuration relative to `$PSScriptRoot`, so launching from a different working directory works. Distribute the complete directory tree.

## Encoding and runtime

`.ps1` and `.psd1` files use **UTF-8 with BOM and CRLF** for Windows PowerShell 5.1 compatibility. BAT files use ASCII and CRLF. JSON and XAML use UTF-8; the scripts read them explicitly as UTF-8. Git attributes normalize repository line endings and restore Windows endings on checkout.

The app targets Windows 10/11, an interactive signed-in desktop and built-in Windows PowerShell 5.1. Launchers use `-STA` for WPF. Localization and tests use built-in PowerShell APIs; no translation service or additional runtime dependency is required by the app.

## Text resources

User-facing strings belong in both locale dictionaries. Use the same keys and format placeholders, and reference them through `Get-ScreenTimeText`. Code identifiers remain stable in English; key implementation comments explain the behavior in English and Chinese.

`Resolve-ScreenTimeLanguage` implements CLI/config/system selection. `Update-SetupLanguage` updates settings text and validation. The selected locale is explicitly passed to the worker. `Update-CountdownLanguage` refreshes the countdown's text without resetting its stopwatch, due time or duration.

A settings dropdown and a countdown context menu expose the language choices. Their language names remain `中文` and `English` so either audience can recognize them.

## Automated checks

From the repository root:

```powershell
powershell.exe -NoProfile -File .\scripts\check.ps1 -Language en-US
powershell.exe -NoProfile -File .\scripts\check.ps1 -Language zh-CN
```

On macOS/Linux with PowerShell 7:

```sh
pwsh -NoProfile -File ./scripts/check.ps1 -Language en-US
```

Checks cover syntax, BAT targets, XAML control names, the eight presets, input validation, countdown formatting, the five-minute warning boundary, language key/placeholder parity, CLI/config/system precedence, and localized messages for both actions and test mode. Tests use simulated controls and never launch a timer or invoke native actions.

### Validation record — October 8, 2026

PowerShell 7.5.4 checks passed on macOS in both Chinese and English. Locale resources, XAML, launch paths, file encodings, document links and both previews were also checked. Windows PowerShell 5.1 compatibility, actual WPF rendering and real lock/shutdown actions still require Windows verification; PowerShell 7 checks do not confirm those outcomes.

## Windows manual verification

1. Run automated checks in Windows PowerShell 5.1, in both languages.
2. Open each BAT launcher separately. Verify the settings dropdown switches all labels, accessibility names, error messages and expected times; the input value and selected duration remain unchanged.
3. Test `auto`, `zh-CN` and `en-US` in configuration. Confirm CLI overrides configuration and explicit `-Language auto` follows the system.
4. Click each preset: 10, 15, 20, 25, 30, 45, 60 and 90. Default selection is 60. Verify custom `37` is accepted and empty input, zero, negatives, decimals and text are rejected.
5. Run the following tests **one at a time**. Confirm the chosen language reaches the countdown, right-click switching leaves the due time and countdown intact, and the window closes after `00:00` without any native action:

   ```powershell
   powershell.exe -NoProfile -STA -File .\src\lock-timer.ps1 -Minutes 1 -DryRun -Language en-US
   powershell.exe -NoProfile -STA -File .\src\shutdown-timer.ps1 -Minutes 1 -DryRun -Language zh-CN
   ```

6. While a test runs, start another timer. Confirm the localized duplicate-task message appears and the original task continues.
7. Verify dragging and text layout at multiple display scaling settings, in both languages. Test an extracted folder with spaces and Chinese characters in its path, launching from another working directory.

Save your work before separately verifying real lock or force-shutdown actions.

## Previews

`images/overview.svg` / `.png` show Chinese; `images/overview.en.svg` / `.png` show English. They illustrate the app's XAML, palette and actual text resources. The example times are fixed. Windows controls, fonts, shadows and dimensions can render differently.
