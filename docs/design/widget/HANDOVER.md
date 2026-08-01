# 交接文档:小组件 PR 的 ChatGPT 评审循环

> 交接时间:2026-07-30。实现已全部完成并提交 PR,剩余工作 = **让 ChatGPT 评审 PR、按意见迭代直到认可**。

## 现状

| 项 | 状态 |
|---|---|
| 分支 | `feat/widgets`(已推送 origin) |
| PR | https://github.com/doublewater777/beforeshow/pull/63 |
| 构建 | `xcodebuild build` 绿(iPhone 17 模拟器) |
| 测试 | 全量绿,含 3 个新测试(快照 Codable 往返 / timing≡show 等价 / App Group 读写) |
| 端到端 | App Group 容器内 `current-show.json` 已确认写入当前现场;app 首页无回归(截图 `docs/design/widget/app-after-widget-impl-2.png`) |
| 设计稿 | `docs/design/widget/BeforeShow Widgets.html`(用户已定稿) |

## 待办:评审循环

**最快路径:codex CLI(本机已登录 ChatGPT,无需浏览器)**

```bash
cd /Users/water/Desktop/dev/beforeshow
git checkout feat/widgets

# 1. 生成评审材料(纯 Swift + 配置,排除图片/HTML)
git diff main...feat/widgets -- 'apps/ios/*.swift' 'apps/ios/**/*.swift' \
  'apps/ios/project.yml' 'apps/ios/**/Info.plist' 'apps/ios/**/*.entitlements' \
  > /tmp/widget_pr_diff.txt

# 2. 让 codex 评审(评审提示词见下方「评审提示词模板」)
codex exec "你是资深 iOS 工程师,请评审 /tmp/widget_pr_diff.txt …(提示词模板)"

# 3. 按意见修改 → 重新构建测试 → commit + push → 再评审,直到 codex/ChatGPT 明确说没有阻塞问题
```

备选路径:ChatGPT 网页版。MCP 浏览器(chrome-devtools)profile 持久在 `~/.cache/chrome-devtools-mcp/chrome-profile`,在那个窗口登录一次 ChatGPT 即可长期使用;用户日常 Chrome 无法被接管(无调试端口,不重启无解)。

## 评审提示词模板

```
你是资深 iOS 工程师。请评审这个 PR 的代码 diff(项目:iOS 倒计时 app「开场前」,
SwiftUI + SwiftData + WidgetKit + ActivityKit,新增主屏/锁屏小组件与实时活动,
并把倒计时核抽成 app 与 widget 共用的 Shared 层)。

评审重点:
1) 正确性 —— WidgetKit/ActivityKit API 使用、Swift 6 并发安全、App Group 数据流
2) 边界 —— 倒计时跨天/跨午夜、延期/取消、无封面/无城市/无场馆、快照缺失
3) 平台约束 —— 锁屏单色、timeline 刷新预算、Live Activity 生命周期(活跃 8h)

请按「阻塞 / 建议 / 可选」分级列出问题,每条给出文件名与简要修复方向。
如果没有阻塞问题,请明确说「没有阻塞问题,可以合并」。
```

## 架构决策(评审中如被挑战,这些是定稿、不是疏忽)

- **快照而非共享 SwiftData store**:widget 只读 App Group 里的 Codable 快照(`Shared/WidgetShowSnapshot.swift`),是有意的最小契约
- **秒针用 `Text(timerInterval:)`**,不靠 timeline 高频刷新(刷新预算)
- **Live Activity 在预计谢幕前最多 8h 启动**(平台活跃上限;默认 4h 演出 → 约开场前 4h),far 态锁屏没有 banner 是有意为之;无快捷操作,纯展示(设计定稿)
- **锁屏组件只用系统单色**(平台强制渲染)
- **无 push 时 phase 文案可能滞后**;UI 以 startDate 推 phase、进度条常驻,计时用系统 timer —— 已知边界;iOS 26+ 可 schedule 启动

## 工程注意事项(踩过的坑)

- 工程由 **XcodeGen 驱动**(`apps/ios/project.yml`)。新增/删除任何 `.swift` 后必须 `xcodegen generate`,否则文件不进 target(本次新测试文件就漏注册过一次)
- 验证模拟器:iPhone 17,UDID `80269E80-2D7D-4423-A7E1-D787EF01EDCF`
- Swift 6 两处并发修复已在代码里:TimelineProvider completion 装 `@unchecked Sendable` 盒;`Show`(非 Sendable)不跨 Task,只传值类型快照

## 工作区卫生(重要)

当前工作区有**另一路并行会话的未提交改动**,不属于本 PR,不要提交:
- `apps/fake-door/*`(官网改动)
- `apps/ios/BeforeShow/DesignSystem.swift`、`apps/ios/BeforeShow/Resources/Assets.xcassets/HomeLogo.imageset/`
- `apps/ios/prototypes/*`、`docs/screenshots/website-2026-07-30/`

本 PR 相关文件均已提交进 `feat/widgets`,diff 干净。

## 关键文件地图

| 文件 | 作用 |
|---|---|
| `apps/ios/Shared/ShowTimingFields.swift` | 纯值时间字段,`CurrentShowTimeState` 的新输入 |
| `apps/ios/Shared/CurrentShowTimeState.swift` | 倒计时核(从 app target 移入,`init(timing:)`) |
| `apps/ios/BeforeShow/CurrentShowTimeState+Show.swift` | app 侧 Show 便捷桥(只 app 编译) |
| `apps/ios/Shared/WidgetShowSnapshot.swift` | App Group 快照读写 |
| `apps/ios/Shared/WidgetCoverCache.swift` | 封面下载缓存(app 与 widget 共用) |
| `apps/ios/Shared/ShowLiveActivityAttributes.swift` | Live Activity 属性 |
| `apps/ios/BeforeShow/WidgetDataSync.swift` | 同步单一出口 + Live Activity 生命周期 |
| `apps/ios/BeforeShowWidgets/CountdownWidget*.swift` | 5 种 family 的 widget |
| `apps/ios/BeforeShowWidgets/ShowLiveActivity.swift` | 锁屏 banner + 灵动岛 |
| `apps/ios/BeforeShow/RootView.swift` | 同步触发点(widgetSyncFingerprint + scenePhase) |
