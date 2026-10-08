# 开发与验证

[English](DEVELOPMENT.md) | [简体中文](DEVELOPMENT.zh-CN.md) · [使用说明](../README.zh-CN.md)

## 目录职责

- 根目录：双语 README、Git 配置和两个面向用户的 BAT 启动入口。
- `config/`：默认界面语言，详见双语[配置说明](CONFIGURATION.zh-CN.md)。
- `src/`：PowerShell 入口、共用倒计时逻辑与语言函数。
- `src/locales/`：键名及格式占位符一致的 `en-US.psd1` 和 `zh-CN.psd1` 文案字典。
- `src/ui/`：不写死语言的 WPF XAML 布局，不包含计时逻辑。
- `scripts/` 与 `tests/`：不依赖额外框架的 PowerShell 语法与回归检查。
- `docs/`：互相链接的中英文开发、配置说明与效果图。

BAT 通过 `%~dp0` 定位 `src/`，脚本通过 `$PSScriptRoot` 定位窗口、语言资源和配置，因此不依赖当前工作目录。分发时请保留完整目录结构。

## 编码与运行环境

`.ps1` 和 `.psd1` 使用 **UTF-8 BOM + CRLF**，兼容 Windows PowerShell 5.1 的中文读取。BAT 使用 ASCII + CRLF。JSON 和 XAML 使用 UTF-8，由脚本显式按 UTF-8 读取。Git 属性规范仓库换行，并在检出时恢复 Windows 文件的换行。

程序面向 Windows 10/11 的交互桌面与系统自带的 Windows PowerShell 5.1。启动入口包含 `-STA`。语言资源和测试仅使用 PowerShell 内置能力，不依赖翻译服务或额外运行时。

## 语言资源

面向用户的文案需要同时加入两套语言字典，保持键名与格式占位符一致，再通过 `Get-ScreenTimeText` 读取。代码标识符保持稳定的英文名称，关键实现注释提供中英文说明。

`Resolve-ScreenTimeLanguage` 负责命令行、配置与系统语言的选择规则。`Update-SetupLanguage` 刷新设置文案和输入校验。设置窗口选中的语言会显式传入计时进程。`Update-CountdownLanguage` 只刷新倒计时文字，不重置秒表、预计执行时间或时长。

设置窗口的下拉框与倒计时右键菜单均提供语言切换。选项固定使用 `中文`、`English`，方便两种语言的用户识别。

## 自动检查

在仓库根目录运行：

```powershell
powershell.exe -NoProfile -File .\scripts\check.ps1 -Language en-US
powershell.exe -NoProfile -File .\scripts\check.ps1 -Language zh-CN
```

macOS/Linux 上如已安装 PowerShell 7：

```sh
pwsh -NoProfile -File ./scripts/check.ps1 -Language zh-CN
```

检查范围包括语法、BAT 路径、XAML 控件、8 档预设、输入校验、倒计时格式、5 分钟提醒边界、翻译键与占位符一致性、命令行/配置/系统语言优先级，以及两种动作和测试模式的双语文案。测试使用模拟控件，不启动计时或调用原生动作。

### 本次验证记录（2026-10-08）

已在 macOS 使用 PowerShell 7.5.4 通过中英文检查，并检查语言资源、XAML、启动路径、文件编码、文档链接和两种语言效果图。Windows PowerShell 5.1、WPF 实际显示与真实锁屏/关机仍需要在 Windows 验证；PowerShell 7 检查不能确认这些结果。

## Windows 手工验证

1. 在 Windows PowerShell 5.1 中分别运行中英文自动检查。
2. 依次打开两个 BAT，确认设置下拉框切换全部文案、无障碍标签、错误提示和预计时间，输入框与所选时长保持原值。
3. 在配置中分别使用 `auto`、`zh-CN`、`en-US`。确认命令行覆盖配置，显式 `-Language auto` 跟随系统。
4. 点击 10、15、20、25、30、45、60、90 各档；默认选中 60。确认自定义 `37` 有效，空值、零、负数、小数和文字无法开始计时。
5. **依次运行**下面两个测试，确认语言正确传入倒计时，右键切换不改变预计时间与计时进度，显示 `00:00` 后自动关闭，且没有执行原生动作：

   ```powershell
   powershell.exe -NoProfile -STA -File .\src\lock-timer.ps1 -Minutes 1 -DryRun -Language en-US
   powershell.exe -NoProfile -STA -File .\src\shutdown-timer.ps1 -Minutes 1 -DryRun -Language zh-CN
   ```

6. 在测试运行时再次开始计时，确认重复任务提示使用当前语言，原任务继续。
7. 在两种语言、不同显示缩放比例下检查拖动与文字裁切。使用包含空格、中文的文件路径，并从其他工作目录启动，确认资源可正常读取。

真实锁屏和强制关机需在保存工作后单独验证。

## 效果图

`images/overview.svg` / `.png` 为中文，`images/overview.en.svg` / `.png` 为英文。效果图根据实际 XAML、配色与语言资源绘制；时间为固定示例，Windows 控件、字体、阴影和尺寸可能有所不同。
