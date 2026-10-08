# 开发与验证

## 目录职责

- 根目录：README、Git 配置和面向用户的 BAT 启动入口。
- `src/`：PowerShell 程序。锁屏、关机入口只负责传递参数，共用 `countdown.ps1` 的设置、计时和到期动作。
- `src/ui/`：WPF XAML 布局；不包含计时逻辑。
- `scripts/`：维护与检查脚本。
- `tests/`：无需额外测试框架的回归检查。
- `docs/`：开发说明、验证步骤及效果图。

双击入口通过 `%~dp0` 定位 `src/`，程序通过 `$PSScriptRoot` 定位窗口资源，因此不依赖当前工作目录。分发时应保留完整目录结构。

## 编码与运行环境

面向 Windows PowerShell 5.1 的 `.ps1` 使用 **UTF-8 BOM + CRLF**，避免中文在旧版 PowerShell 中被按系统代码页读取。`.bat` 使用 ASCII + CRLF；XAML 使用 UTF-8，由程序显式以 UTF-8 读取。Git 属性负责规范换行。

运行环境为 Windows 10/11 的交互桌面与系统自带的 Windows PowerShell 5.1。启动入口包含 `-STA`，供 WPF 窗口使用。

## 自动检查

在仓库根目录运行：

```powershell
powershell.exe -NoProfile -File .\scripts\check.ps1
```

macOS/Linux 上如已安装 PowerShell 7，可执行：

```sh
pwsh -NoProfile -File ./scripts/check.ps1
```

检查包括 PowerShell 语法、BAT 目标路径、XAML 控件绑定、8 档预设顺序与布局，以及真实显示函数的输入验证、选中状态、倒计时格式和 5 分钟提醒边界。测试使用模拟控件，不会启动计时、锁屏或关机。

PowerShell 7 的检查通过不能替代 Windows PowerShell 5.1 的运行验证，也不能确认 WPF 实际显示效果。

### 本次整理的验证记录（2026-10-08）

- 已在 macOS 静态检查 XAML XML、8 档预设顺序、两行四列布局、默认 60 分钟、控件绑定、资源和 BAT 路径、脚本编码及 README 本地链接。
- 已渲染并检查效果图，Git 差异检查通过。
- 当前环境没有 PowerShell，临时运行时下载失败，`scripts/check.ps1` 的语法与行为检查尚未执行；Windows WPF 显示、锁屏和关机也尚未验证。

## Windows 手工验证

1. 在 Windows PowerShell 5.1 运行上述自动检查。
2. 双击两个 BAT，分别确认设置窗口打开；关闭一个后再打开另一个。
3. 依次选择 10、15、20、25、30、45、60、90 分钟，确认输入框、选中状态和预计执行时间同步；默认选中 60 分钟。
4. 输入自定义的 `37` 分钟，再输入空值、`0`、负数、小数和非数字，确认错误输入无法开始计时。
5. 分别运行以下命令，等待显示 `00:00` 后窗口自动关闭，确认没有锁屏或关机：

   ```powershell
   powershell.exe -NoProfile -STA -File .\src\lock-timer.ps1 -Minutes 1 -DryRun
   powershell.exe -NoProfile -STA -File .\src\shutdown-timer.ps1 -Minutes 1 -DryRun
   ```

6. 在测试计时运行期间尝试再次开始计时，确认提示已有任务，原任务继续。
7. 确认悬浮窗可以拖动，在不同显示缩放比例下文字和按钮没有裁切。

真实锁屏、强制关机需要在保存工作后单独验证。

## 效果图

`images/overview.svg` 与 `images/overview.png` 为按 `src/ui/` 布局、颜色和文案绘制的界面示意，包含设置窗口及常规、最后 5 分钟倒计时。示例时刻是固定展示值，不代表运行状态；字体、阴影和尺寸以 Windows 实际渲染为准。
