# 悬浮工作台（Floating Workspace）

一个 macOS 菜单栏浮窗工具。Phase 1 提供本地便签与空白面板，不需要 Accessibility 或 Screen Recording 权限。

## 功能与路线图

| 模式 | 状态 |
| --- | --- |
| 便签 | Phase 1 已完成 |
| 空白 | Phase 1 已完成 |
| 图片 | 后续路线图，Phase 1 未实现 |
| 网页 | 后续路线图，Phase 1 未实现 |

Phase 1 不包含图片编辑、网页正文编辑、网页编辑回放或网络功能。

## 使用

- 全局快捷键 `⌃⌥⌘P`：切换当前浮窗的置顶状态。
- 菜单栏 `显示／隐藏浮窗`：隐藏或显示浮窗，不显示 Dock 图标。
- 菜单栏 `切换置顶`：与快捷键操作同一个面板。
- 菜单栏 `退出悬浮工作台`：安全保存并退出；保存失败时可重试或明确放弃未保存内容。

便签内容、当前模式、窗口位置和尺寸、置顶状态会自动保存。窗口 frame 在移动或缩放后自动保存，并在下次启动时恢复。

默认数据文件：

```text
~/Library/Application Support/FloatingWorkspace/workspace-v1.json
```

保存失败时，界面会显示失败状态，未保存内容仍保留。退出时若保存仍失败，可重试，或选择 `放弃未保存内容并退出`。启动时遇到损坏的 JSON，原文件会移动到带时间戳的备份，应用以默认内容启动并显示恢复信息。

## 构建与运行

要求 macOS 13.0 或更高版本，以及 Xcode Swift 工具链。

```bash
xcrun swift test
Scripts/build-app.sh
open dist/FloatingWorkspace.app
```

构建产物为 `dist/FloatingWorkspace.app`，使用本机 ad-hoc 签名。应用只使用公开 AppKit/Carbon API，不使用 SkyLight 或其他私有 API，不要求特殊权限，Phase 1 不发起网络请求。

## 测试与验收

完整八组验收步骤见 [`docs/testing/floating-workspace-phase1-acceptance.md`](docs/testing/floating-workspace-phase1-acceptance.md)。

隔离测试数据时，仅在测试命令前设置完整文件 URL 或 POSIX 路径：

```bash
FLOATING_WORKSPACE_STORE_URL="$PWD/.artifacts/acceptance/workspace-v1.json" \
  dist/FloatingWorkspace.app/Contents/MacOS/FloatingWorkspace
```

保存失败验收固定使用 `FLOATING_WORKSPACE_STORE_URL=/dev/null/workspace-v1.json`。所有本机验收输出和截图只放在 `.artifacts/acceptance/`，不要提交。

## 许可证

MIT License，Copyright (c) 2026 Yintong。详见 [`LICENSE`](LICENSE)。
