# Configuration

[English](CONFIGURATION.md) | [简体中文](CONFIGURATION.zh-CN.md) · [User guide](../README.md)

The tool reads `config/settings.json` relative to its own directory, independently of the current working directory. Keep this file with the extracted repository. JSON uses UTF-8 and does not allow comments.

```json
{
  "language": "auto"
}
```

| Value | Behavior |
| --- | --- |
| `auto` | Simplified Chinese for system UI locales beginning with `zh`; English otherwise |
| `zh-CN` | Simplified Chinese |
| `en-US` | English |

Language selection follows these rules:

1. An explicit `-Language` argument overrides the configured language, including explicit `-Language auto`.
2. Without that argument, `language` in the configuration decides the default.
3. `auto` resolves using the system UI language.
4. A selection in the settings window overrides the language for that window and the countdown it launches.
5. The countdown's right-click menu can change the display language while keeping the original elapsed time and expected action time.

UI choices are not saved to disk. Edit `config/settings.json` to change the default for future launches. Invalid or missing configuration produces an error rather than silently choosing another language. If `-Language` explicitly supplies a valid value, the configuration is not read.

The following commands open settings in a chosen language:

```powershell
.\start-lock.bat -Language en-US
.\start-shutdown.bat -Language zh-CN
powershell.exe -NoProfile -STA -File .\src\lock-timer.ps1 -Language auto
```

Both entry points accept `-Minutes`, `-DryRun` and `-Language`. Omitting `-Minutes` opens settings; it does not implicitly start a timer. The default duration remains 60 minutes, independent of language. Presets remain 10, 15, 20, 25, 30, 45, 60 and 90 minutes.

Application messages, validation, accessibility labels, test mode and countdown states come from `src/locales/en-US.psd1` and `src/locales/zh-CN.psd1`. Bootstrap errors before resources can load, and test assertion diagnostics, use a shared bilingual or English diagnostic; operating-system errors retain the system's own wording.
