# Screen Time Tools

Windows 定时锁屏与定时关机工具。选择时长后，桌面顶部的悬浮倒计时显示剩余时间；到点执行所选操作。

无需安装额外软件，适用于 **Windows 10/11 + 系统自带的 Windows PowerShell 5.1**，在已登录的桌面中使用。

## 效果预览

![锁屏与关机设置窗口，以及悬浮倒计时示意](docs/images/overview.png)

*按实际 XAML 布局绘制的效果示意，非 Windows 运行截图。示例时刻仅用于展示。*

## 快速开始

1. [下载仓库 ZIP](https://github.com/wind8ai/screen-time-tools/archive/refs/heads/main.zip)，或克隆仓库，然后完整解压、保留目录结构。
2. 双击根目录的 `start-lock.bat`（定时锁屏）或 `start-shutdown.bat`（定时关机）。
3. 选择 **10 / 15 / 20 / 25 / 30 / 45 / 60 / 90 分钟**，也可输入自定义的正整数分钟数；默认 **60 分钟**。
4. 确认预计执行时间，点击 **开始计时**。设置窗口中的 **取消** 或关闭按钮会退出设置。

悬浮窗始终显示在桌面顶部，可拖动调整位置，包含操作标识、剩余时间、预计执行时间和进度条。**最后 5 分钟显示红色提醒**，到零后执行一次锁屏或关机。

> 关机会强制关闭应用，请提前保存工作。锁屏后应用继续运行，可使用 Windows 登录方式解锁。

同一 Windows 会话中同时只运行一个计时任务；锁屏、关机和测试模式共用这个限制。重复开始计时会提示已有任务，原任务继续运行。

## 命令行与安全测试

在仓库根目录打开 Windows PowerShell：

```powershell
# 直接开始 45 分钟锁屏倒计时
powershell.exe -NoProfile -STA -File .\src\lock-timer.ps1 -Minutes 45

# 直接开始 60 分钟关机倒计时
powershell.exe -NoProfile -STA -File .\src\shutdown-timer.ps1 -Minutes 60

# 体验 1 分钟倒计时，结束时不会锁屏
powershell.exe -NoProfile -STA -File .\src\lock-timer.ps1 -Minutes 1 -DryRun

# 体验 1 分钟关机倒计时，结束时不会关机
powershell.exe -NoProfile -STA -File .\src\shutdown-timer.ps1 -Minutes 1 -DryRun
```

| 参数 | 作用 |
| --- | --- |
| `-Minutes <正整数>` | 指定分钟数并直接开始；省略时打开设置窗口 |
| `-DryRun` | 体验倒计时，结束时不执行锁屏或关机；可与设置窗口搭配使用 |

首次使用建议先运行 1 分钟测试。两个测试应依次运行。

## 提前停止或调整时间

在任务管理器的“详细信息”中启用“命令行”列，找到命令行同时包含 `countdown.ps1` 和 `-Worker` 的 `powershell.exe`，仅结束这个进程即可取消任务。之后重新打开设置，选择新时长。

电脑睡眠时不会被主动唤醒；恢复运行时若已到点，将继续执行结束流程。注销或重启后任务不会自动恢复。

## 项目结构

```text
screen-time-tools/
├── start-lock.bat              # 双击启动锁屏设置
├── start-shutdown.bat          # 双击启动关机设置
├── src/                       # 程序源码
│   ├── lock-timer.ps1          # 锁屏入口
│   ├── shutdown-timer.ps1      # 关机入口
│   ├── countdown.ps1          # 共用设置、倒计时和到期动作
│   └── ui/                    # WPF 窗口布局
│       ├── duration-picker.xaml
│       └── countdown.xaml
├── scripts/
│   └── check.ps1               # 语法及回归检查入口
├── tests/
│   └── countdown.tests.ps1     # 无额外框架的回归检查
└── docs/
    ├── DEVELOPMENT.md         # 开发说明与 Windows 验证步骤
    └── images/                # README 效果图
```

从旧版更新时，**命令行入口已迁移到 `src/`**；两个根目录 BAT 的启动方式保持一致。请更新指向旧 `.ps1` 路径的快捷方式，并保留 `src/ui/` 中的窗口资源。

开发及验证说明见 [DEVELOPMENT.md](docs/DEVELOPMENT.md)。自动检查命令：

```powershell
powershell.exe -NoProfile -File .\scripts\check.ps1
```
