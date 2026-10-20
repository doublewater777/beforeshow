# 产品数据分析规范

事件定义的真源是 `apps/ios/BeforeShow/Infrastructure/Analytics/AnalyticsEvent.swift`；本文与之同步维护。同行操作事件见 [companion-monitoring.md](../companion-monitoring.md)。

## 北极星指标：月陪伴现场数

自然月内，至少发生一次**陪伴行为**的去重现场数。

现场一年只有几场，DAU/WAU 会随演出日历剧烈波动，不反映价值。BeforeShow 的价值单位是「被陪伴过的一场现场」：多添加现场、每场用得更深，都会推高它。

陪伴行为（事件带 `core_action = true`）：

| 事件 | 条件 |
| --- | --- |
| `listen_playback_started` | — |
| `timetable_saved` | — |
| `memory_fragment_created` | — |
| `dispersal_ceremony_completed` | — |
| `memory_card_shared` | — |
| `app_opened_from` | `source` 为 `widget` / `live_activity` |
| `companion_invitation_finished` / `companion_join_finished` | `outcome = succeeded` |

现场归属：`coalesce(properties.show_id, properties.current_show_id)`。

```sql
select toStartOfMonth(timestamp) as month,
       count(distinct coalesce(properties.show_id, properties.current_show_id)) as accompanied_shows
from events
where properties.core_action = true
  and properties.$app_namespace = 'com.doublewaterapps.beforeshow'
  and properties.$is_emulator = false
  and properties.$is_sideloaded = false
group by month
order by month
```

辅助指标：陪伴行为人均现场数、每场陪伴行为种类数（深度）。

## 留存漏斗

按用户，窗口从首次 `show_added` 起算：

| 步骤 | 判定 | 窗口 |
| --- | --- | --- |
| 1 安装 | `Application Installed` | — |
| 2 完成引导 | `onboarding_completed` | 1 天 |
| 3 添加第一场 | `show_added` 且 `is_first_show = true` | 1 天 |
| 4 激活 | 首场开场前任一陪伴行为 | 7 天 |
| 5 现场日回访 | `current_show_phase` 为 `show_day` / `live` 的任一事件 | 至首场散场 |
| 6 散场收束 | `dispersal_ceremony_completed`，或 `memory_fragment_created` 且 `phase` 为 `live` / `after` | 散场后 3 天 |
| 7 复用 | 再次 `show_added`（`show_count ≥ 2`） | 90 天 |

**核心留存率 = 第 7 步 / 第 3 步**。PostHog 周留存：起始事件 `show_added`，回访事件为陪伴行为。

## PostHog 看板

[BeforeShow · 产品北极星与留存](https://us.posthog.com/project/461647/dashboard/2218938)

5 个指标：月陪伴现场数、核心留存（第一场 → 第二场，90 天）、7 步用户漏斗、周留存、功能推荐露出 → 点击转化（按 feature / surface）。
仅统计 bundle `com.doublewaterapps.beforeshow` 且 `$is_emulator=false`、`$is_sideloaded=false` 的真机数据。
陪伴行为在 PostHog 中定义为 Action「陪伴行为（core_action）」，供激活步骤和周留存回访使用。
PostHog 漏斗只有一个总转化窗口（90 天），各步单独窗口不生效；复用以 `show_added` 且 `is_first_show = false` 判定。
SQL、查询定义与 insight ID 存在 [product-analytics-posthog.json](product-analytics-posthog.json)，不包含访问凭证。

## 公共属性

每次进入前台和现场变化后注册为 super properties：

| 属性 | 值 |
| --- | --- |
| `is_pro` | Bool |
| `has_widget` | 已添加任一 BeforeShow 小组件 |
| `show_count` | 我的现场总数 |
| `footprint_count` | 已结束且未取消的现场数 |
| `current_show_id` | 当前现场 ID；无则不带 |
| `current_show_phase` | `before` / `show_day` / `live` / `after` / `ended` / `canceled` / `postponed` / `none` |
| `current_show_days_until` | 仅 `before`：距开场自然日 |
| `current_show_is_festival` | 当前现场多艺人 |

`show_day`：当天未开场；`after`：当日谢幕至散场后停留期结束。

## 事件

`show_id` 为本机随机 UUID。

| 事件 | 属性 | 触发 |
| --- | --- | --- |
| `onboarding_started` | — | 引导出现 |
| `onboarding_page_viewed` | `page` | 引导翻页 |
| `onboarding_add_show_tapped` | — | 引导页点添加 |
| `onboarding_invite_accepted` | — | 引导页接受邀请 |
| `onboarding_skipped` | `from_page` | 跳过引导 |
| `onboarding_completed` | `method` | 完成引导 |
| `screenshot_recognized` | — | 截图识别成功 |
| `show_link_parsed` | — | 链接解析成功 |
| `duplicate_show_blocked` | `method`, `existing_show_id` | 重复现场拦截 |
| `pro_limit_reached` | — | 免费容量用完 |
| `show_added` | `show_id`, `method`, `lifecycle`, `is_first_show`, `is_festival` | 保存成功 |
| `show_ended_confirmed` | `show_id` | 用户确认散场时间 |
| `listen_playback_started` | `source`（`full` / `preview`） | 一段播放开始；切歌不重复计 |
| `timetable_saved` | `show_id`, `performance_count`, `is_new` | 时刻表保存成功 |
| `memory_fragment_created` | `show_id`, `has_media`, `media_count`, `phase` | 记忆保存成功 |
| `dispersal_ceremony_completed` | `show_id`, `has_rating`, `has_note`, `rating_value` | 散场仪式保存 |
| `dispersal_ceremony_skipped` | `show_id`, `trigger` | 关闭散场仪式 |
| `memory_card_shared` | `show_id`, `material_count` | 现场回忆卡片导出 |
| `app_opened_from` | `source`（`notification` / `widget` / `live_activity`）, `destination`, `feature` | 通知、「听」小组件或 `beforeshow://open` 链接打开 App；倒计时小组件无链接，不计 |
| `feature_recommendation_shown` | `show_id`, `feature`, `surface`（`card`） | 主卡推荐当日首次露出 |
| `feature_recommendation_tapped` | `show_id`, `feature`, `surface`（`card` / `notification`） | 点推荐 |
| `pro_paywall_viewed` | — | 付费墙出现 |
| `purchase_tapped` | `plan`, `price` | 点购买；价格为商店本地化展示字符串 |
| `purchase_cancelled` | `plan` | 用户取消系统购买确认 |
| `purchase_failed` | `plan`, `error_code` | 购买失败；仅记录系统错误码，不记录错误文案 |
| `paywall_closed` | `duration_seconds` | 付费墙离开屏幕时记录停留秒数 |
| `pro_purchase_completed` / `pro_purchase_failed` | `plan` | 购买结果 |
| `pro_restored` | — | 恢复购买成功 |
| `app_review_prompt_requested` / `app_review_store_opened` | `moment` | 评分 |

## 采集规则

- 新事件只经 `ProductAnalytics.capture(_:)`，不直接调用 `PostHogSDK`。
- 不采集姓名、现场名、艺人名、场馆、邀请 token、URL、配文或任何用户输入文字。
- 一次用户事务一个结果事件；不为中间 UI 状态埋点。
- 新增或改名事件同时改本文；已上线事件名与属性名不改，只新增。
- 用户关闭「产品数据分析」后 SDK opt-out，不发送任何事件。

## 身份、屏幕、营收与回放

详见 [posthog-activation-goal.md](posthog-activation-goal.md)。要点：

- **身份**：首次启动用 Keychain 里的匿名安装 ID 调 `identify`，并把公共上下文同步为 person properties。不使用 iCloud / Apple 身份。
- Keychain 写入失败时**不 identify**：宁可本次缺身份，也不把无法持久化的随机 UUID 上报成 Person（会把同一装切成多个 Person，污染留存 / 漏斗）。
- **屏幕**：`$screen` 是系统事件，经 `ProductAnalytics.screen(_:)` 或 `.bsScreenView(_:)` 上报。纯 SwiftUI 下 SDK 的自动采集不生效，必须显式埋。名字须是稳定 ASCII 值，不用界面文案（`BeforeShowTab.rawValue` 是中文，改用 `analyticsKey`）。
- **营收**：成功购买额外发 `$revenue`（`$amount` + `$currency`），金额取自 store 真实价格，catalog 占位价不上报。
- **实验**：flag 经 `RemoteConfig` 读取；分组以 `$feature/<flag_key>` 写进 super properties，使同会话事件都带分组。flag 未命中时行为等同于关闭。
- **回放**：`maskAllImages` 已关闭以保留封面等核心视觉；用户照片、视频、文字展示处用 `.bsMaskUserContent()` 显式遮回。输入框仍由 SDK 默认全遮。
  默认遮罩落在**共享组件**上（`MemoryThumbnail`、`FootprintLocalImage`、`FootprintCoverLocalImage`、`BSZoomableImagePage` 调用点），而不是逐个调用点：加新展示路径时不需要重新记一遍规则（PR #357 review）。
- **实验分组快照**：一次展示只取一次 flag，文案与曝光事件都读同一份快照（`WinbackCopyExperiment`）；flag 未加载时按 control 处理，并标记「未解析」以区分真实 control 分组。
