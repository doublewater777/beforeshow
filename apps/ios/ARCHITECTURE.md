# BeforeShow iOS Architecture

目标不是为了“分文件夹”而分层，而是让新增功能有唯一归属，避免继续把状态、路由、业务规则、媒体 I/O 和 SwiftUI 视图堆进同一个文件。

## 当前判断

现有业务逻辑总体可用，问题主要是物理边界已经落后于产品复杂度：

- `RootView.swift` 同时承担 App 路由、当前现场首页、媒体导入、通知同步、散场仪式和大量 UI。
- `AddShowFlowViews.swift`、`FootprintsArchive.swift`、`FootprintArchiveViews.swift`、`MemoryFragmentsView.swift` 已成为明显的增长热点。
- `Show.swift` 过去同时包含 SwiftData 模型和展示格式化。本轮先把展示格式化移出模型文件，作为后续拆分的第一步。
- Cloud Functions 已按 `auth/functions/logging` 分层，当前优先治理 iOS。

## 目标目录

新增代码按下面的归属放置。不要为了迁移而一次性移动所有旧文件；旧热点在被功能修改时逐步搬迁。

```text
BeforeShow/
├── App/
│   ├── App bootstrap / lifecycle
│   ├── Root routing
│   └── Deep links
├── Domain/
│   ├── Show
│   ├── Time / lifecycle policies
│   └── Pure domain values
├── Features/
│   ├── CurrentShow/
│   ├── DynamicCover/
│   ├── AddShow/
│   ├── Footprints/
│   ├── Memory/
│   ├── Companion/
│   ├── Settings/
│   └── Subscription/
├── Infrastructure/
│   ├── Media/
│   ├── Notifications/
│   ├── Weather/
│   ├── Cloud/
│   └── Analytics/
├── UI/
│   ├── DesignSystem/
│   └── SystemPresentation/
├── Resources/
└── Supporting/
```

`Shared/` 只放 App 与 Widget 都需要的代码。不能因为“不知道放哪”就放进 `Shared/`。

## 依赖方向

依赖只能大体沿下面方向流动：

```text
App -> Features -> Domain
App -> Infrastructure
Features -> Infrastructure
Features -> UI
Infrastructure -> Domain
Widget -> Shared
App -> Shared
```

禁止：

- `Domain` import SwiftUI / UIKit / Photos / RevenueCat / PostHog。
- `Infrastructure` 持有具体 feature View 或导航状态。
- `RootView` 实现 feature 级 UI、媒体 I/O 或业务 mutation。
- 一个 Feature 为了复用直接读取另一个 Feature 的私有状态；跨 feature 行为应通过 Domain 值、Coordinator 或窄接口连接。

## 文件职责

### App

只负责组装依赖、scene lifecycle、tab/root navigation、deep-link dispatch。`RootView` 应最终只看见“当前现场 feature”和“足迹 feature”的公开入口。

### Domain

只负责持久化实体、纯值对象、校验、状态转换和无 UI 的 policy。SwiftData model 不负责生成页面文案或控制 sheet/navigation。

### Features

一个 feature 自己拥有：

- SwiftUI views
- presentation state
- feature coordinator / use-case orchestration
- 只服务该 feature 的 formatter/policy

如果一个类型只有一个 feature 使用，不要提前放到全局 `UI` 或 `Shared`。

`DynamicCover` 是可被 `CurrentShow` 与 `Footprints` 复用的窄子 feature；可共享无状态展示入口，但导入、持久化与页面状态仍由各自 owner 管理。

### Infrastructure

负责文件系统、CloudKit、WeatherKit、通知、网络、系统权限、分析等副作用。尽量暴露窄接口，不让 View 直接拼接多个底层 store 的事务。

## 防止再次变乱的规则

1. **新增 Swift 文件不得继续放在 `BeforeShow/` 根目录。** 新 feature 默认放 `Features/<Feature>/`；只有真正跨 feature 的代码才进入 App/Domain/Infrastructure/UI。
2. **大文件只能缩，不能自然生长。** CI 对当前 legacy hotspots 设置预算。超过预算时，先拆职责再继续开发。
3. **新文件尽量 < 400 行；超过约 600 行应检查是否混入多个职责。** 这是 review 信号，不是为了机械拆小组件。
4. **一个页面可以有多个 View 文件，但业务状态只能有一个明确 owner。** 不通过多个 `@State`/singleton 拼出隐式 coordinator。
5. **修改 legacy hotspot 时采用“顺手搬出本次涉及的完整职责”，不要做全仓库大爆炸重构。** 行为先由测试锁住，再移动。
6. **新增源文件后运行 `xcodegen generate` 并提交生成后的 `BeforeShow.xcodeproj`。** `project.yml` 是项目结构真源，不能只手改 pbxproj。

## Legacy hotspot budgets

CI 当前只做“止涨”，不是要求本 PR 一次性清零技术债：

| File | Budget |
| --- | ---: |
| `RootView.swift` | 120 KB |
| `AddShowFlowViews.swift` | 155 KB |
| `FootprintsArchive.swift` | 105 KB |
| `FootprintArchiveViews.swift` | 125 KB |
| `MemoryFragmentsView.swift` | 95 KB |
| `BeforeShowApp.swift` | 26 KB |
| `Show.swift` | 24 KB |

预算只能在有明确架构理由时调整；正常新增功能不应通过“把预算调大”绕过检查。

## 推荐迁移顺序

### 1. CurrentShow / RootView

先把 `CurrentShowHomeView`、`CurrentShowManagementSection`、首页 sheet/presentation state 从 `RootView.swift` 迁到 `Features/CurrentShow/`。`RootView` 最终只保留 onboarding、tab 和跨 feature 路由。

### 2. AddShow

把 coordinator、manual/link/screenshot import、review form、平台链接帮助拆到 `Features/AddShow/`。导入来源共享同一个 draft/domain seam，不复制保存逻辑。

### 3. Footprints

把 archive builder/ranking 等纯计算迁到 Domain/Feature domain；dashboard、detail、share/export 分开。避免 archive snapshot、照片权限、分享卡和页面状态继续混在同一文件。

### 4. Memory

把 composer、viewer、media actions、media store 分成 Feature 与 Infrastructure 两侧。View 不直接负责磁盘 reconciliation。

### 5. App lifecycle / infrastructure

最后把 `BeforeShowApp` 中媒体维护、天气兜底、第三方 SDK bootstrap 拆成 App + Infrastructure 的独立职责。这里跨功能最多，等前面边界稳定后再动风险更低。

## Review checklist

每个新增功能在 review 时先回答：

- 它属于哪个 feature/domain/infrastructure？
- 状态 owner 是谁？
- View 是否直接做了持久化、文件、网络或系统服务编排？
- 是否为了方便又把代码加进 legacy hotspot？
- 是否真的需要跨 feature 复用，还是只是两个页面长得像？

如果这五个问题说不清，先确定边界再写代码。
