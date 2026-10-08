# 配置说明

[English](CONFIGURATION.md) | [简体中文](CONFIGURATION.zh-CN.md) · [使用说明](../README.zh-CN.md)

程序根据自身所在目录读取 `config/settings.json`，不依赖当前工作目录。请保留该配置文件。JSON 使用 UTF-8，不支持注释。

```json
{
  "language": "auto"
}
```

| 值 | 行为 |
| --- | --- |
| `auto` | 系统界面语言以 `zh` 开头时显示简体中文，其他情况显示英文 |
| `zh-CN` | 简体中文 |
| `en-US` | 英文 |

语言选择按以下规则执行：

1. 显式传入 `-Language` 时覆盖配置值，包括显式的 `-Language auto`。
2. 未传入该参数时，使用配置中的 `language`。
3. `auto` 根据系统界面语言选择中文或英文。
4. 设置窗口中的选择覆盖该窗口和它启动的倒计时进程所用的语言。
5. 倒计时的右键菜单可再次切换显示语言，已经经过的时间和预计执行时间保持原值。

界面选择不会写入磁盘。要修改未来启动的默认语言，请编辑 `config/settings.json`。无效或缺失配置会报错，不会静默改用其他语言。显式传入有效的 `-Language` 时，不读取配置文件。

以下命令可按指定语言打开设置窗口：

```powershell
.\start-lock.bat -Language en-US
.\start-shutdown.bat -Language zh-CN
powershell.exe -NoProfile -STA -File .\src\lock-timer.ps1 -Language auto
```

两种入口均支持 `-Minutes`、`-DryRun`、`-Language`。省略 `-Minutes` 会打开设置窗口，不会直接开始计时。语言不会改变默认 60 分钟或 10、15、20、25、30、45、60、90 分钟预设。

应用文案、输入校验、无障碍标签、测试模式和倒计时状态来自 `src/locales/en-US.psd1` 与 `src/locales/zh-CN.psd1`。语言资源加载前的启动错误和测试断言使用共用的双语或英文诊断；操作系统错误保留系统原有文字。
