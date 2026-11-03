# Floating Workspace Phase 1 验收

本规程只验收 `dist/FloatingWorkspace.app` 的最终 release 构建。便签和空白属于 Phase 1；图片和网页不在本次范围内。任何一组失败都阻止 Phase 1 完成声明。

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

3. 除默认启动冒烟外，每个用例设置独立的 `FLOATING_WORKSPACE_STORE_URL`，避免改写真实工作区。完整文件 URL 和 POSIX 路径均可。
4. 日期化终端输出、辅助脚本和截图仅保存到 `.artifacts/acceptance/`。截图不是必选项；不得为取证授予 Screen Recording 权限。
5. 操作真实窗口时，等待目标应用确实成为 frontmost、目标 alert 确实出现，再发送输入或记录结果。不要把 `activate` 调用返回当成 frontmost 已成立。
6. 八组全程确认：没有 Accessibility 或 Screen Recording 权限提示，没有 SkyLight/私有 API 依赖，Phase 1 进程没有网络请求。可用 `lsof -nP -a -p <pid> -i` 和交互期间的网络进程采样辅助确认无网络连接。
7. 每个用例结束后通过菜单正常退出；保存失败用例使用明确的放弃退出按钮。清理自己启动的 Safari、Notes 和 IDE，但不修改其中已有内容。

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

## 2. 快捷键与菜单切换同一面板

1. 保持第 1 组的同一实例和同一个面板。分别让 Safari、Notes 和 IDE frontmost，等待真实 frontmost 条件后按 `⌃⌥⌘P`。
2. 每次按键后确认该面板在 `.floating` 与 `.normal` 间切换，隔离 JSON 中 `isPinned` 同步改变。取消置顶后重新激活目标应用，面板应处于普通层级；再次按键恢复置顶。
3. 使用菜单栏 `切换置顶` 再执行往返切换，确认窗口层级与 `isPinned` 跟随同一面板变化。

通过标准：快捷键和菜单操作同一实例、同一面板；两种入口都能完成 `.floating` → `.normal` → `.floating`。

## 3. 空白模式即时生效与持久化

1. 在同一最终 app 实例切换到 `空白`，输入可识别标题，修改背景颜色、宽度和高度，并确认各字段的实际提交动作。
2. 每次修改后立即检查窗口标题/背景/frame 和保存状态，不等待重启才判定即时生效。
3. 通过菜单安全退出并重启同一隔离数据文件，确认空白标题、背景颜色、宽度和高度全部恢复。

通过标准：四项空白配置立即应用，并在 relaunch 后保持一致。

## 4. 便签、模式、frame 与置顶状态持久化

1. 使用同一隔离数据文件，编辑便签文本，选择目标模式，移动并缩放窗口，切换一次置顶状态。
2. 等自动保存完成后，通过菜单安全退出，再启动最终 app。
3. 对照退出前的 JSON 和窗口记录，检查便签文本、`selectedMode`、frame 与 `isPinned`。

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

## 完成判定

只有自动化测试、release 构建、签名校验及以上八组最终 app 验收全部通过，才能声明 Phase 1 完成。记录每组实际命令、日期化输出与结果；失败、未执行和不可复现必须原样记录，不得用早期 debug-app 证据替代。
