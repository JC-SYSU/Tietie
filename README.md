# 贴贴 (Tietie)

**贴贴是一个免费、开源的 macOS 剪贴板管理器。** 按 <kbd>⇧⌘V</kbd>,屏幕底部会升起一排卡片,显示你复制过的所有内容,可以直接搜索、置顶、编辑和粘贴。所有数据留在本机:没有账号、没有云同步、没有遥测。

贴贴基于 [Copy](https://github.com/tarikbc/Copy) 修改。代码遵循 GPL-3.0,名称、图标和品牌已全部替换,与原项目没有关联,也不受原作者支持。

<p align="center">
  <b><a href="https://github.com/JC-SYSU/Tietie/releases/latest">下载</a> &nbsp;·&nbsp; <a href="#install">安装</a> &nbsp;·&nbsp; <a href="#keyboard-shortcuts">快捷键</a></b>
</p>

## 从 Copy 来的用户

贴贴第一次启动时会把 `~/Library/Application Support/Copy/` 和 `~/Library/Copy/Images/` 复制到 `~/Library/Application Support/Tietie/` 和 `~/Library/Tietie/Images/`,并迁移旧版偏好设置。原目录保留不删,确认新版本正常后可以自行清理。

贴贴与上游 Copy 使用不同的 bundle identifier 和存储目录,两个 app 可以同时安装,互不写入对方的数据库。

## 功能

**面板**
- 在任意 app 里按 <kbd>⇧⌘V</kbd> 唤起;每次复制都会变成一张卡片,立刻可以搜索
- 完整历史记录与全文搜索,按 All / 文本 / 图片 / 链接 / 文件筛选
- 端侧 OCR,图片里的文字也能搜到,结果中高亮匹配位置
- 空格预览卡片,文件走 Quick Look
- 把卡片拖出面板,或选中多张一起拖出
- macOS 26 上使用 Liquid Glass,同时提供实色回退,支持"降低透明度"
- 跟随系统外观,也可以固定浅色或深色;面板可以贴边或悬浮
- 切换标签、归档卡片、粘贴等操作可开启触控板触感反馈

**整理**
- 带颜色和 emoji 的置顶板;把卡片拖到标签上即可归档,<kbd>⌘1</kbd>–<kbd>⌘9</kbd> 切换
- 拖动卡片时提示将落入哪个置顶板;拖动标签可以调整顺序
- 收藏把星标卡片放在最前,也可以完全关闭
- 搜索范围可以限定在当前置顶板或全部历史
- 点击卡片标题就地重命名;多选后可批量操作
- 设置、更新和所有操作都能从面板内打开,也可以隐藏菜单栏图标

**编辑与工具**
- 富文本编辑器:粗体、斜体、下划线、删除线,实时统计字符、词数和行数
- 自动识别代码并在卡片上语法高亮
- 复制 `#4C9DFF` 这样的十六进制颜色,卡片直接显示颜色
- 旋转复制来的图片;调整颜色后重新复制
- macOS 15+ 支持 Apple 写作工具

**粘贴**
- <kbd>⏎</kbd> 粘贴选中的卡片;<kbd>⌥⏎</kbd> 去掉格式粘贴纯文本
- 默认单击选中、双击粘贴,也可以改成单击粘贴
- 粘贴队列:排好若干卡片,之后每次 <kbd>⌘V</kbd> 依次粘贴,队列中标注下一条
- <kbd>⌘O</kbd> 直接打开选中的链接或文件;<kbd>⌘Z</kbd> 撤销删除
- 提供 App Intents,快捷指令可以粘贴最新一条、搜索或从置顶板粘贴

**隐私**
- 所有数据留在你的 Mac 上。没有账号、云同步或遥测
- 遵守系统隐藏内容标记,密码管理器复制的内容不会记录
- 按 app 排除,支持在录屏和共享屏幕时隐藏面板
- 可配置历史保留时长;历史可以导出为单个归档并重新导入

## 安装

### 直接下载

从 [Releases](https://github.com/JC-SYSU/Tietie/releases/latest) 下载最新的 DMG,打开后把贴贴拖进"应用程序"。需要 **macOS 26 或更高版本**。

首次启动时,贴贴会请求辅助功能权限(用于替你粘贴),macOS 15.4+ 还会请求剪贴板访问权限。之后随时按 <kbd>⇧⌘V</kbd> 唤起。

Homebrew cask 尚未发布。需要自己构建时见下文。

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| <kbd>⇧⌘V</kbd> | Open the shelf |
| <kbd>←</kbd> / <kbd>→</kbd> | Move selection |
| <kbd>⌘C</kbd> | Copy the selection to the clipboard |
| <kbd>⌘V</kbd> | Paste the selection |
| <kbd>⏎</kbd> | Paste selected card |
| <kbd>⌥⏎</kbd> | Paste as plain text |
| <kbd>Space</kbd> | Preview selected card |
| <kbd>1</kbd>–<kbd>9</kbd> | Quick-paste the Nth card |
| <kbd>⌘1</kbd>–<kbd>⌘9</kbd> | Switch to history / pinboard tab |
| <kbd>⌘E</kbd> | Edit selected card |
| <kbd>⌘R</kbd> | Rename selected card |
| <kbd>⌘O</kbd> | Open selected link or file |
| <kbd>⌘Z</kbd> | Undo the last delete |
| <kbd>⌫</kbd> | Delete selected card (when the search box is empty) |
| <kbd>⌘⌫</kbd> | Clear the search, or delete the selected card |
| <kbd>⌘N</kbd> | New item |
| <kbd>⇧⌘C</kbd> | Toggle the paste stack |

## Build from source

Requirements: macOS 26+, Xcode 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project Tietie.xcodeproj -scheme Tietie -configuration Debug build
```

Core engine tests:

```sh
swift test --package-path TietieCore
```

The app is a thin SwiftUI + AppKit shell over **TietieCore**, a local Swift package
(GRDB / SQLite + FTS5) that holds the clipboard engine, storage, and all the logic that
carries a test suite. UI lives in the app target; behavior lives in TietieCore.

### Release builds

This fork does not ship Sparkle updates. The upstream appcast and EdDSA key have been
removed, so `SUFeedURL` is unset and the app never checks for updates. A release is a
signed and notarized `Tietie.app` packaged as a DMG; `Scripts/dmg_settings.py` has the
dmgbuild layout if you want to build one.

## 隐私

贴贴只在本机运行,唯一的外部请求是为复制来的链接抓取页面标题和图标。这个功能默认开启,可以在设置的历史标签里关闭。除此之外,贴贴不发起网络请求,没有分析或崩溃上报,剪贴板历史不会离开你的 Mac。密码管理器等把剪贴板内容标记为隐藏的 app 会被完全跳过;其他 app 可以逐个加入排除列表。

## 贡献

这是 Copy 的 fork,上游的设计和绝大部分代码来自 [Tarik Caramanico](https://github.com/tarikbc)。贴贴自己的改动、问题和发布在这个仓库里:

- 🐛 [Open an issue](https://github.com/JC-SYSU/Tietie/issues)
- 🔧 Send a pull request. The core engine lives in `TietieCore` and has its own test suite
  (`swift test --package-path TietieCore`); please add or update tests for any engine change

上游的 commit sign-off 规则保留:提交需要 `Signed-off-by` trailer,`git commit -s` 会自动加上。

## License

[GPL-3.0](LICENSE). © 2026 Tarik Caramanico; fork changes © 2026 JC-SYSU.

This is a modified version of Copy. The original copyright notice, [NOTICE](NOTICE)
and the GPL-3.0 grant are preserved. [TRADEMARK.md](TRADEMARK.md) records the upstream
trademark policy: the code is free to fork, the upstream name and artwork are not.
贴贴 ships under its own name, icon, bundle identifier and storage location.
