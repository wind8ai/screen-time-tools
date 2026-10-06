# Screen Time Tools

电脑使用时长控制工具，当前提供 Windows 定时关机，后续计划加入定时锁屏。

定时关机功能整合为一个 `shutdown-timer.ps1`，包含输入分钟数、悬浮倒计时和到期关机。

## 使用

在脚本所在目录打开 Windows PowerShell：

```powershell
# 先测试 1 分钟：到零后停留约 1 秒并退出，不会关机。
powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1 -Minutes 1 -DryRun

# 正式使用：输入分钟数，回车默认 60 分钟。
powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1

# 直接指定 60 分钟。
powershell.exe -NoProfile -STA -File .\shutdown-timer.ps1 -Minutes 60
```

需要 Windows 10/11、Windows PowerShell 5.1。启动器运行本文件的隐藏 STA 子进程；该子进程同时负责窗口和关机，启动终端可以关闭。请确认顶部窗口已出现，创建进程成功不代表其脚本已运行成功。

保留顶部居中、圆角半透明白底、置顶、最后 5 分钟变红。窗口宽度随文本扩展；使用 UTF-8 BOM 保存以兼容 Windows PowerShell 5.1 的中文。

## 原代码问题

| 问题 | 影响 | 修复 |
| --- | --- | --- |
| 显示与后台各自计时 | 启动时间和时间基准不同 | 一个工作进程同时处理显示和关机 |
| WPF 每个 Tick 才减 1 秒 | UI 延迟累积，显示可能落后于后台 | Stopwatch 计算实际经过时间，Tick 仅刷新 |
| 初始化 `$totalSeconds`，事件修改 `$global:totalSeconds` | `-File` 下作用域不同，可能从空全局变量开始减，显示停在初始值等 | 明确的 `$script:timerState` 状态对象 |
| Closing 无条件取消 | 到零后的程序 Close 也被拦截 | 正常禁止关闭，结束或报错时允许关闭 |
| UI 线程 Start-Sleep | 阻塞刷新，零秒未必能画出来 | 到零后用另一定时器等待约 1 秒 |
| 重复启动 | 旧后台任务可能比新窗口更早到期 | 本版本在同一 Windows 会话内只允许一个实例 |
| 输入直接嵌入 CMD | 非法输入可能执行其他命令或出错 | PowerShell 校验正整数 |

“显示还没到零就关机”与 UI 刷新延迟、后台独立到期的组合相符；作用域错误或旧后台任务也可能导致相似现象。缺少运行日志，不能确定具体一次运行属于哪种。

## 合并版规则

- 窗口首次渲染后开始计时，共用一个 Stopwatch。
- 剩余秒数为 `Max(0, Ceiling(总秒数 - 已经过秒数))`，只在该值为零时进入关机阶段。
- 到零后留出约 1 秒让界面显示 00:00，再调用 `Stop-Computer -Force`；正常情况下本脚本不会在倒计时为零前发起关机。
- UI 忙碌仍可能推迟显示和关机，这不是系统级定时服务。
- Windows 高精度计时包含睡眠/休眠时间。脚本不会唤醒电脑；睡眠期间到点，恢复运行后会显示零并进入结束流程。
- 使用实际经过时间，不用系统日期计算；正常高精度计时不受修改系统时间影响。

## 注意

保留原稿的强制关机行为，未保存内容可能丢失。普通关闭/Alt+F4 被拦截，但任务管理器仍可结束进程；不能保证绝对不可关闭。结束新版工作进程也会停止计时，没有独立后台关机任务。

**单实例保护不能识别或取消旧版已经启动的 `shutdownwin.ps1`。首次切换前确认旧任务已结束；不确定时保存工作并重启后测试新版。**

需要停止新版时，在任务管理器“详细信息”显示“命令行”列，仅结束命令行同时含 `shutdown-timer.ps1` 和 `-Worker` 的 powershell.exe，不要批量结束其他 PowerShell。

关机权限不足时会显示错误。脚本不自动提权、不改执行策略；文件被下载来源标记阻止时，检查代码后可在文件属性中解除锁定。组织策略需遵循管理员设置。

## 验证

已静态检查脚本、解析 XAML，并模拟 UI 延迟、到零边界及大整数计算。环境为 Linux，无 Windows PowerShell/WPF，**未进行 Windows 上的 PowerShell 语法解析、窗口运行或真实关机测试**。

建议先做 1 分钟 DryRun，验证到零退出、重复启动提示、Alt+F4 拦截和最后 5 分钟红色显示；保存工作后再验证真实关机。

## Microsoft 参考

- [DispatcherTimer 的调度延迟](https://learn.microsoft.com/en-us/dotnet/api/system.windows.threading.dispatchertimer.interval?view=netframework-4.8)
- [PowerShell 作用域](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes)
- [Stopwatch](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.stopwatch?view=netframework-4.8)
- [Windows 高精度计时](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)
- [Stop-Computer](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/stop-computer?view=powershell-5.1)
