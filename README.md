# 悬浮工作台（Floating Workspace）

一个 macOS 菜单栏浮窗工具。Phase 1 提供本地便签、空白面板、图片编辑和 WKWebView 网页模式，不需要 Accessibility 或 Screen Recording 权限。

## 功能与路线图

| 模式 | 状态 |
| --- | --- |
| 便签 | Phase 1 已完成 |
| 空白 | Phase 1 已完成 |
| 图片 | 本地 PNG/JPEG 导入、缩放、滚动查看、裁剪、画笔／文字／箭头标注和 PNG 导出 |
| 网页 | 浏览、本地正文编辑、按 URL 保存与单次重放 |

图片编辑只处理用户主动选择或拖入的本地文件，不访问网络或屏幕内容；网页修改不会写回远程网站。

## 玻璃视觉与辅助功能

- 浅色外观采用 C「浅色渐变玻璃」：`#E0F4FF` → `#EEE4FF` 蓝紫渐变叠加公开系统材质。
- 深色外观采用 B「深色 HUD 玻璃」：以 `#121926` 深蓝黑为背景，强调色为 `#8BD0FF`。
- 应用图标采用「悬浮徽章」：叠放窗口形体搭配小图钉徽章；浅色、深色资源随有效外观切换。菜单栏使用单色模板图，模式入口保留 SF Symbols 与中文标签。
- 系统开启「减少透明度」时隐藏材质与渐变并使用实色背景；开启「增强对比度」时使用可见性更高的边框（浅色为深色描边，深色为浅色描边）。默认读取真实系统外观和辅助功能设置，运行中切换这两项会通过公开的辅助功能通知即时刷新，不轮询，也不修改全局 macOS 偏好。
- 1pt 边框绘制在内容最上层，只描左、右、下三边，下方两角随面板圆角弯曲；顶边交给系统标题栏分隔线，不再叠出第二条线。
- 窗口阴影使用 AppKit 原生 `NSPanel.hasShadow`，不在内容背景 layer 上添加自定义阴影或额外离屏阴影通道。
- 空白模式继续保留用户选择的背景色，不用主题渐变或玻璃材质覆盖；该颜色只由面板绘制一次，alpha 小于 1 时不会被重复叠加。图片和网页入口均可用，从空白切到图片时恢复默认窗口标题与透明背景。

图标矢量生成源码为 `Scripts/generate-icons.swift`。默认的 `Scripts/build-app.sh` 和测试只把资源生成到临时目录，再用 `cmp` 与 `Resources/Assets.xcassets` 逐字节比较，有漂移时报出文件名并失败，不会改写已提交资源。修改生成器后，显式重新生成并打包：

```bash
Scripts/build-app.sh --update
```

也可以只检查或只更新资源：`Scripts/check-icon-resources.sh [--update]`。两个脚本默认使用 `/Applications/Xcode.app/Contents/Developer`，已设置的 `DEVELOPER_DIR` 优先。

## 使用

- 标题栏右侧图钉按钮：显示当前置顶状态（`已置顶`／`未置顶`），点击切换置顶。
- 全局快捷键 `⌃⌥⌘P`：切换当前浮窗的置顶状态。
- 菜单栏 `显示／隐藏浮窗`：隐藏或显示浮窗，不显示 Dock 图标。
- 菜单栏 `切换置顶`：与快捷键、标题栏图钉操作同一个面板；菜单打开时以勾选标记显示当前置顶状态。
- 菜单栏 `退出悬浮工作台`：安全保存并退出；保存失败时可重试或明确放弃未保存内容。

便签内容、当前模式、空白标题与背景色、图片文档、网页草稿、置顶状态会自动保存到默认数据文件：

```text
~/Library/Application Support/FloatingWorkspace/workspace-v1.json
```

窗口位置和尺寸不写入该 JSON，而是由 AppKit frame autosave 保存在 UserDefaults 域 `local.floatingworkspace` 的 `NSWindow Frame FloatingWorkspaceFrame` 键中，移动或缩放后自动保存，下次启动时恢复；已保存的 frame 若标题栏不在任何屏幕可见区域内，则改用居中的默认窗口。

保存失败时，界面会显示失败状态，未保存内容仍保留。退出时若保存仍失败，可重试，或选择 `放弃未保存内容并退出`。启动时遇到损坏的 JSON，原文件会移动到带时间戳的备份，应用以默认内容启动并显示恢复信息。

## 图片模式

- 切换到 `图片`，点击 `导入` 选择本地 PNG/JPEG，或把一个图片文件拖到图片区域。单文件上限为 **50MB**；不支持的扩展名、解码失败和超限都会显示错误，并保留当前文档。
- 导入时原图会复制到工作区 `Images/<uuid>.<ext>`，之后移动或删除用户原文件不影响已导入图片。`替换` 创建新 UUID 文档并保留旧的管理副本；`删除` 只删除当前管理副本和文档，绝不改写或删除用户原文件。旧替换副本会有意保留，不提供自动清理。
- 缩放范围为 **10%–400%**，始终等比显示。放大后可使用图片区域的横向／纵向滚动条查看整张图，再执行裁剪或标注；窗口 resize 会重新计算适配布局。
- `裁剪` 支持拖动、移动和缩放保持原图宽高比的裁剪框，`重置裁剪` 恢复完整图片。裁剪和缩放不会改写原图。
- 画笔、文字和箭头共用当前颜色；文字先填入 `标注文字` 再点击图片位置。`撤销` 只移除最后一次标注，`清空` 移除全部标注。坐标按原图归一化保存，缩放、滚动和裁剪后仍映射到相同原图像素。
- `导出` 通过保存面板生成 PNG，包含当前裁剪和全部标注，输出尺寸为裁剪后的原图像素尺寸，不随显示缩放放大。导出先在内存中完成合成和编码，再原子写入目标；失败会显示原因，保留当前编辑且不以半成品覆盖目标。
- 图片功能不访问网络，不使用截图 API，不要求 Screen Recording 权限，也不支持网络图片、视频或远程图片编辑。

图片验收 fixture 由以下命令生成；PNG/JPEG 都是 16×12，四个 8×6 象限在原图左下坐标系中依次为：左上红、右上绿、左下蓝、右下黄。PNG 像素精确，JPEG 使用最高质量但按有损格式容差检查。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift Tests/Fixtures/images/generate-fixtures.swift
```

## 网页模式

- 在 URL 输入框输入完整的 `http` 或 `https` 地址并打开；后退、前进和刷新操作当前 WKWebView，新窗口链接也在同一网页视图加载。非法地址、凭据地址、网络失败和证书失败会显示错误，不绕过证书校验。
- `编辑正文` 只修改当前页面的本地 DOM，`结束编辑` 恢复只读。停止修改 800ms 后异步保存；结束编辑、导航离开和正常退出前也会尝试保存，避免丢失最后一次输入。保存失败时可见提示；随后一次导航仍然放行，但会显示 `无法保存网页草稿` 且明确告知会丢失未保存的网页修改。网页进程崩溃时丢弃未保存修改并显示 `网页进程已终止，未保存的网页修改已丢失`。
- 草稿按规范化 URL 保存：scheme/host 转小写，移除 fragment、用户名、密码和默认端口，保留其余 path、query 与末尾斜杠。加载完成后只尝试重放一次；重放会把整页 `body` 替换为草稿内容，并检查页面是否还有 `body`。它只识别"正文缺失"这一类结构变化，不检测其他页面结构变化；页面改动后草稿可能不再贴合当前页面，需要重新编辑并再次保存。正文缺失时显示 `无法应用上次修改`，保留草稿，不循环重试。
- 保存和重放都会清理脚本、iframe/object/embed/noscript/noembed/noframes、meta refresh、事件属性、`ping`、`javascript:` 链接、表单提交地址及输入值。普通正文、链接和文本结构保留；编辑及重放后拦截表单 submit。
- 网站数据使用 `WKWebsiteDataStore.nonPersistent()`。Cookie、sessionStorage 和登录状态只存在于当前进程，重启后不会恢复；不保存密码、表单输入值或网站凭据，不承诺持久登录。
- 网页自己的脚本在原始页面中仍按 WebKit 默认行为运行，清理草稿不等于隔离恶意网页；只打开可信来源。网络仅用于用户主动打开的网页及其正常资源，便签和空白模式不发起网络请求。
- 网页编辑不会写回远程网站，不调用网站写入 API，也不主动提交表单。Chromium/Electron、远程写入和持久登录均不在本次完成范围内。

本地验收 fixture 位于 `Tests/Fixtures/web/`。只绑定回环地址启动服务：

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory Tests/Fixtures/web
```

随后打开 `http://127.0.0.1:8765/static.html?case=local`。`dynamic.html` 在同一 case 第二次加载时移除原 body，用于验证可见的重放失败路径；换用新的 query case 可重新执行。

## 构建与运行

要求 macOS 13.0 或更高版本，以及 Xcode Swift 工具链。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/build-app.sh
open dist/FloatingWorkspace.app
```

`xcode-select` 指向 Command Line Tools 时，需按上面显式设置 `DEVELOPER_DIR` 使用 Xcode 工具链运行测试。

构建产物为 `dist/FloatingWorkspace.app`，使用本机 ad-hoc 签名。应用只使用公开 AppKit/Carbon/WebKit/CoreGraphics/ImageIO API，不使用 SkyLight 或其他私有 API，不要求特殊权限。便签、空白和图片模式不发起网络请求；网页模式只加载用户主动打开的网页及其正常资源。

## 测试与验收

原八组功能验收、玻璃视觉验收、网页专项验收和图片专项验收见 [`docs/testing/floating-workspace-phase1-acceptance.md`](docs/testing/floating-workspace-phase1-acceptance.md)。

隔离测试数据时，仅在测试命令前设置完整文件 URL 或 POSIX 路径：

```bash
FLOATING_WORKSPACE_STORE_URL="$PWD/.artifacts/acceptance/workspace-v1.json" \
  dist/FloatingWorkspace.app/Contents/MacOS/FloatingWorkspace
```

`FLOATING_WORKSPACE_STORE_URL` 只隔离 JSON 数据文件，不隔离窗口 frame：所有实例共用 UserDefaults 域 `local.floatingworkspace` 中的 frame。验收前后需记录并恢复该键，步骤见验收文档。

视觉验收可为单独启动的进程设置以下覆盖项；它们只影响该实例，不写入系统设置。这些环境开关会随 release 二进制发布，并非编译期测试专用功能；只应用于隔离验收进程，未设置时始终使用真实系统设置：

```bash
FLOATING_WORKSPACE_APPEARANCE=light \
FLOATING_WORKSPACE_REDUCE_TRANSPARENCY=1 \
FLOATING_WORKSPACE_INCREASE_CONTRAST=1 \
FLOATING_WORKSPACE_STORE_URL="$PWD/.artifacts/acceptance/workspace-v1.json" \
  dist/FloatingWorkspace.app/Contents/MacOS/FloatingWorkspace
```

- `FLOATING_WORKSPACE_APPEARANCE` 仅接受 `light` 或 `dark`；其他值回退到系统外观。
- `FLOATING_WORKSPACE_REDUCE_TRANSPARENCY=1` 强制本进程使用减少透明度回退。
- `FLOATING_WORKSPACE_INCREASE_CONTRAST=1` 强制本进程使用增强对比度边框。
- 不设置这些变量时使用真实系统设置；辅助功能变量只有精确值 `1` 是覆盖，其他值回退到系统设置。

多个单独启动的实例如果使用同一个数据文件，彼此不隔离，后保存的实例会覆盖其他实例的内容；应用不加锁，也不限制为单实例。需要并行运行的隔离验收必须为每个实例使用不同的 `FLOATING_WORKSPACE_STORE_URL`。

保存失败验收固定使用 `FLOATING_WORKSPACE_STORE_URL=/dev/null/workspace-v1.json`。所有本机验收输出和截图只放在 `.artifacts/acceptance/`，不要提交。

## 许可证

MIT License，Copyright (c) 2026 Yintong。详见 [`LICENSE`](LICENSE)。
