# Screen Time Tools

Windows 电脑使用时长工具，提供定时关机和定时锁屏，共用一个桌面悬浮倒计时组件。

适用于 Windows 10/11 和系统自带的 Windows PowerShell 5.1，需要在已登录的桌面会话中运行。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `start-shutdown.bat` | 双击启动定时关机，并输入分钟数 |
| `start-lock.bat` | 双击启动定时锁屏，并输入分钟数 |
| `shutdown-timer.ps1` | 关机独立入口，也可从 PowerShell 指定时长 |
| `lock-timer.ps1` | 锁屏独立入口，也可从 PowerShell 指定时长 |
| `countdown.ps1` | 两个入口共用的输入校验、悬浮窗口、计时和到期操作 |

把上述五个文件放在同一个目录中。两个 `.ps1` 入口都需要旁边的 `countdown.ps1`，不要只复制单个入口。BAT 按自身目录寻找脚本，不需要修改固定盘符或工作目录；可右键 BAT 创建桌面快捷方式。

原始文件目录 `originals/` 不提交到仓库，已由 `.gitignore` 排除。

## 日常使用

1. 双击 `start-shutdown.bat`（关机）或 `start-lock.bat`（锁屏）。
2. 在打开的窗口中输入正整数分钟数；直接回车为 **60 分钟**。输入校验由 PowerShell 完成。
3. 确认屏幕顶部出现对应操作的倒计时，启动终端随后即可关闭。

倒计时置顶、顶部居中，高度 40 像素，采用圆角半透明白底，并显示“关机”或“锁屏”操作名称。正常为绿色，剩余时间不超过 5 分钟时变红，窗口宽度随文字扩展。

BAT 在可见窗口中完成时长输入，然后由公共组件创建隐藏的 Windows PowerShell STA 工作进程。工作进程同时负责窗口和到期操作。BAT 启动阶段发生错误时保留错误输出并暂停，关闭提示后返回原错误码；请以倒计时窗口已经出现为启动完成的依据。

## 从 PowerShell 指定时长

在这五个文件所在目录打开 Windows PowerShell：

```powershell
# 60 分钟后关机。
powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1 -Minutes 60

# 45 分钟后锁屏。
powershell.exe -NoProfile -STA -File .\lock-timer.ps1 -Minutes 45

# 不传 Minutes 时询问时长，回车默认 60 分钟。
powershell.exe -NoProfile -STA -File .\lock-timer.ps1
```

只需运行对应入口，不需要单独启动公共组件；`-Worker` 是内部参数，不用于日常启动。

## 先做不会关机或锁屏的测试

```powershell
# 关机模式测试：倒计时到零后退出，不执行关机。
powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1 -Minutes 1 -DryRun

# 等上一个测试结束，再测试锁屏模式；不会真的锁屏。
powershell.exe -NoProfile -STA -File .\lock-timer.ps1 -Minutes 1 -DryRun
```

`-DryRun` 完整运行计时和窗口流程，但跳过实际关机、锁屏操作。可检查窗口操作名称、剩余时间、最后 5 分钟红色显示，以及到零后约 1 秒退出。需要检查绿色到红色的变化，可将时长设为 6 分钟。

## 计时与重复启动规则

- 窗口首次渲染后才开始计时。显示与到期操作共用一个 Stopwatch，根据实际经过时间计算剩余秒数，界面刷新不累积计时误差。
- 剩余秒数取 `Max(0, Ceiling(总秒数 - 已经过秒数))`。显示为零后等待约 1 秒，再执行一次对应操作；测试模式直接结束。
- 同一 Windows 会话中只允许一个任务，关机、锁屏和 DryRun 共用该限制。已经有任务时再次启动会提示，不覆盖旧任务，也不同时创建两个倒计时。
- 本版与仓库之前的合并版 `shutdown-timer.ps1` 共用单实例标识，因此仍在运行的上一版合并脚本也会阻止新任务启动。
- UI 忙碌可能推迟刷新和到期操作。脚本不会唤醒睡眠中的电脑；睡眠或休眠时间计入经过时间，恢复时若已经到点，会显示零并进入结束流程。计时不依赖系统日期，正常高精度计时不受手动调整时钟影响。

## 停止或更换任务

悬浮窗口正常运行时拦截关闭和 Alt+F4。如需提前停止或改时长：

1. 打开任务管理器，进入“详细信息”，在列标题处启用“命令行”列。
2. 找到 `powershell.exe`，确认命令行同时包含 **`countdown.ps1`** 和 **`-Worker`**，并检查 `-Action Shutdown` 或 `-Action Lock` 是否为要停止的任务。
3. 仅结束该工作进程。倒计时和对应操作同时取消，之后可重新启动所需任务。

如果运行的是仓库上一版合并脚本，其工作进程命令行包含 `shutdown-timer.ps1` 和 `-Worker`。不要批量结束其他 PowerShell 进程，也不要只结束已经完成启动的入口进程。

**原始分离版 `shutdownwin.ps1`、`shutdownwin_countdown.ps1` 或旧 `lockscreen.ps1` 不受本版单实例保护，也不会被自动取消。** 首次切换前确认旧任务已结束；不确定时先保存工作并重启，再测试本版。

## 到期行为与运行限制

**关机**保留原稿的 `Stop-Computer -Force` 行为，会强制关闭应用，未保存内容可能丢失。正式使用前先保存工作；权限不足时操作可能失败，脚本不会自动提权。

**锁屏**通过 Windows `LockWorkStation` API 发起锁屏请求，不主动关闭应用。API 成功返回只表示异步请求已经发起，不等于已经确认锁屏完成；需要在当前已登录用户的交互桌面中运行。锁屏是一次性操作，用户仍可用 Windows 登录凭证解锁，不提供持续禁止登录或防止孩子绕过的能力。

结束工作进程会取消任务，注销或重启也不会自动恢复。因此该工具适合家庭使用时长提醒与单次到期操作，不能保证任务不可被结束。

脚本和 BAT 不修改执行策略，不自动提权。若下载来源标记阻止运行，检查代码后可在文件属性中“解除锁定”；如果是组织执行策略阻止运行，应按管理员要求处理。PowerShell 文件使用 UTF-8 BOM 以兼容 Windows PowerShell 5.1 的中文，BAT 使用 ASCII 和 CRLF 换行。

## 验证状态

开发环境为 Linux。**Windows PowerShell 5.1、WPF 窗口、BAT 双击和真实关机/锁屏仍需在 Windows 上验证**，不要把静态检查或模拟计时当作这些项目已经通过。

建议依次完成两个 1 分钟 DryRun，并在其中一个计时期间启动另一入口，确认单实例提示；再确认 Alt+F4 拦截和任务管理器停止流程。之后可测试 1 分钟真实锁屏；真实关机测试请先保存工作。

## Microsoft 参考

- [Windows PowerShell 启动参数与 BAT 相对路径](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)
- [DispatcherTimer 的调度延迟](https://learn.microsoft.com/en-us/dotnet/api/system.windows.threading.dispatchertimer.interval?view=netframework-4.8)
- [Stopwatch](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.stopwatch?view=netframework-4.8)
- [Windows 高精度计时](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)
- [Stop-Computer](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/stop-computer?view=powershell-5.1)
- [LockWorkStation：异步请求与交互桌面要求](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-lockworkstation)
- [DllImport.SetLastError 与 Win32 错误获取](https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.dllimportattribute.setlasterror?view=netframework-4.8.1)
