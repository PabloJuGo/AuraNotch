<div align="center">

<img src="Docs/images/icon.png" width="112" alt="Aura Notch 图标">

# Aura Notch

**把 MacBook 的刘海变成实用又安静的小面板。**
正在播放控制、临时文件暂存架、即将到来的日程、计时器、音量、电池和剪贴板历史，指针一悬停即可使用。

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [简体中文](README.zh-CN.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![License MIT](https://img.shields.io/badge/license-MIT-blue)
![Status beta](https://img.shields.io/badge/status-beta-yellow)

<img src="Docs/images/closed.png" width="420" alt="播放音乐时收起的刘海">

</div>

Aura Notch 是一款使用 Swift（SwiftUI + AppKit）编写的原生 macOS App，没有任何第三方依赖。它静静待在刘海处，不打扰你，指针指向它时便展开为面板。一切都在本地运行：无需账户，无分析，无遥测。

<div align="center">
<img src="Docs/images/home.png" width="720" alt="主页面板，包含正在播放、今天、剪贴板和暂存架">
</div>

## 功能

- **带实时动态的收起刘海。** 播放内容时，刘海旁会出现动态均衡器和曲目标题；计时器会显示倒计时；简短的提醒（即将开始的会议、充电器已连接、计时器已结束）会滑入显示。收起状态的宽度固定且左右对称，不会随歌名变长，尽可能少地遮挡菜单栏。
- **主页。** 今天的日期和电池、带封面和播放控制的正在播放、今天的日程、最近的剪贴板内容和你的暂存架，一目了然。
- **媒体。** 音乐和 Spotify：标题、艺人、进度与拖移定位，以及 macOS 风格的播放/暂停/下一首/上一首。在收起的刘海上用双指滑动即可切歌。Spotify 封面为可选项，也是这款 App 唯一会下载的内容。
- **暂存架。** 将文件或链接拖向刘海，它会展开来接住。暂存架只保存引用，绝不移动或删除你的原始文件。可以打开、在访达中显示、拷贝路径、共享或通过 AirDrop 发送，也可以把项目拖出来。跨会话保留为可选项，需自行开启。
- **日历。** 即将到来的日程，只读，通过 EventKit 并在明确授权后读取。
- **小组件。** 计时器、音量、电池、日期和快捷操作，整齐排列在两列网格中。
- **剪贴板历史（可选）。** 文本、链接和图像，仅保存在内存中。会忽略被标记为隐藏或临时的内容（例如密码管理器），并且在你启用之前默认关闭。
- **主题和语言。** 可选择强调色和收起刘海的大小。界面支持英语、西班牙语、法语、德语、巴西葡萄牙语和简体中文。
- **好公民。** 非激活面板，绝不抢占焦点；全局快捷键（`⌃⌥N`）、菜单栏图标、登录时打开，遵循“减弱动态效果”，在全屏 App 上方自动隐藏（可配置），空闲时 CPU 占用约为 0%。
- **没有刘海也能用。** 在没有刘海的 Mac 和显示器上，它会变成屏幕顶部居中的一个小型浮动胶囊。

<div align="center">
<img src="Docs/images/media.png" width="360" alt="媒体面板"> <img src="Docs/images/clipboard.png" width="360" alt="剪贴板面板">
</div>

## 安装

1. 从[最新版本](https://github.com/PabloJuGo/AuraNotch/releases/latest)下载 `AuraNotch.zip` 并解压。
2. 将 **AuraNotch.app** 拖到“应用程序”文件夹。
3. 首次打开时，**右键点按 > 打开**，然后确认。该 App 使用临时（ad-hoc）签名但未经过公证（公证需要付费的 Apple 开发者账户），因此 macOS 会要求你批准一次。如果 macOS 仍然拒绝，请运行：
   ```sh
   xattr -dr com.apple.quarantine /Applications/AuraNotch.app
   ```
4. 在屏幕顶部找到刘海条（以及菜单栏中的图标）。悬停或点按它，或按下 `⌃⌥N`。

**系统要求：** macOS 14 或更高版本。开发和测试均在运行 macOS 27 的带刘海 MacBook 上完成；其他配置应该也能使用，但测试较少。

## 设置

从面板标题栏中的齿轮或菜单栏图标打开**设置**。

| 分区 | 可更改的内容 |
|---|---|
| 通用 | 登录时打开、显示器模式、**界面语言**、强调色、收起刘海的大小 |
| 交互 | 悬停时打开、点按时打开或使用全局快捷键打开；悬停延迟；全屏行为；收起刘海中的标题；滑动切歌；提醒 |
| 动画 | 动效（跟随系统、减弱或无） |
| 模块 | 启用、停用主页、媒体、暂存架、日历、小组件和剪贴板，并调整其顺序 |
| 隐私 | 在会话之间保留暂存架、历史记录上限、Spotify 封面、删除所有数据 |

更改语言后需要重新启动才会生效；App 提供**立即重新启动**按钮。

## 隐私与权限

- 无账户，无分析，无遥测，无更新检查。
- **网络：** 唯一的请求是 Spotify 封面图片，地址由 Spotify 自身提供。你可以在“设置 → 隐私”中将其关闭。
- **仅在你使用相应功能时才会请求权限：**“自动化”用于控制音乐和 Spotify（查看正在播放的内容无需权限），“日历”用于列出你的日程（只读）。
- 暂存架只保留文件的引用，剪贴板历史仅存在于内存中，**“设置 → 隐私 → 删除所有数据”**会清除一切。

更多详情见 [PRIVACY.md](PRIVACY.md) 和 [SECURITY.md](SECURITY.md)（目前均为西班牙语）。

## 从源码构建

只需 Swift 6 工具链（安装 Xcode 命令行工具即可）。

```sh
git clone https://github.com/PabloJuGo/AuraNotch.git
cd AuraNotch
swift build
swift run AuraSelfTests            # test suite with detailed failures
swift run AuraNotch                # run without packaging (no Calendar/Automation prompts)
Scripts/package-app.sh             # builds dist/AuraNotch.app (release, ad-hoc signed)
```

常用参数：`--skip-onboarding`、`--start-module=<home|media|shelf|calendar|widgets|clipboard>`。

架构说明见 [ARCHITECTURE.md](ARCHITECTURE.md)，设计决策见 [Docs/decisions](Docs/decisions)（西班牙语）。

## 状态与已知限制

Aura Notch 目前是**测试版**。需要了解的事项：

- 未经过公证（见“安装”）。没有自动更新。
- 日历和 AirDrop 流程依赖系统权限和对话框，在真实硬件上的测试有限。
- 外接显示器、多显示器和旁白（VoiceOver）的实际测试较少。
- 在较新的 macOS 版本上，Spotify 的“自动化”权限提示可能出现得较慢；此时 macOS 会在你第一次点按控制按钮时询问。
- 除英语和西班牙语外，其他语言的翻译借助机器完成，尚未经过母语人士审校。非常欢迎提出修正。
- 部分项目文档（架构说明、决策、隐私）仍为西班牙语。

## 参与贡献

欢迎提交 issue 和 pull request；请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。如需修正或新增翻译，请编辑 `Resources/<language>.lproj/Localizable.strings` 并运行 `Scripts/check-localizations.py`。

## 许可

[MIT](LICENSE)。Aura Notch 是一个独立项目，与 Apple、Spotify 或此处提到的任何其他 App 均无关联。
