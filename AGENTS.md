# AGENTS.md

不用考虑兼容性，这个app还没有上线

临时文件、截图不要上传git，密钥不要上传git

i18n

use iphone 17 simulator

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

## 5. Goal-Driven Execution

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
