# AGENTS.md

不用考虑兼容性，这个app还没有上线，不要大字号适配，不需要voice over

临时文件、截图不要上传git，密钥不要上传git

i18n

不要有非必要的解释性文字

use beforeshow iphone 18 pro simulator
## iOS 命令行构建（重要）

命令行构建必须显式带上开发团队，否则 xcodebuild 找不到项目里配置的 `"iPhone Developer"` 签名身份（钥匙串里只有 `"Apple Development"` 证书），会退回 "Sign to Run Locally" ad-hoc 签名，把 iCloud 容器 / App Groups / WeatherKit 等受限 entitlements 全部剥掉。后果：App 启动即闪退，`BeforeShowApp.init()` → `CKContainer(identifier:)` SIGTRAP（见 `CompanionSharing.swift` 的 `CloudKitCompanionSharingService.live()`）。

```bash
cd apps/ios
xcodebuild -project BeforeShow.xcodeproj -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
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

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. UI Consistency & Component Reuse

**Same design system, same set of components. Don't reinvent the wheel.**

Before implementing a module:
- Check for existing shared components first (Button, Card, Modal, Form, etc.)
- Need a component that doesn't exist? Abstract it as a shared component first, then use it in your module
- UI style, spacing, font sizes, colors must follow design tokens — no hardcoded values
- Keep components atomic and reusable; don't mix page logic with UI in one file

## 5. Presentation Discipline

**一次只看到一个主界面；完成一个主要动作后，最多只给一次轻反馈，不再立刻要求第二次确认。**

- 一个用户事务只能有一个主要 presentation surface；不要让 sheet、fullScreenCover、alert、confirmationDialog 连续接力。
- 主要动作完成后，最多给一次非阻塞轻反馈（例如一次 toast、按钮内成功态或页面内成功态），不要再立刻弹出第二个确认。
- 能在当前主界面提前完成的选择，必须 inline 解决；不要等提交成功后再追问。
- 错误优先留在当前主界面原位展示，并提供重试/关闭；除非当前界面无法承载，否则不要再叠 alert。
- 如果某个后续动作不是完成当前事务所必需，就延后到用户下一次自然进入相关上下文时再处理。
- 系统权限弹窗也算一次阻塞式 presentation；不要紧跟在刚完成的 sheet/fullScreenCover 后面触发。
- Review UI 流程时按用户连续看到的界面序列检查，而不是只看各状态在代码里是否“合法”。

## 6. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
