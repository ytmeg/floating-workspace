# Floating Workspace Phase 1 验收

本规程只验收 `dist/FloatingWorkspace.app` 的最终 release 构建。便签、空白和网页属于本次范围；图片仍禁用。任何一组失败都阻止 Phase 1 + glass visual refresh + web mode 完成声明。

## 准备与证据边界

1. 使用已解锁、位于当前控制台的 macOS 图形会话。不要用锁定屏幕下的输入或不可见窗口结果判定产品通过或失败。
2. 运行自动化检查并打包：

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release --product FloatingWorkspace
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/build-app.sh
   codesign --verify --verbose=2 dist/FloatingWorkspace.app
   git diff --check
   open dist/FloatingWorkspace.app
   ```

3. 除默认启动冒烟外，每个用例设置独立的 `FLOATING_WORKSPACE_STORE_URL`，避免改写真实工作区。完整文件 URL 和 POSIX 路径均可。同时运行的实例不得共用同一数据文件，否则会互相覆盖。
4. 视觉验收可用 `FLOATING_WORKSPACE_APPEARANCE=light|dark`、`FLOATING_WORKSPACE_REDUCE_TRANSPARENCY=1` 和 `FLOATING_WORKSPACE_INCREASE_CONTRAST=1` 覆盖单个验收进程。未设置或值无效时回退到真实系统设置；不得为验收修改全局 macOS 外观或辅助功能偏好。
5. `FLOATING_WORKSPACE_STORE_URL` 不隔离窗口 frame。frame 保存在 UserDefaults 域 `local.floatingworkspace`，验收会改写它。任何验收实例启动前先记录原值（包括不存在的情况）：

   ```bash
   RUN="$PWD/.artifacts/acceptance/<run>"
   mkdir -p "$RUN"
   FRAME_KEY="NSWindow Frame FloatingWorkspaceFrame"
   if defaults read local.floatingworkspace "$FRAME_KEY" > "$RUN/frame-before.txt" 2>/dev/null; then
     echo present > "$RUN/frame-before.state"
   else
     echo absent > "$RUN/frame-before.state"
   fi
   ```
6. 日期化终端输出、辅助脚本和截图仅保存到 `.artifacts/acceptance/`。截图不是必选项；不得为取证授予 Screen Recording 权限。
7. 操作真实窗口时，等待目标应用确实成为 frontmost、目标 alert 确实出现，再发送输入或记录结果。不要把 `activate` 调用返回当成 frontmost 已成立。
8. 八组全程确认：没有 Accessibility 或 Screen Recording 权限提示，没有 SkyLight/私有 API 依赖。第 1–9 组的便签／空白实例不得发起网络请求；第 10 组只允许用户主动打开的回环地址网页及其正常资源。可用 `lsof -nP -a -p <pid> -i` 和交互期间的网络进程采样分别核对，不能用网页组的回环连接掩盖其他组的意外联网。
9. 每个用例结束后通过菜单正常退出；保存失败用例使用明确的放弃退出按钮。清理自己启动的 Safari、Notes 和 IDE，但不修改其中已有内容。
10. 全部实例退出后恢复 frame，并核对结果与记录一致：

   ```bash
   if [[ "$(cat "$RUN/frame-before.state")" == present ]]; then
     defaults write local.floatingworkspace "$FRAME_KEY" -string "$(cat "$RUN/frame-before.txt")"
     test "$(defaults read local.floatingworkspace "$FRAME_KEY")" = "$(cat "$RUN/frame-before.txt")"
   else
     defaults delete local.floatingworkspace "$FRAME_KEY" 2>/dev/null || true
     ! defaults read local.floatingworkspace "$FRAME_KEY" 2>/dev/null
   fi
   ```

以下命令中的 `$APP` 均指：

```bash
APP="$PWD/dist/FloatingWorkspace.app/Contents/MacOS/FloatingWorkspace"
```

## 1. 便签置顶、可见性与焦点

1. 用隔离数据文件启动最终 app，在便签中输入两行可识别文本，等待自动保存。
2. 确认浮窗初始为 `.floating` 对应层级。依次启动并激活 Safari（空白页）、Notes 和 IDE；每次等待该应用确实 frontmost。
3. 在每个应用 frontmost 时，确认便签文本仍显示在浮窗中，浮窗位于该应用窗口之上，且切换后焦点属于 Safari、Notes 或 IDE，而不是浮窗。
4. 再激活各应用一次，确认显示浮窗和操作其他应用不会无预期地偷走焦点。

通过标准：三种目标应用下，已编辑便签保持可见且置顶；应用切换没有非预期焦点窃取。

## 2. 快捷键、标题栏图钉与菜单切换同一面板

1. 保持第 1 组的同一实例和同一个面板。分别让 Safari、Notes 和 IDE frontmost，等待真实 frontmost 条件后按 `⌃⌥⌘P`。
2. 每次按键后确认该面板在 `.floating` 与 `.normal` 间切换，隔离 JSON 中 `isPinned` 同步改变。取消置顶后重新激活目标应用，面板应处于普通层级；再次按键恢复置顶。
3. 使用菜单栏 `切换置顶` 再执行往返切换，确认窗口层级与 `isPinned` 跟随同一面板变化。每次打开菜单时，`切换置顶` 的勾选状态与当前 `isPinned` 一致。
4. 点击浮窗标题栏右侧图钉按钮执行往返切换。确认按钮标题在 `已置顶` 与 `未置顶` 间变化，窗口层级与 `isPinned` 同步；再用快捷键或菜单切换一次，确认图钉按钮状态随之刷新。

通过标准：快捷键、标题栏图钉和菜单操作同一实例、同一面板；三种入口都能完成 `.floating` → `.normal` → `.floating`，标题栏和菜单显示的置顶状态始终与 `isPinned` 一致。

## 3. 空白模式即时生效与持久化

1. 在同一最终 app 实例切换到 `空白`，输入可识别标题，修改背景颜色、宽度和高度，并确认各字段的实际提交动作。输入小于最小值的宽度时，字段回写为实际宽度 `360`；拖动缩放窗口后，宽高字段同步为当前 frame。
2. 每次修改后立即检查窗口标题/背景/frame 和保存状态，不等待重启才判定即时生效。
3. 通过菜单安全退出并重启同一隔离数据文件，确认空白标题、背景颜色、宽度和高度全部恢复。

通过标准：四项空白配置立即应用，并在 relaunch 后保持一致。

## 4. 便签、模式、frame 与置顶状态持久化

1. 使用同一隔离数据文件，编辑便签文本，选择目标模式，移动并缩放窗口，切换一次置顶状态。
2. 等自动保存完成后，通过菜单安全退出，再启动最终 app。
3. 对照退出前的 JSON、`defaults read local.floatingworkspace "NSWindow Frame FloatingWorkspaceFrame"` 和窗口记录，检查便签文本、`selectedMode`、frame 与 `isPinned`。frame 不在 JSON 中。

通过标准：便签内容、所选模式、窗口 frame、置顶状态均跨 relaunch 恢复。

## 5. 菜单栏隐藏/显示与无 Dock 图标

1. 在最终 app 运行中，从真实菜单栏选择 `显示／隐藏浮窗`，等待面板从 on-screen 窗口列表消失。
2. 再次选择同一菜单项，等待原面板重新出现，内容和模式不变。
3. 检查 app 的 activation policy 为 accessory，并确认 Dock 中没有悬浮工作台图标。

通过标准：菜单栏可完成 hide/show 往返，全程没有 Dock 图标。

## 6. 重复热键与第二实例

1. 同一进程内的确定性 Carbon 检查：先注册一次 `P` + `control/option/command`，再用相同参数重复注册。第二次必须返回数值 `eventHotKeyExistsErr`，即 `-9878`；注销第一个引用并退出 probe。运行 `HotkeyControllerTests` 确认应用的数值错误路径。
2. 保持第一个最终 app 实例运行，确认它的菜单操作仍可使用。
3. 用另一个隔离数据文件直接启动第二个最终 app 实例。当前 macOS 允许跨进程重复注册，因此**不要求**跨进程冲突 alert，也不能把缺少 alert 判为失败。
4. 只操作第二实例的真实菜单栏 `切换置顶` 和 `显示／隐藏浮窗`，确认其自身面板和 JSON 改变，再用 `退出悬浮工作台` 退出第二实例。

通过标准：同进程重复注册返回 `-9878`；两个实例都被允许，第二实例菜单可用；第一实例不被第二实例退出影响。

## 7. 可见保存失败、重试与明确放弃退出

1. 精确使用以下隔离失败路径启动最终 app：

   ```bash
   FLOATING_WORKSPACE_STORE_URL=/dev/null/workspace-v1.json "$APP"
   ```

2. 修改便签并等待真实 `保存失败` 状态可见。
3. 从真实菜单选择 `退出悬浮工作台`，等待 `退出前保存失败` alert，确认存在 `重试` 与 `放弃未保存内容并退出`。
4. 点击 `重试`，等待保存再次失败及同一 alert 再次出现，确认未保存内容没有伪装成已保存。
5. 点击 `放弃未保存内容并退出`，确认进程退出；这是用户明确丢弃本次未保存内容的终止路径。

通过标准：失败状态与 alert 可见；重试确实再次尝试；只有明确放弃后才退出。

## 8. 损坏 JSON 隔离备份与恢复提示

1. 在 `.artifacts/acceptance/` 新建独立目录，向其中 `workspace-v1.json` 写入可识别的非 JSON 字节。
2. 用该路径作为 `FLOATING_WORKSPACE_STORE_URL` 启动最终 app，等待恢复 alert 真实出现。
3. 确认 alert 说明当前使用默认内容并显示保留备份路径；关闭 alert 后默认工作区可用。
4. 确认原路径已不存在，同目录出现 `workspace-v1.corrupt-<timestamp>.json`，备份字节与启动前完全相同。

通过标准：损坏文件被移动而非覆盖，时间戳备份保留原始字节，应用以默认内容启动并显示恢复信息。

## 9. 玻璃视觉、辅助功能与资源

1. 分别用独立数据文件启动四个最终 app 实例：浅色、深色、减少透明度、增强对比度。浅色／深色只设置 `FLOATING_WORKSPACE_APPEARANCE`；后两组同时设置对应辅助功能覆盖。不得修改全局系统偏好。
2. 通过公开视图状态核对实际 palette 和 material，并用真实窗口的 AX 标签核对便签、模式、图钉、保存状态与 alert 仍可访问：浅色 C 的两个渐变色为 `#E0F4FF` alpha `0.68`、`#EEE4FF` alpha `0.60`；深色 B 的背景为 `#121926` alpha `0.64`，强调色为 `#8BD0FF`。普通状态使用 active、emphasized 的 `.popover` material 和 behind-window blending。
3. 减少透明度实例必须隐藏 material 与渐变，使用 alpha `1` 的实色背景、内容底色和侧栏；增强对比度实例的实际渲染边框必须在对应背景上明显提高明暗对比：浅色使用 `#121926` alpha `0.45` 的深色描边，深色使用白色 alpha `0.55` 的描边。恢复无覆盖启动后应重新读取真实系统设置。
4. 检查最终包中的 16px／32px 菜单栏模板和 App Icon 小尺寸资源：模板保持单色 alpha 与 `悬浮工作台` AX 描述，悬浮徽章主体、图钉徽章可辨认；图片模式图标和文字仍存在但按钮禁用，网页按钮可用，运行全程无 Dock 图标。截图只在现有 harness 已有权限时采集，不把不可用截图写成证据。
5. 在空白模式选择可识别的非默认背景色，立即核对保存的 sRGB 值和实际背景视图：用户颜色成为背景 tint，主题渐变和玻璃材质被抑制；减少透明度与增强对比度时仍保留该用户颜色。切回便签后应恢复材质和主题渐变，切换外观不得额外保存或改变用户颜色。
6. 外观变化前后比较隔离 JSON 的内容与保存次数，不得出现仅由外观变化触发的新保存；确认没有持续动画、轮询或高频重绘循环。窗口必须使用原生 `panel.hasShadow = true` 阴影，背景 layer 的 `shadowOpacity` 为 `0` 且 `shadowPath` 为空，不得添加自定义 layer 阴影、内部暗化或离屏 `shadowPath` 渲染通道。

通过标准：四种隔离外观与辅助功能回退的实际状态正确，文字和 AX 标签可用，小尺寸资源完整，空白用户颜色不被渐变覆盖，未引入额外保存、图片模式启用、持续重绘或 Dock 图标。

## 10. 网页浏览、编辑、重放、安全、会话与主题

1. 只在回环地址提供 fixture，并记录服务进程及访问日志；不得绑定 `0.0.0.0` 或暴露到局域网：

   ```bash
   python3 -m http.server 8765 --bind 127.0.0.1 --directory Tests/Fixtures/web
   ```

2. 用独立数据文件启动最终 app，切换到 `网页`。确认 URL、打开、后退、前进、刷新、编辑按钮及状态／错误标签可通过 AX 访问，图片按钮仍禁用；便签和空白模式来回切换后原内容不丢失，窗口最小宽度仍为 360。
3. 打开 `http://127.0.0.1:8765/static.html?case=<run>`，等待 `加载完成`。点击导航链接，检查 URL 和后退／前进状态；再分别输入 `file:///tmp/private.html`、带用户名密码的 URL、畸形 authority 和 `http://127.0.0.1:1/unreachable`，确认拒绝或网络失败提示可见。用仅绑定回环地址的临时自签 HTTPS 服务检查证书错误，必须显示 `证书验证失败，已停止加载`，不得绕过信任。
4. 回到静态页，点击 `编辑正文`，修改 `#editable-text` 并触发表单／主动内容 fixture 的保存。800ms 停顿后检查隔离 JSON 中该规范化 URL 的 `webDrafts`：保留新正文，但不包含 `script`、iframe/object/embed、meta refresh、`on*`、`javascript:`、form action/method、密码或其他输入值。访问日志不得出现远程写入或表单提交请求。
5. 刷新当前静态页，确认正文恢复且状态显示 `已恢复上次修改`。记录重放前后的草稿内容与更新时间，后续 DOM 变化不得反复重放或循环保存。点击 `结束编辑` 后正文恢复只读。
6. 再次修改静态页，在 800ms 内立即通过 URL 输入框打开导航目标（`contentEditable` 内的链接只放置光标，因此导航前保存用 URL 导航验证）。等待目标 URL 加载后后退，确认离开前已保存最新正文，返回后单次重放显示最新值；不能只验证较早一次自动保存。
7. 打开 `http://127.0.0.1:8765/dynamic.html?case=<run>`，编辑并保存正文后刷新。fixture 第二次加载会移除原 body；必须显示 `无法应用上次修改`，原草稿字节保持不变，不自动重试或删除草稿。
8. 重启最终 app，用新的 `static.html?case=session-<run>` 检查会话：新进程首次加载页面输出 `session-absent`，同进程刷新后输出 `session-present`。再次正常退出并重启最终 app，再打开同一 URL，必须重新输出 `session-absent`，证明 Cookie／sessionStorage／登录状态没有跨进程持久化。
9. 分别在浅色、深色、减少透明度、增强对比度覆盖下以网页模式启动独立实例。检查工具栏、URL、状态、错误及正文可读，AX 标识存在，网页按钮主题强调色正确；实际玻璃 palette、material、实色回退和边框继续满足第 9 组，网页内容不得迫使窗口变宽或引入额外保存。
10. 在一个新的静态 case 中编辑正文并在 800ms 内通过真实菜单正常退出。确认退出流程先保存网页草稿再保存工作区；重启并打开该 URL，最新正文恢复。随后清理自己启动的 HTTP／HTTPS 服务和 app 实例，保留各自独立日志。

通过标准：导航、可见错误、编辑／刷新单次重放、动态失败、导航与退出前保存、清理结果、非持久会话及四种外观全部独立通过；没有远程写入、持久登录、图片模式启用或外部地址暴露。任何一项失败都不能由另一项通过抵消。

## 完成判定

只有自动化测试、release 构建、签名校验、以上八组最终 app 功能验收、第 9 组视觉验收及第 10 组网页专项验收全部通过，并按准备第 10 步恢复窗口 frame，才能声明 Phase 1 + glass visual refresh + web mode 完成。记录每组实际命令、日期化输出与结果；失败、未执行和不可复现必须原样记录，不得用早期 debug-app 证据替代。图片模式、持久登录、Chromium/Electron 和远程网站写入不属于完成声明。
