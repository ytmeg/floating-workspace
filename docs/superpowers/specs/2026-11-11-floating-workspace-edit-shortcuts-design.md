# 悬浮工作台标准编辑快捷键设计

- 日期：2026-11-11
- 状态：用户明确要求优先支持常用编辑快捷键
- 项目：悬浮工作台

## 1. 目标与范围

为便签、空白模式文本框、网页正文和图片标注输入提供一致的 macOS 标准编辑体验，至少支持：

- `⌘C`：复制
- `⌘V`：粘贴
- `⌘X`：剪切
- `⌘A`：全选
- `⌘Z`：撤销
- `⌘⇧Z`：重做

不改变 `⌃⌥⌘P` 的置顶快捷键、现有内容模型、持久化或网页正文编辑逻辑。

## 2. 实现方案

新增 `EditMenuController`，创建标准「编辑」主菜单并设置 `NSApp.mainMenu`。菜单项使用 AppKit 标准选择器：

- `copy:`、`paste:`、`cut:`、`selectAll:`、`undo:`、`redo:`。

菜单项 target 为 `nil`，让 `NSApp.sendAction` 沿 responder chain 交给当前可编辑控件。使用现有 `NSTextView`、`NSTextField`、`WKWebView` 的复制/粘贴/撤销能力，不自行读写剪贴板或拦截按键。

`AppDelegate.applicationDidFinishLaunching` 在窗口与编辑器创建后安装菜单。没有可编辑焦点时，由系统保持相应菜单项的可用状态。

## 3. 验证

### 自动化测试

- 菜单标题、选择器、快捷键和 target 符合规范。
- `NSApp.sendAction` 能到达当前编辑控件的 copy/paste/cut/selectAll/undo/redo。
- 真实 `NSTextView` 完成全选、复制、粘贴、剪切、撤销和重做。
- 保留原有全部测试。

### 真机验收

- 便签中全选、复制、粘贴、剪切、撤销和重做。
- 空白标题和图片标注输入中复制粘贴。
- 网页正文中复制粘贴。
- `⌃⌥⌘P` 置顶切换和其他模式行为不回归。

## 4. 完成标准

只有标准菜单、快捷键映射、真实编辑测试和原功能回归全部通过，才可声明编辑快捷键完成。GitHub 发布在该功能完成后继续进行。
