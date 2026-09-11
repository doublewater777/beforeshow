# FootprintArchiveSnapshot 数据结构扩充方案

状态：已决策，服务于 [足迹 Tab 升级 · Wayfinder Map](https://github.com/doublewater777/beforeshow/issues/87)。

## 结论

`FootprintArchiveBuilder` 继续只接收 `[Show]`，负责生成统计快照；不把 `MemoryFragment`、`ShowAsset`、`DynamicCover` 或城市坐标放进统计快照。封面、洞察、可见性阶梯和 geocoding 都是独立的后处理能力。

快照保留现有的归档现场集合和总量字段，并增加三类带上下文的排行项以及按年组织的月度活动数据。

## 推荐模型

```swift
struct FootprintArchiveSnapshot {
    let shows: [Show]                         // 最新 → 最早
    let artistItems: [FootprintArtistItem]
    let cityItems: [FootprintCityItem]
    let venueItems: [FootprintVenueItem]
    let years: [FootprintYearGroup]           // 年份降序
    let currentYearCount: Int
    let totalDurationMinutes: Int

    var firstShow: Show? { shows.last }
}

struct FootprintArtistItem {
    let name: String
    let count: Int
    let showIDs: [UUID]                       // 最早 → 最近
    let yearSpan: FootprintYearSpan
}

struct FootprintCityItem {
    let name: String
    let count: Int
    let venueCount: Int                       // 去重后的非空场馆数
    let showIDs: [UUID]
    let yearSpan: FootprintYearSpan
}

struct FootprintVenueItem {
    let name: String
    let count: Int
    let cities: [String]                      // 去重、稳定排序；不假设一个场馆只有一个城市
    let showIDs: [UUID]
    let yearSpan: FootprintYearSpan

    var isRevisited: Bool { count > 1 }
}

struct FootprintYearSpan {
    let first: Int
    let latest: Int
}

struct FootprintYearGroup {
    let year: Int
    let shows: [Show]
    let monthlyActivity: [FootprintMonthActivity] // 固定 1...12，0 场也保留
}

struct FootprintMonthActivity {
    let month: Int
    let showCount: Int
    let durationMinutes: Int
}
```

字段名可以按现有 Swift 命名规范微调，但语义保持不变。

### 为什么排行项按类型拆开

目前的 `FootprintRankItem(name, count)` 只能支持同一种横向排行。城市需要场馆数，场馆需要关联城市，艺人需要重复见面时间跨度；把这些字段塞进一个带大量 optional 的通用排行项会让数据语义变弱。

实现迁移时保留一个兼容适配层即可：

```swift
var artists: [FootprintRankItem] { artistItems.map(\.rankItem) }
var cities: [FootprintRankItem] { cityItems.map(\.rankItem) }
var venues: [FootprintRankItem] { venueItems.map(\.rankItem) }
```

这样现有分享卡、旧的完整档案页和已有测试可以继续读取 `archive.artists / cities / venues`；新首页和三个独立档案页改用 typed items，不形成两套统计来源。

### `showIDs` 的用途

排行项只保存关联现场的 ID，不重复持有 `[Show]`。快照本身已经持有完整的 `shows`，后续用 `archive.shows(for:)` 或按 ID 建立一次索引即可得到关联现场。

`showIDs` 统一按最早到最近排列，`yearSpan` 由 Builder 在同一套现场排序和当地年份规则下计算。这样艺人时间轴、城市现场列表、场馆回访列表共享同一组身份数据。

### 月度活动的组织方式

月度数据嵌入 `FootprintYearGroup`，不单独在 Snapshot 再维护一份按月数组：

- 趋势图：读取当前年份的 `monthlyActivity`。
- Heatmap：遍历 `years × monthlyActivity`。
- 年度详情：同一份数据同时提供每月场次数和观看时长。

每个年份固定生成 12 个月，空月份的 `showCount` 与 `durationMinutes` 为 0。这样 View 不需要补齐缺失月份，坐标和 Heatmap 网格也稳定。

月份和年份都使用每场现场自己的 `timingCalendar()` 从 `effectiveDate` 计算，延续现有跨时区、跨年测试语义。

## Builder 边界

`FootprintArchiveBuilder.make(shows:now:calendar:)` 保持现有入口和过滤规则：

- 排除取消现场。
- 只收录 `.postShow` 或 `.ended`。
- 城市、场馆继续 trim 首尾空白；空字符串不参与统计。
- 排行按 count 降序，同分按稳定的本地化名称排序。
- 总时长继续使用 `ShowDurationFormatter` 动态计算，不持久化。

Builder 只做统计，不做以下工作：

- `MemoryFragment` / `ShowAsset` 查询与图片路径解析
- 动态封面或 Typography Cover 选择
- 洞察文案生成
- 数据量阶梯可见性判断
- 城市 geocoding 与坐标缓存

这些能力分别由后续票据中的 resolver / builder / policy 负责。这样仪式结束时 RootView 只需一个轻量的 identity snapshot，不会被媒体或地图数据依赖拖入。

## 现有调用方迁移

当前直接构造 `FootprintArchiveSnapshot` 的位置只有两处：

1. `FootprintArchiveBuilder.make(...)` 的正式统计路径。
2. `RootView.footprintIdentityForCeremony()` 的极简身份路径。

为第二处提供 `FootprintArchiveSnapshot.identityOnly(shows:)` 便利初始化器，或者保留新字段的空默认值；推荐前者，因为它明确表达该快照只用于排序身份，避免调用方手写一串空数组。

`FootprintDetailIdentityBuilder` 与新的排行项应共用同一套现场时间排序 helper，避免“第一场 / 第 N 场”与艺人、城市时间轴出现不同顺序。

## 不纳入本票据的决定

- 封面数据不放在 `FootprintArchiveSnapshot`；由 `FootprintCoverResolver` 单独产生 `[UUID: FootprintCover]`。
- 洞察结果不预先写入 Snapshot；由 `FootprintInsightsBuilder` 读取 Snapshot 生成结构化结果。
- 数据量阶梯不写成 Snapshot 的固定字段；由 `FootprintVisibilityPolicy` 根据 Snapshot 统计判断，避免快照同时承担展示策略。
- `VenueArchiveItem` 不保存含义不明确的 `revisitRate`；当前产品需求只需要 `count > 1` 的回访判断，使用 `isRevisited` 即可。若未来需要比例，应先定义分子和分母再新增字段。
- 场馆不只保存一个 `city`，而保存去重后的 `cities`，避免同名场馆跨城市时丢失信息。
