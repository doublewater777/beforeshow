# AGENTS.md

App 已上线：持久化格式（SwiftData 模型、UserDefaults key、深链 URL、widget kind）需要兼容旧版本，删改 @Model 必须带迁移方案。不要大字号适配，不需要voice over

临时文件、截图不要上传git，密钥不要上传git

i18n

不要有非必要的解释性文字

use beforeshow iphone 18 pro simulator
## iOS 命令行构建（重要）

命令行构建必须显式带上开发团队，否则 xcodebuild 找不到项目里配置的 `"iPhone Developer"` 签名身份（钥匙串里只有 `"Apple Development"` 证书），会退回 "Sign to Run Locally" ad-hoc 签名，把 iCloud 容器 / App Groups / WeatherKit 等受限 entitlements 全部剥掉。后果：App 启动即闪退，`BeforeShowApp.init()` → `CKContainer(identifier:)` SIGTRAP（见 `CompanionSharing.swift` 的 `CloudKitCompanionSharingService.live()`）。

```bash
cd apps/ios
xcodebuild -project BeforeShow.xcodeproj -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=29C8MS76CZ build
```

验证方法：构建后检查 `Entitlements-Simulated.plist`（在 DerivedData 的 `BeforeShow.build/Debug-iphonesimulator/BeforeShow.build/DerivedSources/` 下）里应有 `com.apple.developer.icloud-container-identifiers`；装到模拟器后 `simctl launch` 进程应存活（旧 bug 下 2 秒内必崩）。从 Xcode GUI 里 Run 不受此问题影响。

注意：entitlements 里新增了 WeatherKit，真机/上传签名时要求 App ID 在开发者后台开启 WeatherKit capability。

## iOS 架构边界（重要）

非 trivial 的 iOS 改动先读 `apps/ios/ARCHITECTURE.md`。

- 新 Swift 源文件不要再放进 `apps/ios/BeforeShow/` 根目录；feature 默认进 `BeforeShow/Features/<Feature>/`。
- `RootView.swift` 只保留 app/root routing，不再新增 feature 级 UI、媒体 I/O 或业务 mutation。
- SwiftData model 文件只放持久化字段、校验和 domain mutation；展示格式化、sheet/navigation 状态不要塞进 model。
- `Shared/` 只放 App 与 Widget 真正共同需要的代码，不能作为“不知道放哪”的兜底目录。
- `RootView.swift`、`AddShowFlowViews.swift`、`FootprintsArchive.swift`、`FootprintArchiveViews.swift`、`MemoryFragmentsView.swift` 等 legacy hotspot 原则上只缩不涨；先运行 `python3 apps/ios/scripts/check_architecture.py`。
- 新增/移动 Swift 源文件后，以 `apps/ios/project.yml` 为真源运行 `xcodegen generate`，并提交生成后的 `BeforeShow.xcodeproj`；不要只手改 pbxproj。

## Git commit 规范

- 每个 commit subject 必须以当前 App 版本开头：`<major.minor.patch>: <描述>`，版本以 `apps/ios/project.yml` 的 `MARKETING_VERSION` 为准。
- 新 clone 后运行 `./scripts/setup-hooks.sh` 安装校验 hook。详细规则见 `docs/agents/commit-convention.md`。

## Agent skills

### Issue tracker

GitHub Issues via `gh`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default Matt Pocock triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` + `docs/adr/`. See `docs/agents/domain.md`.

### Anti-rot loop

- Feature delivery: `to-spec` → `tdd` / `implement` → `code-review` → `pr`
- Architecture debt discovery: `architecture-rot-check` / `improve-codebase-architecture`
- Agent environment repair: `retro`
- Accidental complexity audit: `reclaim-code-entropy`
- Review standards: `CODING_STANDARDS.md`

Scheduled weekly runs are hands-off: write `docs/agents/architecture-reviews/`, file a `needs-triage` GitHub issue only for guard failures or one clear Strong candidate, stay quiet otherwise, never auto-refactor.

## 工作方式

- 只做被要求的事；不加推测性的抽象、配置项和不可能场景的错误处理。
- 死代码：发现生产路径无人调用的代码（包括只被测试引用的），证明无消费者后连同其测试一起删除；涉及持久化格式的按顶部兼容规则处理。
- 先用已有组件和 design token，不硬编码样式。
- Sheet/navigation chrome 用中性前景色：完成用 `checkmark`（语义仍是完成），关闭才用 `BSChromeToolbarCloseButton`/`xmark`；不要把 `TimetableStyle.mine` / accent / warm 黄涂到 chrome 上（见 `docs/agents/issue-notes/toolbar-chrome-tint-2026-10-14.md`）
- 改动要可验证：先写复现/约束测试，再改实现。

## Presentation Discipline

**一次只看到一个主界面；完成一个主要动作后，最多只给一次轻反馈，不再立刻要求第二次确认。**

- 一个用户事务只能有一个主要 presentation surface；不要让 sheet、fullScreenCover、alert、confirmationDialog 连续接力。
- 主要动作完成后，最多给一次非阻塞轻反馈（例如一次 toast、按钮内成功态或页面内成功态），不要再立刻弹出第二个确认。
- 能在当前主界面提前完成的选择，必须 inline 解决；不要等提交成功后再追问。
- 错误优先留在当前主界面原位展示，并提供重试/关闭；除非当前界面无法承载，否则不要再叠 alert。
- 如果某个后续动作不是完成当前事务所必需，就延后到用户下一次自然进入相关上下文时再处理。
- 系统权限弹窗也算一次阻塞式 presentation；不要紧跟在刚完成的 sheet/fullScreenCover 后面触发。
- Review UI 流程时按用户连续看到的界面序列检查，而不是只看各状态在代码里是否“合法”。
