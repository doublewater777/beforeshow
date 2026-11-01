# PostHog 充分启用：目标与排期

现状（见 `docs/observability/product-analytics.md` 与 `apps/ios/BeforeShow/Infrastructure/Analytics/`）：

- SDK 已接入（3.93.1），生命周期事件、错误自动捕获、session replay、dSYM 上传、opt-in/out 开关均已就位。
- 已通过 `ProductAnalytics.capture` 埋了 34 个产品事件，覆盖引导、导入、付费墙、陪伴核心动作、同行诊断。隐私纪律到位：不含姓名 / 艺人 / token / 用户输入。
- **但 PostHog 的上层能力一块没用**：没有 `identify`、没有 `$screen`、购买事件不带 `$revenue`、session replay 没做脱敏调优、feature flag / experiment 闲置。

本 goal 把「已有事件用出价值」而非「再埋更多事件」作为目标。全部改动遵守现有采集规则：新事件只经 `ProductAnalytics.capture`，不破坏已上线事件名 / 属性名，不引入 PII。

## 实现状态（已全部落地）

| # | 项 | 状态 |
| --- | --- | --- |
| 1 | 身份与 person properties | ✅ `AnalyticsInstallID`（Keychain）+ `ProductAnalytics.identify()` + `setPersonProperties` |
| 2 | 屏幕浏览 `$screen` | ✅ `ProductAnalytics.screen(_:)` / `.bsScreenView(_:)`，覆盖 tab、引导页、付费墙、添加现场及各设置页 |
| 3 | 购买带 `$revenue` | ✅ `ProPurchaseRevenue`（交易实付金额，免费试用不记），成功购买发 `$revenue` |
| 4 | Session replay 脱敏调优 | ✅ 关掉 `maskAllImages`，用户照片 / 视频 / 文字用 `.bsMaskUserContent()` 显式遮回 |
| 5 | Feature flag 实验 | ✅ `RemoteConfig`，首个 flag `winback-save-copy-variant` 驱动挽留文案，分组写进 super properties |

## 1. 身份与 person properties（最高优先级）

PostHog `personProfiles` 默认 `.identifiedOnly`，而 App 从未调用 `identify`。后果：留存 / 漏斗只能按匿名 anonymous distinct_id 聚合，Person 页面无可读用户。

- 新增一个稳定的匿名安装 ID：存 Keychain（`kSecClassGenericPassword`，不与 iCloud 绑定，重装后保留），首次启动生成 UUID。不采用 iCloud `userRecordID`——会把它和用户的 iCloud 身份挂钩，超出「匿名分析」口径。
- `ProductAnalytics` 新增 `identifyIfNeeded()`：首次设置完成后调用一次 `PostHogSDK.shared.identify(installID)`。
- 把 `AnalyticsContext` 的 `is_pro`、`show_count`、`footprint_count`、`current_show_phase`、`has_widget` 同步为 person properties（`PostHogSDK.shared.setPersonProperties` 或 identify 时带 `$set`），使留存 / 漏斗能按人、且能在 Person 页面按这些维度筛选。
- super properties 路径保持不变（继续 `ProductAnalytics.register`）。person 与 super 是两套，互补。

## 2. 屏幕浏览 `$screen`（SwiftUI 手动埋）

SDK 仅 swizzle `UIViewController.viewDidAppear`（`PostHogScreenViewIntegration`），纯 SwiftUI App 不会产生任何 `$screen`。后果：无页面流量、无用户路径、无法定位卡点。

- 给 RootView 的各 tab 根视图与每个主要 ContentView 加 `.postHogScreenView("screen_name")`（`PostHogSwiftUIViewModifiers`）。screen_name 用稳定字符串，不拼动态内容。
- 至少覆盖：引导根、首页（当前现场）、足迹根、听、时刻表、设置根、付费墙。
- 不在列表 / 子行 / sheet 内联视图上埋，避免噪声。
- 完成后在 PostHog 验证 `$screen` 事件确实有量、且 `$screen_name` 落在后续事件上。

## 3. 购买事件带 `$revenue`

`proPurchaseCompleted` 现在只有 `plan`，无金额。后果：PostHog 营收仪表盘 / LTV 用不了。

- `ProductAnalytics` 在 `proPurchaseCompleted` 路径补充 `$revenue`（金额）+ `$currency`（商店区域货币，如 `USD` / `CNY`）。金额为数值，不记录原始错误文案。
- 仅成功购买记 `$revenue`；失败 / 取消不记。
- `purchaseTapped` 已带 `price`（展示字符串），保留不改动。
- **营收是事实数据，不是「UI 走到了成功分支」**（PR #357 review）：
  - **商品标价不等于实收金额**。免费试用 / intro 优惠也会给 Pro 权益，但商品标价仍是 $4.99；按标价记就会把试用记成正收入。
  - 因此金额只取 `ProPurchaseRevenue`，由 store 统一整理：
    - `entitlement.periodType == .normal`（试用 / intro / 取不到均不记）；
    - 优先且只取 StoreKit 2 交易实付金额（`transaction.sk2Transaction?.price`，iOS 15+）；拿不到实付价格时上报 nil，不回落商品标价。
    - 金额 > 0 且有 ISO 4217 货币代码；否则上报 nil，不发 `$revenue`。
  - **无效权益不算购买成功**。`purchase()` 返回后先校验 `entitlement.isProActive`，未激活时走失败分支：不记 `proPurchaseCompleted`、不显示「Pro 已启用」。
  - 按 `transactionID` 做幂等去重，同一笔交易只记一次。
  - 续订、退款、currency 变更等以 RevenueCat Webhook / 服务端为准，客户端只记首次成交。

## 4. Session replay 脱敏调优

`maskAllTextInputs` / `maskAllImages` 默认 `true`，回放里输入框全黑、封面 / 照片全占位块。对「封面 + 唱片 + 回忆卡片」是核心视觉的 App，回放基本看不出在操作什么。

- 先在 PostHog 看板抽几条真实回放，确认当前可辨识度。
- 非敏感内容用 `postHogNoMask()` 放行（例如封面图、唱片 UI、空白占位区），降低回放噪声但仍保护输入。
- 明确仍要 `postHogMask()` 的：任何文本输入框、用户配文、邀请 token 展示、姓名类字段。
- 不依赖「全 mask」的默认保护，对新增含用户输入的视图显式加 mask。
- 不降低采样到 0（保持现状默认），除非回放量成为性能 / 隐私负担。

## 5. 试一个真实 feature flag / experiment

SDK 已 `preloadFeatureFlags = true`，但代码零调用 `isFeatureEnabled`。Experiment 功能闲置。

- 选一个低风险、可逆的真实场景：例如引导页某句文案、付费墙方案 A/B、或某个新功能的灰度。
- 用 `PostHogSDK.shared.isFeatureEnabled("flag_key")` 取值驱动分支，先在小比例灰度。
- 不为 flag 引入新的远程配置依赖；仅用一个 flag 跑通「配置 → 取值 → 分支 → 看板对比」闭环。

## 验收

- Person 页面出现可读安装 ID，留存 / 漏斗改用 identify 后身份。
- `$screen` 事件有量，`$screen_name` 正确附着在业务事件上。
- 成功购买事件带 `$revenue` 与 `$currency`，营收看板可读；免费试用与无效权益不记。
- 回放里核心视觉可辨识、用户输入仍被遮挡；新增含输入视图显式 mask。
- 至少一个 feature flag 在真机按配置分支并产出对比数据。

## 不做

- 不加新的业务事件（现有 34 个足够覆盖北极星与漏斗）。
- 不引入 PII（姓名 / 艺人 / token / 用户输入）到任何事件或 person property。
- 不把分析身份与 iCloud / Apple ID 挂钩。
- 不动已上线的事件名与属性名，只新增 person properties 与 `$screen` / `$revenue` 两类系统属性。
