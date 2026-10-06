# Screen Time Tools

为 Windows 设置一次定时锁屏或关机，用悬浮倒计时提醒剩余使用时间。

需要 Windows 10/11 和系统自带的 Windows PowerShell 5.1，在已登录的桌面中使用。

## 快速开始

1. 双击 `start-lock.bat` 打开**定时锁屏**，或双击 `start-shutdown.bat` 打开**定时关机**。
2. 选择 **15 / 30 / 60 / 90 分钟**，也可输入自定义的正整数分钟数；默认 **60 分钟**。
3. 确认窗口中的预计执行时间，点击**开始计时**。点击**取消**可退出设置。

计时开始后，屏幕顶部显示浅色圆角悬浮窗，包含操作标识、大号剩余时间、预计执行时间和进度条。可以拖动悬浮窗调整位置；最后 5 分钟变为红色提醒。到零后，执行所选操作。

同一 Windows 会话中同时只运行一个任务，锁屏、关机和测试模式共用这个限制。重复启动会提示已有任务，原任务继续运行。

## 文件放置

将以下五个文件保存在同一文件夹中，即可通过两个 BAT 启动；也可为 BAT 创建桌面快捷方式。

| 文件 | 用途 |
| --- | --- |
| `start-lock.bat` | 双击打开定时锁屏 |
| `start-shutdown.bat` | 双击打开定时关机 |
| `lock-timer.ps1` | 锁屏入口 |
| `shutdown-timer.ps1` | 关机入口 |
| `countdown.ps1` | 共用的设置窗口和倒计时组件 |

## 命令行与测试

在文件所在目录打开 Windows PowerShell：

```powershell
# 直接开始 45 分钟锁屏倒计时。
powershell.exe -NoProfile -STA -File .\lock-timer.ps1 -Minutes 45

# 直接开始 60 分钟关机倒计时。
powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1 -Minutes 60

# 体验 1 分钟倒计时，结束时不会锁屏。
powershell.exe -NoProfile -STA -File .\lock-timer.ps1 -Minutes 1 -DryRun

# 关机模式也支持同样的安全测试。
powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1 -Minutes 1 -DryRun
```

| 参数 | 作用 |
| --- | --- |
| `-Minutes <正整数>` | 指定时长并直接开始；省略时打开设置窗口 |
| `-DryRun` | 体验完整倒计时，结束时不执行关机或锁屏 |

首次使用时，可先运行 1 分钟测试，查看启动和倒计时效果。两个测试需依次运行。仅传 `-DryRun` 时，也可以在设置窗口中选择测试时长。

## 提前停止或调整时间

在任务管理器的“详细信息”中启用“命令行”列，找到命令行同时包含 `countdown.ps1` 和 `-Worker` 的 `powershell.exe`，仅结束这个进程即可取消任务。随后可重新打开设置，选择新的时长。

## 使用提醒

- **关机会强制关闭应用，请提前保存工作。**
- **锁屏为一次性操作**，应用保持运行；之后仍可使用 Windows 登录凭证解锁。
- 电脑睡眠时不会被主动唤醒；恢复运行时若已到点，将继续执行结束流程。注销或重启后任务不会自动恢复。
