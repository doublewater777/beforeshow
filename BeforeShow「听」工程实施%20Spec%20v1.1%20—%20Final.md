# BeforeShow「听」工程实施 Spec v1.1 — Final

**基线：** `main @ e41c99c658b956de1a2405559d1eb4f185f5ecac`。当前 `main` HEAD 已重新确认未变化。

**目标平台：**

- iOS 17.0+
- Swift 6
- SwiftUI
- SwiftData
- MusicKit
- XcodeGen
- iPhone 17 Simulator 作为标准模拟器验收环境

`project.yml` 当前 deployment target 为 iOS 17.0、Swift 6、Development Team 为 `29C8MS76CZ`。

本 Spec 是实现真相。

旧 `codex/artist-warmup` 分支仅作为算法与 MusicKit 探索素材，不作为：

- 产品真相
- 架构真相
- SwiftData schema 真相
- 文件组织真相

禁止整体 cherry-pick。

---

# 1. 最终产品不变量

## 1.1 一级导航

```text
当前 / 听 / 足迹
```

「听」是一级 Tab。

---

## 1.2 Current Show

Current Show 是：

> 用户主动拥有的长期现场焦点。

时间流逝不能自动改变 Current Show。

只允许以下情况改变：

1. 用户主动选择另一场；
2. 当前 Show 被删除；
3. `selectedShowID` 已无法解析到任何 Show；
4. 从未建立过 Current Show，需要第一次初始化。

以下事件均不得自动抢 Current：

- 新增未来现场
- 新增正在进行现场
- 下一场到达当天
- 下一场开场
- 当前现场结束
- 当前现场结束超过 3 天
- 当前现场被标记 canceled / postponed / historical

只要 Show 仍存在，用户就可以主动把它设为 Current。

---

## 1.3 Current Show、通知、Widget、Live Activity 是四种不同焦点

最终关系固定为：

```text
Current Show
    = 用户选择

Listen
    = Current Show

Widget
    = Current Show

Notifications
    = 所有需要未来提醒的 Shows

Live Activity
    = 实际正在发生 / 最近即将发生的现场
```

禁止再次把它们合成一个：

```text
focusedShow
```

---

## 1.4 「听」

「听」围绕 Current Show。

开场前、现场中、散场后均可继续使用。

它不是：

- Apple Music 替代品
- 通用音乐播放器
- 任务中心
- 熟悉度游戏
- 歌词 App
- setlist 数据服务

---

## 1.5 Familiarity

一首歌曲可以因为以下正向证据被认为熟悉：

1. 用户手动确认「听过」
2. BeforeShow 内完整播放实际累计达到 50%
3. 用户在某次足迹的现场歌单回记中确认听到了这首 Apple Music catalog song

Preview 不自动产生熟悉证据。

Seek 跳过部分不计实际收听。

---

## 1.6 Wants Live

「想现场听」属于：

```text
showID + songID
```

开场前可修改。

到达该场有效开场时间后：

> 冻结为只读历史期待。

不跨现场继承。

---

# 2. 当前仓库必须保留的架构边界

当前仓库已明确分层：

```text
App
Domain
Features
Infrastructure
UI
Supporting
Shared
```

依赖方向：

```text
App -> Features -> Domain
App -> Infrastructure
Features -> Infrastructure
Features -> UI
Infrastructure -> Domain
Widget -> Shared
App -> Shared
```

`Domain` 不得 import SwiftUI/UIKit；RootView 不得承担 feature 业务 mutation、媒体 I/O 或 MusicKit orchestration。

新增源码：

> 默认 < 400 行。

约 600 行以上必须重新检查职责是否混杂。

新增/移动 Swift 文件：

```bash
cd apps/ios
xcodegen generate
```

`project.yml` 是项目结构真源。

禁止只修改 `.xcodeproj`。

---

# 3. 目标目录

```text
BeforeShow/
├── App/
│   ├── BeforeShowApp.swift
│   ├── BeforeShowTab.swift
│   ├── ModelContainerFactory.swift
│   ├── AppStartupCoordinator.swift
│   └── Migrations/
│       ├── AppPersistenceMigrationRunner.swift
│       ├── CurrentShowOwnershipMigration.swift
│       └── AppleMusicArtistIdentityMigration.swift
│
├── Domain/
│   ├── Shows/
│   │   ├── Show.swift
│   │   ├── ShowDraft.swift
│   │   ├── ShowMutationCoordinator.swift
│   │   └── ShowDeletionCoordinator.swift
│   │
│   └── Listening/
│       ├── ArtistFamiliarity.swift
│       ├── ArtistCatalogSnapshot.swift
│       ├── CatalogSong.swift
│       ├── CatalogAlbum.swift
│       ├── SongFamiliarityRecord.swift
│       ├── ShowWantsLiveSong.swift
│       ├── ShowArtistListeningPreference.swift
│       ├── ShowOpeningFamiliarityBaseline.swift
│       ├── ShowOpeningArtistTier.swift
│       ├── ShowSetlistMemory.swift
│       ├── FamiliarityEvidenceResolver.swift
│       ├── ListeningMusicContracts.swift
│       ├── ListeningQueuePolicy.swift
│       ├── ListeningEvidenceTracker.swift
│       └── WantsLiveMutationPolicy.swift
│
├── Features/
│   ├── CurrentShow/
│   │   ├── CurrentShowSelection.swift
│   │   ├── CurrentShowSelectionStore.swift
│   │   ├── CurrentShowSession.swift
│   │   ├── InitialCurrentShowPolicy.swift
│   │   ├── CurrentShowFollowUpPolicy.swift
│   │   ├── CurrentShowFeatureRootView.swift
│   │   └── CurrentShowNotificationRouteCoordinator.swift
│   │
│   ├── Listening/
│   │   ├── ListenRootView.swift
│   │   ├── ListeningSessionController.swift
│   │   ├── ListeningRepository.swift
│   │   ├── OpeningFamiliarityCoordinator.swift
│   │   ├── ListeningSongCardView.swift
│   │   ├── ListeningArtistView.swift
│   │   ├── ListeningArtistMatchSheet.swift
│   │   ├── ListeningLibraryView.swift
│   │   ├── ListeningPresentation.swift
│   │   └── ListeningDebugFixtures.swift
│   │
│   └── Footprints/
│       ├── FootprintListeningMemorySection.swift
│       └── FootprintSetlistRecallSheet.swift
│
├── Infrastructure/
│   ├── Music/
│   │   ├── AppleMusicArtistSearchService.swift
│   │   ├── MusicKitListeningCatalogService.swift
│   │   ├── MusicKitListeningPlayer.swift
│   │   └── AppleMusicPreviewPlayer.swift
│   │
│   ├── Media/
│   │   ├── AppAudioSession.swift
│   │   └── AudioPlaybackCoordinator.swift
│   │
│   ├── Notifications/
│   │   ├── NotificationSchedulingModels.swift
│   │   ├── LocalNotificationScheduler.swift
│   │   ├── NotificationPortfolioPlanner.swift
│   │   ├── NotificationPortfolioRecordStore.swift
│   │   ├── LocalNotificationCenter.swift
│   │   ├── NotificationDeepLink.swift
│   │   └── NotificationDeepLinkRouting.swift
│   │
│   └── Widgets/
│       ├── WidgetDataSync.swift
│       ├── WidgetSnapshotSync.swift
│       └── LiveActivityShowResolver.swift
```

不要重新创建：

```text
ArtistWarmup*
Warmup*
ShowArtist
ArtistInterest
ShowSongImpression
```

---

# 4. ModelContainerFactory

当前 `BeforeShowApp.swift` 内直接声明整个 ModelContainer，并且当前 architecture checker 已对 `BeforeShowApp.swift` 设置增长预算。 

因此 v1.1 强制新增：

```text
App/ModelContainerFactory.swift
```

接口：

```swift
@MainActor
enum ModelContainerFactory {
    static func make(
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer
}
```

生产配置继续：

```swift
ModelConfiguration(
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .none
)
```

测试可：

```swift
isStoredInMemoryOnly: true
```

最终注册：

```text
Show
CurrentShowSelection
NotificationSchedulingState
ShowNotificationScheduleRecord
MemoryFragment
MemoryMediaItem
ShowAsset
DynamicCover

ArtistCatalogSnapshot
CatalogSong
CatalogAlbum
SongFamiliarityRecord
ShowWantsLiveSong
ShowArtistListeningPreference
ShowOpeningFamiliarityBaseline
ShowOpeningArtistTier
ShowSetlistMemory
```

Listening 数据全部保持本地。

不得接：

- Companion CloudKit
- Widget App Group 数据模型
- 腾讯云
- server sync

---

# 5. BeforeShowApp

最终：

```text
BeforeShowApp
    ├─ 创建 ModelContainer
    ├─ 第三方 SDK bootstrap
    ├─ AppStartupCoordinator
    ├─ app-scoped ListeningSessionController
    └─ RootView
```

不得把：

- SwiftData model 注册清单
- migration 具体实现
- Current Show selection 逻辑
- MusicKit catalog
- notification portfolio
- opening snapshot 算法

继续塞进 `BeforeShowApp.swift`。

目标：

> BeforeShowApp 改完后不增加现有 architecture checker hotspot budget。

---

# 6. ArtistSlot：保留现有类型，不引入 ShowArtist

当前 `Show` 已直接保存：

```swift
var artists: [ArtistSlot]
```

并且 `ArtistSlot` 是 Codable value type。

继续使用。

新增：

```swift
struct ArtistSlot: Codable, Hashable, Equatable {
    var name: String
    var avatarURL: String?
    var appleMusicURL: String?
    var appleMusicArtistID: String?
    var albumArtworkURL: String?
}
```

`appleMusicArtistID` 必须 optional，保证现有数据可轻量读取。

---

# 7. ArtistSlot dirty tracking

`Show.artists` 是 value array。

任何 migration / mutation 不允许：

```swift
show.artists[index].appleMusicArtistID = ...
```

然后假定 SwiftData 一定正确检测嵌套 struct 修改。

统一使用：

```swift
var artists = show.artists
artists[index].appleMusicArtistID = resolvedID
show.artists = artists
```

所有 `[ArtistSlot]` 修改都遵守：

> copy → mutate → reassign。

---

# 8. Show.normalizedArtistSlots / Show.apply

`normalizedArtistSlots` 必须保留：

```text
name
avatarURL
appleMusicURL
appleMusicArtistID
albumArtworkURL
```

修改艺人名字时，现有代码已经会清旧识别资料；新增 ID 后必须一起清：

```text
avatarURL
appleMusicURL
appleMusicArtistID
albumArtworkURL
```

名字不变：

> 保留全部识别字段。

---

# 9. Add Show 艺人候选

当前 `RecognizedArtist.id` 已经是 iTunes catalog artist ID，而且现有 `AppleMusicArtistSearchService` 使用公开 iTunes Search API。

**保留这个服务。**

不要为了「听」重写 Add Show 的搜索为 MusicKit。

用户在 Add Show 明确选择艺人候选时保存：

```text
ArtistSlot.name
ArtistSlot.avatarURL
ArtistSlot.appleMusicURL
ArtistSlot.appleMusicArtistID = RecognizedArtist.id
```

这样进入「听」时无需二次确认。

---

# 10. AppleMusicArtistIdentityMigration

用于开发期已有数据 repair。

条件：

```text
appleMusicArtistID == nil
AND
appleMusicURL != nil
```

只允许从标准 Apple Music URL 的 artist path ID 提取。

成功：

```text
appleMusicArtistID = parsedID
```

失败：

> nil。

禁止：

- 按名字自动搜索并绑定
- 自动确认同名艺人
- avatar 猜身份

必须幂等。

---

# 11. SwiftData 数组字段规则

当前 main 已实际使用：

```text
[ArtistSlot]
[String]
[UUID]?
```

作为 SwiftData 属性，例如 `Show.artists` 和 `NotificationSchedulingState.backfillMintedShowIDs`。 

因此 v1.1 允许：

```text
[String]
```

用于：

- ArtistCatalogSnapshot.orderedSongIDs
- ArtistCatalogSnapshot.topSongIDs
- ArtistCatalogSnapshot.albumIDs
- CatalogAlbum.orderedTrackIDs
- CatalogSong.performerArtistIDs
- CatalogSong.performerArtistNames
- ShowOpeningFamiliarityBaseline.familiarSongIDsAtCapture

规则：

> 所有数组更新均重新赋整个数组。

禁止依赖 nested collection 的隐式 dirty tracking。

---

# 12. 所有 unique model 的统一事务规则

main 已使用：

```swift
@Attribute(.unique)
var uniqueKey: String
```

例如 `ShowAsset`。

v1.1 继续沿用这种已经在仓库中运行的方式。

**禁止 blind insert。**

任何 unique model：

```text
先 fetch
↓
有记录
    → mutate existing
无记录
    → insert
↓
save
```

不得：

```swift
context.insert(Model(uniqueKey: key))
```

然后依赖 SwiftData `.unique` 自动 upsert。

---

# 13. Unique 表

| Model | Unique |
|---|---|
| ArtistCatalogSnapshot | artistID |
| CatalogSong | appleMusicSongID |
| CatalogAlbum | appleMusicAlbumID |
| SongFamiliarityRecord | songID |
| ShowWantsLiveSong | `showID|songID` |
| ShowArtistListeningPreference | `showID|artistID` |
| ShowOpeningFamiliarityBaseline | showID |
| ShowOpeningArtistTier | `showID|artistID` |

Composite key 模型必须提供：

```swift
static func makeUniqueKey(...)
```

以及测试。

---

# 14. ArtistCatalogSnapshot

```swift
@Model
final class ArtistCatalogSnapshot {
    @Attribute(.unique)
    private(set) var artistID: String

    var artistName: String
    var artworkURL: String?
    var editorialText: String?
    var genreNames: [String]

    var orderedSongIDs: [String]
    var topSongIDs: [String]
    var albumIDs: [String]

    var fetchedAt: Date
}
```

这个模型只表示：

> 最后一次完整成功的 catalog denominator。

不保存：

```text
loading
partial
failed
```

---

# 15. CatalogSong

```swift
@Model
final class CatalogSong {
    @Attribute(.unique)
    private(set) var appleMusicSongID: String

    var title: String
    var artistName: String

    var albumID: String?
    var albumTitle: String?

    var artworkURL: String?
    var duration: TimeInterval?

    var performerArtistIDs: [String]
    var performerArtistNames: [String]

    var previewURL: String?
    var updatedAt: Date
}
```

CatalogSong：

> 全局 cache。

不带 showID。

---

# 16. CatalogAlbum

```swift
@Model
final class CatalogAlbum {
    @Attribute(.unique)
    private(set) var appleMusicAlbumID: String

    var title: String
    var artworkURL: String?
    var releaseDate: Date?

    var artistIDs: [String]
    var orderedTrackIDs: [String]

    var updatedAt: Date
}
```

---

# 17. SongFamiliarityRecord：证据不能互相覆盖

不要再使用一个：

```text
sourceRawValue
```

表示唯一来源。

否则：

```text
manual
→ actual
→ undo
```

会丢真实 evidence。

最终模型：

```swift
@Model
final class SongFamiliarityRecord {
    @Attribute(.unique)
    private(set) var songID: String

    var manualConfirmedAt: Date?
    var actualListeningAt: Date?
    var updatedAt: Date
}
```

`showRecall` 不复制到这个 row。

现场听到证据由：

```text
ShowSetlistMemory.catalogSongID
```

自身承担。

---

# 18. FamiliarityEvidenceResolver

最终熟悉判断：

```text
manualConfirmedAt != nil

OR

actualListeningAt != nil

OR

存在任意 ShowSetlistMemory.catalogSongID == songID
```

即：

```swift
isFamiliar(songID)
```

由统一的：

```text
FamiliarityEvidenceResolver
```

计算。

`familiarSince`：

取三类当前仍存在正向 evidence 的最早时间：

- manualConfirmedAt
- actualListeningAt
- earliest ShowSetlistMemory.createdAt

不额外持久化。

---

# 19. 手动「听过」

执行前：

> 必须先 capture 所有到期开场 baseline。

之后 fetch：

```text
SongFamiliarityRecord(songID)
```

有：

```text
manualConfirmedAt = now
```

无：

> insert 一条。

如果 already manual：

> no-op。

---

# 20. 真实 50% Evidence 升级

达到实际 50% 时：

先 capture due opening baselines。

然后 fetch existing。

已有 manual：

```text
manualConfirmedAt 保留
actualListeningAt = now
```

已有 actual：

> no-op。

没有：

> insert actual evidence。

因此：

```text
manual → actual
```

是 evidence 升级，不是覆盖。

---

# 21. Undo

v1.1 中「撤销听过」严格解释为：

> 撤销用户自己的手动确认。

操作：

```text
manualConfirmedAt = nil
```

然后重新检查正向 evidence。

如果：

```text
actualListeningAt == nil
AND
没有任何 ShowSetlistMemory(songID)
```

可以删除 SongFamiliarityRecord。

否则：

> 仍保持 familiar。

因此必须成立：

```text
manual → undo
    => unfamiliar

manual → actual → undo
    => familiar

manual → showRecall → undo
    => familiar
```

不得通过 Undo 删除：

- actualListening evidence
- setlist recall

---

# 22. ShowWantsLiveSong

```swift
@Model
final class ShowWantsLiveSong {
    @Attribute(.unique)
    private(set) var uniqueKey: String

    var showID: UUID
    var songID: String
    var createdAt: Date
}
```

unique：

```text
showID|songID
```

不保存：

```text
note
hasFeeling
rating
```

---

# 23. ShowArtistListeningPreference

```swift
@Model
final class ShowArtistListeningPreference {
    @Attribute(.unique)
    private(set) var uniqueKey: String

    var showID: UUID
    var artistID: String
    var isExcluded: Bool
    var updatedAt: Date
}
```

仅表示：

> 当前这场“不听这位”。

推荐恢复时直接删除 row。

默认无 row：

```text
isExcluded = false
```

---

# 24. ShowOpeningFamiliarityBaseline

用于解决：

> 开场时 catalog 尚未完整，之后无法恢复当时 numerator。

模型：

```swift
@Model
final class ShowOpeningFamiliarityBaseline {
    @Attribute(.unique)
    private(set) var showIDKey: String

    var showID: UUID

    var effectiveStartAtCapture: Date
    var familiarSongIDsAtCapture: [String]

    var capturedAt: Date
}
```

`showIDKey`：

```text
showID.uuidString
```

baseline 的语义：

> 在这场有效开场时刻已经成立的熟悉歌曲集合。

---

# 25. 为什么 baseline 保存 song IDs

如果只保存：

```text
capture timestamp
```

未来用户：

- 撤销手动 familiar
- 删除 setlist recall
- 修改证据

都可能重写过去。

因此必须冻结：

```text
familiarSongIDsAtCapture
```

而不是未来重新读取当前 familiarity。

---

# 26. Baseline capture 时机

任何会改变 familiarity 的 mutation **之前**：

```text
manual mark heard
manual undo
actual 50%
add catalog setlist recall
delete catalog setlist recall
```

统一先调用：

```text
OpeningFamiliarityCoordinator.captureDueBaselines(
    in: modelContext,
    now: now
)
```

不是只捕获 Current Show。

必须扫描：

> 所有到期开场、尚无 baseline 的 eligible shows。

原因：

Current Show 可能仍停留在旧现场 A，但真正的未来现场 B 已经开场。

用户继续听 A 时产生的新 familiarity：

> 不允许污染 B 的 opening baseline。

---

# 27. Baseline eligibility

满足：

```text
wasAddedAsHistorical != true
changeStatus != canceled
存在 effectiveStartTime
now >= effectiveStartTime
尚无 baseline
```

即可 capture。

**不要求：**

- 已连接 artist
- 已有 catalog
- 当前是 Current Show

因此即使艺人稍后才连接，也还能恢复 opening tier。

---

# 28. App launch / foreground baseline

还必须在：

```text
cold launch
scenePhase -> active
```

执行：

```text
captureDueBaselines
```

但所有 familiarity mutation 前仍必须再次调用。

后者是 correctness boundary，不能只靠 scene lifecycle。

---

# 29. ShowOpeningArtistTier

```swift
@Model
final class ShowOpeningArtistTier {
    @Attribute(.unique)
    private(set) var uniqueKey: String

    var showID: UUID
    var artistID: String
    var artistNameAtCapture: String

    var tierRawValue: String

    var baselineCapturedAt: Date
    var catalogSnapshotFetchedAt: Date

    var resolvedAt: Date
}
```

unique：

```text
showID|artistID
```

不保存：

- heardSongCount
- totalSongCount
- percentage

---

# 30. Opening tier 延迟解析

条件：

```text
有 ShowOpeningFamiliarityBaseline
+
有该 artist 的 complete ArtistCatalogSnapshot
+
还没有 ShowOpeningArtistTier
```

计算：

```text
baseline.familiarSongIDsAtCapture
∩
snapshot.orderedSongIDs
```

得到 numerator。

denominator：

```text
snapshot.orderedSongIDs.count
```

然后保存 tier。

因此：

```text
20:00 开场，无 catalog
20:10 用户继续听
21:00 catalog 第一次完整拉回
```

21:00 计算 tier 时：

> 必须使用 20:00 baseline，不得包含 20:10 新听到的歌曲。

---

# 31. Opening baseline 生命周期失效

Show schedule/status mutation 后执行：

```text
OpeningFamiliarityInvalidationPolicy
```

以下情况删除该 Show 的 baseline + opening tiers：

### canceled

全部删除。

### postponed-undated

全部删除。

### 已 capture 后被延期到未来

如果：

```text
newEffectiveStart > baseline.capturedAt
```

说明旧 baseline 已失效。

删除，等待新开场。

### 已 capture 后只修正到另一个过去时间

如果：

```text
newEffectiveStart <= baseline.capturedAt
```

不尝试伪造历史重算。

保留已有 baseline/tier。

---

# 32. Artist rematch 与 opening tier

如果某 Show 的 artist ID 从：

```text
oldArtistID
→
newArtistID
```

则：

- 删除该 Show + oldArtistID 的 exclusion
- 删除该 Show + oldArtistID 的 opening tier
- baseline 不删除
- 等 new artist complete catalog 后
- 使用原 opening baseline 为 new artist 重新 resolve

---

# 33. Familiarity tier

持久化 raw values 固定：

```text
firstEncounter
newListener
gettingIntoIt
familiar
deepListener
```

不要用中文 label 作为 persistence value。

边界：

```text
0%       firstEncounter
1–24%    newListener
25–49%   gettingIntoIt
50–74%   familiar
75–100%  deepListener
```

UI label 本地化。

不设计 100% completion badge。

---

# 34. CurrentShowSelectionStore

新增唯一访问 seam：

```text
Features/CurrentShow/CurrentShowSelectionStore.swift
```

所有 Current Show read/write 均必须经过它。

接口至少：

```swift
@MainActor
final class CurrentShowSelectionStore {
    func canonicalSelection() throws -> CurrentShowSelection?
    func select(showID: UUID) throws
    func clear() throws
    func bootstrapIfNeeded(shows: [Show], now: Date) throws
    func normalizeDuplicates() throws
}
```

---

# 35. CurrentShowSelection singleton normalization

当前模型本身没有 singleton unique constraint。

如果存在多 row：

排序：

```text
updatedAt descending
↓
id.uuidString ascending
```

第一条为 canonical。

其余：

> 同一个 ModelContext transaction 删除。

不得再使用：

```swift
selections.first
```

直接决定 Current Show。

---

# 36. CurrentShowSession

重构为：

> 解析已经持久化的用户 selection。

逻辑：

```text
selection.selectedShowID
↓
找到 Show
    → 返回 Show
找不到
    → nil
```

不再：

- 看 retention days
- 自动跳下一场
- 判断 ended 是否可选
- 判断 canceled 是否可选

---

# 37. 删除旧 CurrentShowSelector runtime 语义

现有 `CurrentShowSelector` 包含：

- automatic selection
- retention
- manual eligibility
- auto/live ranking。

这些 runtime 行为全部退出生产路径。

如果 migration 需要模拟升级前“用户当时看到哪场”：

> 仅在 `CurrentShowOwnershipMigration.swift` 内保留 private `LegacyCurrentShowSelectionResolver`。

生产代码不得调用。

---

# 38. InitialCurrentShowPolicy

只在没有 Current Show 时使用。

排序：

1. 当前实际 live 的有效 show
2. 最近未来 dated scheduled/postponed show
3. 尚未 confirmed ended 的最近 show
4. nil

默认不自动 bootstrap：

- canceled
- historical
- postponed-undated
- confirmed ended

但用户之后可以主动选。

---

# 39. CurrentShowOwnershipMigration

这是开发期数据 repair。

算法：

1. fetch all CurrentShowSelection
2. 确定 deterministic canonical row
3. 如果旧 row `isManual == false`
   - 用 `LegacyCurrentShowSelectionResolver` 计算升级前此刻真正会展示的 show
4. 如果旧 row `isManual == true`
   - 优先保留其 selectedShowID，只要 Show 仍存在
5. 删除重复 rows
6. 最终 canonical：
   - `selectedShowID = resolved`
   - `isManual = true`
7. 无有效 show：
   - 用 InitialCurrentShowPolicy bootstrap
8. save

必须可重复执行而结果不变化。

---

# 40. AppPersistenceMigrationRunner

新增唯一 startup migration runner：

```swift
@MainActor
enum AppPersistenceMigrationRunner {
    static func run(in context: ModelContext)
}
```

顺序：

```text
1. ShowCreationOriginMigration
2. CurrentShowOwnershipMigration
3. AppleMusicArtistIdentityMigration
4. legacy notification focusedShowID 清空/失效化
```

不使用复杂 `VersionedSchema`。

原因：

仓库 AGENTS 明确：

> App 尚未上线，不需要为了不存在的生产版本建立复杂兼容层。

---

# 41. Migration runner 调用位置

只允许一个 startup lifecycle seam 调：

```text
AppStartupCoordinator
```

禁止重新出现：

```text
.onAppear -> migration
.task -> migration
```

两套 startup migration 调用。

现有 `ShowCreationOriginMigration.resolveUnresolvedOrigins(...)` 在 Companion import mutation 前的 defensive guard：

> 保留。

它属于业务 invariant，不算第二套 startup runner。当前 migration 本身已经说明该 guard 是为了避免 CloudKit acceptance race。

---

# 42. Add Show 不再抢 Current

已有 Current：

```text
add future → 不切
add live   → 不切
add past   → 不切
```

没有 Current：

```text
add future → 可以 bootstrap 为 Current
add live   → 可以 bootstrap 为 Current
add past   → 不自动 Current
```

成功文案不能在没有实际切 Current 时显示：

> 已设为当前现场。

---

# 43. 手动选择 Current

`CurrentShowLibraryManagementView`：

只要：

```text
show.id != currentShow.id
```

即可：

> 设为当前。

包括：

- ended
- historical
- canceled
- postponed-undated

---

# 44. 删除 Current

如果删除的是 Current：

```text
clear selectedShowID
↓
InitialCurrentShowPolicy(remaining shows)
↓
有候选
    → persist candidate
无候选
    → nil
```

这是 Current Show 唯一允许的系统 fallback 切换。

---

# 45. 下一场 suggestion

`CurrentShowFollowUpPolicy` 只计算：

```text
suggestedNextShow
```

不写 CurrentShowSelection。

UI：

```text
下一场 · 9 月 12 日
切到下一场
```

用户点击后才：

```text
selectionStore.select(showID:)
```

---

# 46. 通知：彻底取消单焦点架构

当前 main：

```text
LocalNotificationCenter.applyFocusChange(to: Show?)
reconcileFocus(to: Show?)
```

会取消旧记录并只为单个 show 排自然节点。

v1.1 删除这个业务模型。

不存在：

```text
notificationShow
NotificationFocusPolicy
single notification focus
```

---

# 47. NotificationSchedulingState

当前字段：

```text
focusedShowID
hasRequestedPermissionAfterFirstShow
backfillMintedShowIDs
```

v1.1：

```text
focusedShowID
```

仅为开发数据轻量兼容暂留。

运行时：

> 永远不读取它决定通知。

migration runner 可把它清 nil。

保留：

```text
hasRequestedPermissionAfterFirstShow
backfillMintedShowIDs
```

---

# 48. NotificationPortfolioPlanner

新增纯 planner：

```text
Infrastructure/Notifications/NotificationPortfolioPlanner.swift
```

输入：

```text
all Shows
existing schedule records
scheduling state
reconcile reason
now
```

输出：

```text
desired ScheduledShowNotification[]
```

---

# 49. 多场自然通知

所有以下 Show 都独立进入 portfolio：

```text
日期明确
非 canceled
非 historical
有未来 notification milestone
```

每场调用已有：

```text
LocalNotificationScheduler.futureRequests(for:)
```

现有 scheduler 继续负责：

- 14 days
- 7 days
- 3 days
- 1 day
- show day morning
- show day
- opening memory
- after show

`LocalNotificationScheduler.planFocusChange`：

> 删除。

`futureRequests(for:)` 等单场纯函数继续保留。

---

# 50. confirmed ended 的 afterShow

已 `endedAt != nil` 的 show：

如果次日 afterShow fireDate 仍在未来：

> 继续进入 portfolio。

不依赖 Current Show。

---

# 51. Backfill

Backfill 只在：

```text
NotificationReconcileReason.showAdded(showID)
```

时允许第一次 mint。

不是 Current 才 mint。

每个 show：

> 最多 mint 一次。

继续使用：

```text
backfillMintedShowIDs
```

但数组 mutation 必须：

```text
copy
mutate
reassign
```

Foreground/reconcile 不重新 mint。

---

# 52. Notification portfolio 容量

应用自身最多维护：

```text
56
```

条普通 Show lifecycle pending requests。

保留额外余量给：

- Weather reminder replacement
- 未来 App 其他系统通知
- 平台自身限制

候选超过 56：

```text
按 fireDate 升序
↓
同 fireDate 时按 milestone urgency
↓
取前 56
```

当请求触发、取消或现场修改后：

> 下次 reconcile 自动补入后面的请求。

不得一次性把任意数量的未来 show 全塞进 UNUserNotificationCenter。

---

# 53. NotificationPortfolioRecordStore

`ShowNotificationScheduleRecord` 当前没有 unique constraint。

新增：

```text
NotificationPortfolioRecordStore
```

以：

```text
requestIdentifier
```

作为业务唯一键。

每次 reconcile 先 normalize：

如果多个 record 具有相同 requestIdentifier：

1. 保留与 desired fireDate 最匹配者
2. 否则 createdAt 最新
3. 删除其余

禁止继续累积重复 rows。

---

# 54. Notification reconcile diff

`LocalNotificationCenter` 新主入口：

```swift
func reconcilePortfolio(
    shows: [Show],
    reason: NotificationReconcileReason,
    in context: ModelContext,
    now: Date
) async -> Bool
```

流程：

```text
1. 清理已触发 backfill records
2. normalize duplicate records
3. planner 得出 desired <= 56
4. 查询 UNUserNotificationCenter pending identifiers
5. 对比 existing/desired/system
6. missing → schedule
7. changed → replace same identifier
8. stale → cancel
9. mutate records in place
10. save
11. WeatherReminderScheduler.scheduleNextBackgroundCheck
```

不得：

```text
cancel all
→ recreate all
```

---

# 55. Notification reconcile 触发点

以下都 reconcile **整个 portfolio**：

- cold launch
- foreground
- add show
- edit show
- postpone
- cancel
- mark ended
- delete show
- notification settings refresh
- Current Show 用户切换

注意：

> Current Show 切换触发 reconcile 只是为了保持系统一致，不会改变 desired portfolio。

---

# 56. Notification deep link ownership

当前 main：

```text
RootView -> 切到 current tab
CurrentShowManagementView -> consume
```

而 `CurrentShowManagementView` 对非当前 show 直接 consume 丢弃。

v1.1：

> `CurrentShowManagementView` 删除 notification deep-link ownership。

---

# 57. CurrentShowFeatureRootView

新增：

```text
Features/CurrentShow/CurrentShowFeatureRootView.swift
```

负责 Current Show feature 的：

- NavigationStack
- notification target route
- normal current home

RootView 只：

```text
选 .current tab
```

---

# 58. CurrentShowNotificationRouteCoordinator

收到：

```text
NotificationDeepLink(showID, destination)
```

流程：

```text
fetch target Show by showID
↓
不存在
    → consume
存在
    → 构造 typed destination
    → destination 成功提交给 navigation owner
    → consume
```

不得修改：

```text
CurrentShowSelection
```

---

# 59. 非 Current notification route

如果 notification show != Current：

```text
.home
→ ShowDetailView(targetShow)

.memoryFragments
→ MemoryFragmentsView(show: targetShow)

.memoryCreate
→ targetShow 的统一 Memory editor/create route
```

`MemoryFragmentsView` 已经接受显式 Show，因此不要求它成为 Current。

---

# 60. Widget

Widget 永远使用：

```text
CurrentShowSelectionStore
→ Current Show
```

不使用：

- nearest show
- Notification portfolio
- Live Activity resolver

---

# 61. Live Activity

Live Activity 使用独立：

```text
LiveActivityShowResolver
```

排序：

### 第一优先

如果 Current Show 本身正在实际 live：

> 使用 Current。

### 第二优先

所有实际 live show 中：

> 选择有效 start 最接近 now 的一场。

### 第三优先

最近未来 dated scheduled / dated-postponed show。

排除：

- canceled
- historical
- postponed-undated
- confirmed ended

---

# 62. Widget / Live Activity snapshot 分离

当前 `WidgetDataSync` 用一个 `snapshot` 同时喂 Widget 和 `ShowLiveActivityController`。

v1.1 必须变成：

```text
widgetShow
→ WidgetShowSnapshot
→ WidgetSnapshotSync

liveActivityShow
→ WidgetShowSnapshot/value snapshot
→ ShowLiveActivityController
```

禁止共享“同一 show snapshot”。

---

# 63. Widget / Live Activity cover cache

当前 `ShowLiveActivityController` 会：

```text
pruneCovers(except: source)
```

在 Widget 与 Live Activity 使用不同现场后，这会把另一方需要的封面删掉。

因此同步修改：

```text
WidgetCoverCache.pruneCovers(
    keepingSources: Set<URL/String>
)
```

一次 sync 得出：

```text
widgetCoverSource
liveActivityCoverSource
```

保留二者 union。

禁止：

> Widget 和 Live Activity 各自独立 prune 单个封面。

---

# 64. 目标焦点验收示例

```text
A = 上周已经结束，用户仍设 Current
B = 明天演出
C = 三天后演出
```

必须：

```text
Current Show  -> A
Listen        -> A
Widget        -> A

Notifications
    -> B 的未来节点
    -> C 的未来节点

Live Activity -> B
```

---

# 65. 单场删除 Listening cascade

Listening 第一版：

> 不建立 Show ↔ Listening model SwiftData cascade relationship。

show-scoped model 均用显式：

```text
showID
```

理由：

当前 `ShowDeletionCoordinator` 已明确避免：

> SwiftData cascade + 手动删除 child

同时操作同一 graph。

---

# 66. ListeningShowDataCleaner

删除某个 Show 前删除：

```text
ShowWantsLiveSong
ShowArtistListeningPreference
ShowOpeningFamiliarityBaseline
ShowOpeningArtistTier
ShowSetlistMemory
```

不得删除：

```text
SongFamiliarityRecord
CatalogSong
CatalogAlbum
ArtistCatalogSnapshot
```

全部在同一个 ModelContext 业务 transaction 中完成。

---

# 67. Debug seeder

仓库 DEBUG seeder 也存在直接：

```swift
modelContext.delete(show)
```

路径。

所有 Debug Show 删除也必须先：

```text
ListeningShowDataCleaner
```

否则 DEBUG fixture 会制造 orphan listening rows。

---

# 68. 全量「清除本地数据」

当前 `PrivacyLocalDataView` 按 Model 类型显式删除，而且 `LocalDataInventory` 目前完全不知道 Listening 数据。 

v1.1 必须同步修改。

全量清除新增：

```text
ArtistCatalogSnapshot
CatalogSong
CatalogAlbum
SongFamiliarityRecord
ShowWantsLiveSong
ShowArtistListeningPreference
ShowOpeningFamiliarityBaseline
ShowOpeningArtistTier
ShowSetlistMemory
```

清除后：

> 不允许保留任何「听」私有数据。

---

# 69. LocalDataInventory

增加：

```text
familiarSongCount
wantsLiveCount
setlistMemoryCount
listeningCatalogItemCount
```

`isEmpty` 必须包含 Listening data。

Settings 可聚合显示为：

> 音乐与熟悉记录

无需展示每种内部 model。

---

# 70. MusicKit 使用边界

MusicKit 当前官方文档确认：

- 使用前需要 `NSAppleMusicUsageDescription`
- 使用 `MusicAuthorization`
- `MusicSubscription.canPlayCatalogContent` 判断 catalog playback 能力
- `MusicCatalogSearchRequest` / `MusicCatalogResourceRequest` 获取 catalog
- `ApplicationMusicPlayer` 是 app 独立播放器。

`ApplicationMusicPlayer` 不改变 Music App 自身状态。

当前 deployment target iOS 17.0 不需要为了本功能提高。

禁止提高最低系统版本以“解决”MusicKit API 问题。

---

# 71. Apple Music usage description

现有 Info.plist 已有 key，但现有语义只用于识别艺人。

修改为：

简中：

> 用于确认现场艺人，并通过 Apple Music 浏览和播放与现场相关的音乐。

繁中：

> 用於確認現場藝人，並透過 Apple Music 瀏覽和播放與現場相關的音樂。

英文：

> Used to identify artists for your shows and browse or play related music through Apple Music.

必须同步：

```text
zh-Hans.lproj/InfoPlist.strings
zh-Hant.lproj/InfoPlist.strings
en.lproj/InfoPlist.strings
```

Apple 明确要求缺少 usage description 时访问 MusicKit 可能导致 App 被系统终止。

---

# 72. MusicKit contracts

Domain：

```text
ListeningMusicContracts.swift
```

定义纯值：

```swift
struct ListeningArtistProfile
struct ListeningCatalogSong
struct ListeningCatalogAlbum
struct ListeningArtistCatalogResult

enum ListeningCatalogCompleteness {
    case complete
    case partial
}

enum ListeningAuthorizationState
enum ListeningPlaybackCapability
enum ListeningPlaybackStatus

struct ListeningPlaybackSnapshot
```

协议：

```swift
protocol ListeningCatalogProviding
protocol ListeningPlaying
protocol ListeningPreviewPlaying
```

SwiftUI View：

> 不 import MusicKit。

---

# 73. Artist matching 保持现有 iTunes Search

现有 `AppleMusicArtistSearchService`：

- 已是 Infrastructure/Music
- 返回稳定 catalog artist id
- 不需要 Apple Music 用户授权。

继续复用。

MusicKit 新职责只负责：

> 已确认 artist ID 后的 catalog 与 playback。

---

# 74. MusicKitListeningCatalogService

输入：

```text
appleMusicArtistID
```

负责：

- Artist metadata
- topSongs
- fullAlbums / albums
- singles
- compilationAlbums
- album tracks
- Song hydration
- artwork
- editorial notes
- genreNames
- previewAssets

Apple 当前 Artist API 提供 top songs、albums、fullAlbums、singles、compilationAlbums、editorial notes、genreNames 等关系。

---

# 75. Catalog 范围

第一版：

```text
topSongs
fullAlbums（SDK/关系可用）
    fallback albums
singles
compilationAlbums
```

不枚举：

```text
appearsOnAlbums
playlists
featuredPlaylists
musicVideos
```

如果某个 MusicKit relationship 在 iOS 17 SDK availability 上无法直接使用：

> fallback 到已可用关系。

不得提高 deployment target。

---

# 76. Compilation 过滤

Compilation album 的 tracks：

只有当 Song 的 performer artist IDs 包含目标 artistID 时才纳入。

MusicKit Song 提供 associated artists。

---

# 77. Catalog 排序

```text
topSongs
↓
full album tracks / albums tracks
↓
single tracks
↓
compilation tracks
```

每个来源保持 Apple Music 原顺序。

按：

```text
songID
```

第一次出现去重。

---

# 78. Catalog complete

只有：

- 所有目标 relationship page 成功完成
- 所有纳入 album track page 成功完成

才：

```text
.complete
```

任何需要页面失败：

```text
.partial
```

---

# 79. Last-good snapshot

Partial：

- 可把已拿到的 CatalogSong 写入全局 cache
- 可以暂时参加本次 runtime listening stream
- **不得更新 ArtistCatalogSnapshot denominator**

Complete：

fetch existing snapshot。

有：

> mutate in place。

无：

> insert。

不得：

```text
delete old snapshot
insert new snapshot
```

---

# 80. Catalog refresh

有 complete snapshot：

> 立即显示缓存。

如果：

```text
now - fetchedAt >= 24h
```

后台刷新。

无 snapshot：

> 首批拿到歌曲即可开始 runtime flow。

完整 catalog 继续加载。

---

# 81. 热门

艺人页「热门」只来自：

```text
ArtistCatalogSnapshot.topSongIDs
```

没有 topSongs：

> 隐藏热门。

BeforeShow 不自行推 popularity。

---

# 82. Playback capability

最终：

```text
fullPlayback
previewOnly
metadataOnly
unavailable
```

### fullPlayback

授权正常 + `canPlayCatalogContent` + song 可播放。

### previewOnly

无 full playback，但 `previewAssets` 有 URL。

Song 当前正式提供 preview assets。

### metadataOnly

只展示 metadata。

### unavailable

没有可用 metadata/cache。

---

# 83. MusicKitListeningPlayer

使用：

```text
ApplicationMusicPlayer.shared
```

不要 `SystemMusicPlayer`。

Apple 明确说明 ApplicationMusicPlayer 不修改 Music App 状态。

接口：

```text
load(songID)
play
pause
stop
seek(to:)
snapshot
```

`playbackTime` 当前可读写，可用于 seek。

任何读取：

```text
playbackTime
```

必须 guard：

```text
isFinite
!isNaN
```

---

# 84. App-owned visual queue

歌曲卡片顺序由：

```text
ListeningQueuePolicy
```

拥有。

MusicKit queue 不是产品 queue 的真相。

这样避免：

```text
视觉卡片 = B
系统 queue 仍在 A
```

---

# 85. Background playback 范围

v1.1 中：

> fullPlayback 当前正在播放的歌曲允许进入后台继续。

不承诺 app 被 suspend 后自动装载下一张新的 BeforeShow 卡片。

因此播放器可以以当前歌曲为核心加载。

如果 app 在前台：

> natural end → controller advance → 下一张自动播放。

如果 app 已后台：

> 当前 full song 可以继续至结束；进入下一张无需强行依赖 suspended app 执行新业务代码。

回来前台后 controller reconcile 状态，再决定 advance。

Apple 明确说明启用 background audio mode 后 ApplicationMusicPlayer 可在 app 后台继续当前播放项。

---

# 86. Info.plist background mode

当前 `UIBackgroundModes` 没有 audio。

加入：

```text
audio
```

保留现有：

```text
fetch
processing
```

---

# 87. Preview player

使用：

```text
AVPlayer
```

播放：

```text
PreviewAsset.url
```

支持：

- play
- pause
- seek
- progress
- natural end
- error

Preview：

> 永远不进入 automatic 50% familiarity。

---

# 88. AudioPlaybackCoordinator

当前 `AppAudioSession` 只是两个直接切 category 的 static 方法。

避免继续增大其 architecture hotspot。

保持：

```text
AppAudioSession
```

只负责底层：

```text
configureAmbient
configureSoundPlayback
```

新增：

```text
AudioPlaybackCoordinator.swift
```

---

# 89. Audio owner

```swift
enum AudioPlaybackOwner: Hashable {
    case listening
    case memoryReview
    case dynamicCover
}
```

Coordinator：

```text
acquire(owner)
release(owner)
```

任一 owner active：

```text
.playback
```

全部 release：

```text
.ambient + mixWithOthers
```

Memory Review / Dynamic Cover 逐步改为使用这个 owner seam。

不得各自直接抢 AVAudioSession category。

---

# 90. Listen tab / scene 状态机

必须严格实现以下事件，而不是简单：

```text
selectedTab == listen && sceneIsActive
```

---

## `.tabBecameHidden`

Full：

```text
pause
pausedByTabExit = true
release listening audio owner
```

Preview：

同样 pause。

---

## `.sceneBecameBackground`

如果：

```text
listenTabVisible
AND fullPlayback
AND 正在播放
```

则：

> 不 pause。

继续持有 listening audio owner。

Preview：

```text
pause
pausedByScene = true
```

---

## `.sceneBecameActive`

Full：

> 不主动改变当前 playback state。

Preview：

只有：

```text
pausedByScene
AND listenTabVisible
AND !userPaused
```

才恢复。

---

## `.tabBecameVisible`

只有：

```text
pausedByTabExit
AND !userPaused
```

才恢复。

然后：

```text
pausedByTabExit = false
```

---

## 用户主动 Pause

```text
userPaused = true
```

之后：

- 切 tab 回来
- foreground
- UI rebuild

都不能偷偷 resume。

---

# 91. Current Show 切换时

无论前后台：

```text
stop old playback
clear evidence baseline
scope = wholeShow
clear runtime queue
load new show
```

如果 Listen tab visible：

> 新 show ready 后开始播放。

---

# 92. ListeningEvidenceTracker

Sample：

```swift
struct ListeningPlaybackSample {
    let songID: String?
    let playbackPosition: TimeInterval
    let duration: TimeInterval?
    let isPlaying: Bool
    let isFullPlayback: Bool
    let monotonicUptime: TimeInterval
}
```

时间源：

```text
ProcessInfo.processInfo.systemUptime
```

不得用 Date wall-clock 差值计算连续收听。

---

# 93. Evidence 累计

只有：

```text
same song
isPlaying
isFullPlayback
```

累计。

```text
positionDelta = currentPosition - previousPosition
elapsed = currentUptime - previousUptime
```

### positionDelta < 0

向后 seek：

> 本段不计；重设 baseline。

### positionDelta > elapsed + 0.75s

视为向前 seek：

```text
acceptedDelta = min(positionDelta, elapsed)
```

### normal

```text
acceptedDelta = positionDelta
```

---

# 94. 50% threshold

```text
required = duration * 0.5
```

达到：

> 只触发一次 `actualListeningAt` evidence。

49%：

> 不触发。

50%：

> 触发。

---

# 95. Pause / interruption

遇到：

- pause
- buffering / non-playing
- audio interruption
- song change
- preview mode

重置连续 sample baseline。

同一歌已经累计的有效秒数：

> 保留到该 song playback session 结束。

---

# 96. Queue policy

单艺人：

```text
Apple Music ordered songs
↓ stable partition
未熟悉
↓
已熟悉
```

两个分组内部：

> 原顺序不变。

---

# 97. Multi-artist queue

参与艺人：

```text
appleMusicArtistID != nil
AND
not excluded
```

按 Show.artists 原顺序 round-robin：

```text
A1
B1
C1
A2
B2
C2
...
```

艺人提前耗尽：

> 跳过 lane。

---

# 98. Whole-show song dedupe

同一 Apple Music songID：

> 整场 queue 只出现一次。

第一位贡献它的 Show Artist：

> 作为卡片当前 artist context。

Familiarity 本来就是 song global，因此合作歌只需 familiar 一次。

---

# 99. Swipe

```text
上滑 -> next
下滑 -> previous
```

永远不写：

- skip
- dislike
- notHeard
- negative preference
- recommendation score

---

# 100. 队列末尾

不增加用户可见「循环模式」。

如果非空 queue 到尾：

> 可以内部 wrap 到第一首继续。

这只是连续体验，不形成：

- loop toggle
- reunion mode
- repeat setting

---

# 101. Wants Live mutation policy

### 可修改

```text
scheduled before effectiveStart
dated-postponed before new effectiveStart
postponed-undated
```

### 冻结只读

```text
now >= effectiveStart
ended
historical
```

### canceled

不得新增。

已有 Wants Live：

> 不删除。

---

# 102. ListeningSessionController

```swift
@MainActor
@Observable
final class ListeningSessionController
```

app-scoped。

依赖：

- ListeningRepository
- ListeningCatalogProviding
- ListeningPlaying
- ListeningPreviewPlaying
- AudioPlaybackCoordinator

持有：

```text
currentShowID
scope
queue
currentIndex
playbackStatus
playbackCapability
catalogLoadState
authorizationState
subscriptionState
userPaused
pausedByTabExit
pausedByScene
listenTabVisible
```

---

# 103. ListeningScope

```swift
enum ListeningScope {
    case wholeShow
    case artist(String)
}
```

`.artist`：

> runtime only。

不持久化。

---

# 104. SwiftUI ownership

View：

- 不 fetch MusicKit
- 不操作 AVPlayer
- 不累计 evidence
- 不手写 SwiftData transaction
- 不自己拼 queue

View 只发送 intent：

```text
playPause
next
previous
seek
markHeard
undoManualHeard
toggleWantsLive
openArtist
onlyArtist
excludeArtist
```

---

# 105. ListenRootView states

```text
noCurrentShow
loading
needsAuthorization
noConnectedArtists
loadingCatalog
ready
cachedWithError
fatalUnavailable
```

不要压成：

```text
isLoading Bool
```

---

# 106. Listen UI

主结构：

```text
听

当前现场轻上下文

熟悉身份轻反馈

[专辑/单曲封面]

歌名
艺人
可靠时的 Apple Music 热门标签

Play/Pause

♡ 想现场听
✓ 听过

弱化 progress
```

---

# 107. Card playback

进入 Listen：

如果 ready + tab visible + 非 userPaused：

> 自动播放当前卡。

前台 natural end：

> 自动下一张。

手动 `听过`：

- 写 manual evidence
- 轻反馈
- 300–500ms
- next

如果 already familiar：

> 不重复产生写入。

---

# 108. 艺人页

统一包含：

- artwork
- name
- familiarity tier
- 已熟悉歌曲数
- Apple Music editorial text
- genre
- Wants Live
- 热门
- 全部
- 专辑
- 只听这位
- 不听这位
- 不是这个艺人

不创建独立：

- 熟悉度详情页
- 曲库 Tab
- 艺人百科模块

---

# 109. 只听这位

仅多艺人现场显示。

```text
scope = .artist(artistID)
```

退出：

```text
scope = .wholeShow
```

不持久化。

---

# 110. 不听这位

仅当前 Show 持久化。

如果正在：

```text
scope = artist(X)
```

然后用户：

> 不听这位

必须：

```text
persist exclusion
scope = wholeShow
rebuild queue
```

---

# 111. Artist matching

未连接艺人：

> 不阻塞其他已连接艺人。

用户明确 Confirm 后才写：

```text
appleMusicArtistID
appleMusicURL
avatarURL
canonical name
```

「不是这个艺人？」：

> 可 rematch。

不得后台自动绑定。

---

# 112. Footprint setlist

`ShowSetlistMemory`：

```swift
@Model
final class ShowSetlistMemory {
    var id: UUID
    var showID: UUID

    var catalogSongID: String?
    var manualTitle: String?
    var manualArtistName: String?

    var isMostSurprising: Bool

    var createdAt: Date
    var updatedAt: Date
}
```

Catalog song：

> 自身就是 showRecall familiarity evidence。

Manual song：

> 只进入足迹，不进入 global familiarity。

---

# 113. most surprising invariant

同一个 Show：

```text
最多一条 isMostSurprising == true
```

设置新项：

1. fetch 当前 show 全部 setlist memories
2. existing surprising → false
3. target → true
4. save once

不需要另一个 unique SwiftData model。

---

# 114. 删除 setlist memory

任何删除 catalog setlist memory 前：

> capture due opening baselines。

删除后：

`FamiliarityEvidenceResolver` 重新判断。

如果同 song：

- 还有 actual
- 还有 manual
- 还有另一个 showRecall

则仍 familiar。

否则变 unfamiliar。

---

# 115. FootprintListeningMemorySection

`FootprintDetailView` 只插入：

```text
FootprintListeningMemorySection
```

不要继续增长 `FootprintDetailView.swift` hotspot。

展示：

```text
去见 TA 时
深度乐迷

想现场听
8 首

现场听到了
...

最惊喜
...
```

Opening tier 无法 resolve：

> 不伪造百分比，不展示假身份。

---

# 116. i18n

仓库要求 i18n，并已有：

```text
zh-Hans
zh-Hant
en
```

三套 `Localizable.strings` / `InfoPlist.strings`。 

所有新可见文字必须三套同时加入。

包括但不限于：

```text
听
听过
撤销手动听过
想现场听
热门
全部
专辑
只听这位
不听这位
不是这个艺人？
试听
暂时无法播放
连接艺人
回到整场
五档熟悉身份
授权错误
无订阅
无艺人
accessibility labels/hints
Footprint listening copy
```

动态/domain 文案：

> 使用 `BSLocalization.text/format`。

禁止在新 View 直接硬编码只支持简中的可见 string。

---

# 117. Accessibility

必须：

- 主操作 ≥ 44×44pt
- Dynamic Type
- VoiceOver 读：
  - song
  - artist
  - playback
  - familiar
  - wants-live
- VoiceOver 提供 next/previous action
- Reduce Motion 下卡片切换不用大位移强动画
- selected 不仅依赖颜色

---

# 118. Local cache / errors

### authorization denied

有 cache：

> 浏览 cache。

无 cache：

> 授权说明。

不反复 request。

### no subscription

有 preview：

> 试听。

无 preview：

> metadata only。

### refresh partial

有 last-good snapshot：

> 保留 denominator。

runtime partial 可以听。

### song playback error

只在当前卡：

```text
暂时无法播放
重试
```

不变整页 error。

---

# 119. Analytics

v1.1 不要求新增音乐内容级 analytics。

不得把：

- artist ID/name
- song ID/title
- Wants Live 内容
- setlist 内容
- familiarity 列表

作为新 PostHog event property 上传。

Listening 的正确性不依赖 analytics。

---

# 120. Privacy / local data

Listening persistent data：

> 默认全部本地。

不通过 Companion sharing 自动共享。

同行不自动看到：

- familiar songs
- Wants Live
- setlist recall
- exclusions

---

# 121. Architecture budget

`check_architecture.py` 是实际执行预算真源。

当前 checker 对相关热点包括：

```text
RootView.swift                     12 KB
BeforeShowApp.swift                12 KB
Show.swift                         24 KB
ShowMutationCoordinator.swift      15 KB
NotificationSchedulingModels.swift 13 KB
LocalNotificationCenter.swift      14 KB
LocalNotificationScheduler.swift   19 KB
CurrentShowManagementView.swift    26 KB
FootprintDetailView.swift          33 KB
AppAudioSession.swift               5 KB
```



实现本功能：

> 禁止提高上述 budget。

如果超：

> 抽完整职责到新文件。

---

# 122. 关键文件预算策略

### BeforeShowApp

通过：

```text
ModelContainerFactory
AppStartupCoordinator
```

缩职责。

### LocalNotificationCenter

只留：

- UNUserNotificationCenter side effects
- portfolio reconcile orchestration

Planner/diff/store 拆文件。

### LocalNotificationScheduler

只留：

> 单 Show → notification requests

删除 focus planning。

### AppAudioSession

只留底层 AVAudioSession configuration。

owner state 移到 AudioPlaybackCoordinator。

### RootView

只增加：

> Listen tab routing。

不新增 Listen feature 业务代码。

---

# 123. Phase 1 — App foundation + Current Show + notifications + Widget/Live Activity + deep link

这是第一阶段，因为 Current Show 语义会影响全 App。

实现：

```text
ModelContainerFactory
AppPersistenceMigrationRunner
AppStartupCoordinator

CurrentShowSelectionStore
InitialCurrentShowPolicy
CurrentShowOwnershipMigration
CurrentShowSession 重构
CurrentShowFollowUpPolicy

AddShow Current ownership
Show delete fallback

NotificationPortfolioPlanner
NotificationPortfolioRecordStore
LocalNotificationCenter portfolio reconcile
删除 planFocusChange / reconcileFocus 生产路径

WidgetSnapshotSync
LiveActivityShowResolver
Widget/Live snapshot 分离
cover cache multi-source retention

CurrentShowFeatureRootView
CurrentShowNotificationRouteCoordinator
```

---

## Phase 1 验收测试

新增/更新：

```text
CurrentShowSelectionStoreTests
CurrentShowOwnershipMigrationTests
CurrentShowSessionTests
InitialCurrentShowPolicyTests
AddShowPersistenceTests
ShowMutationCoordinatorTests

NotificationPortfolioPlannerTests
NotificationPortfolioRecordStoreTests
LocalNotificationPortfolioTests

WidgetSnapshotTests
LiveActivityShowResolverTests
WidgetLiveActivityFocusTests
WidgetCoverRetentionTests

NotificationDeepLinkCurrentOwnershipTests
```

必须覆盖：

1. ended 半年仍保持 Current
2. canceled Current 不自动切
3. historical 可手动 Current
4. 明天有 show 不自动切
5. 新增 live 不抢 Current
6. 删除 Current 才 fallback
7. duplicate CurrentShowSelection deterministic 收敛
8. migration rerun 无变化
9. B/C 两场同时拥有未来通知
10. Current Show 切换不取消 B/C 通知
11. portfolio >56 时只保留最近 56
12. 后续 reconcile 补进下一批
13. duplicate schedule record 被收敛
14. Widget = Current
15. Live Activity = actual/upcoming
16. Widget A + Live B 同时保留两张 cover
17. notification tap 非 Current show 不改变 Current
18. cold launch deep link
19. deleted show deep link 安全 consume

执行：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -only-testing:BeforeShowTests/CurrentShowSelectionStoreTests \
  -only-testing:BeforeShowTests/CurrentShowOwnershipMigrationTests \
  -only-testing:BeforeShowTests/CurrentShowSessionTests \
  -only-testing:BeforeShowTests/NotificationPortfolioPlannerTests \
  -only-testing:BeforeShowTests/NotificationDeepLinkCurrentOwnershipTests \
  -only-testing:BeforeShowTests/WidgetLiveActivityFocusTests
```

---

# 124. Phase 2 — Listening persistence + identity + deletion

实现：

```text
ArtistSlot.appleMusicArtistID
AppleMusicArtistIdentityMigration

ArtistCatalogSnapshot
CatalogSong
CatalogAlbum
SongFamiliarityRecord
ShowWantsLiveSong
ShowArtistListeningPreference
ShowOpeningFamiliarityBaseline
ShowOpeningArtistTier
ShowSetlistMemory

ListeningRepository
FamiliarityEvidenceResolver
ListeningShowDataCleaner

PrivacyLocalDataView 全量 clear
LocalDataInventory
```

所有 unique 写入使用：

> fetch → mutate / insert。

---

## Phase 2 验收测试

```text
ListeningModelTests
ListeningUniqueMutationTests
ListeningArrayPersistenceTests
AppleMusicArtistIdentityMigrationTests
ArtistSlotCatalogIdentityTests
ListeningDeletionIntegrationTests
ListeningLocalDataResetTests
LocalDataInventoryListeningTests
ModelContainerFactoryTests
```

必须覆盖：

1. ArtistSlot 旧数据 decode
2. arrays roundtrip
3. URL 提 artist ID
4. migration rerun 无重复变化
5. artist name edit 清 ID
6. repeated wants-live upsert 只有一 row
7. repeated catalog refresh 无 duplicate
8. repeated familiarity mutation 无 duplicate
9. 单 Show 删除清 show-scoped Listening
10. 单 Show 删除不删 global familiarity/catalog
11. clear-local-data 删除所有 Listening models
12. inventory 在只剩 familiarity 时 `isEmpty == false`
13. Debug seeder 删除不留下 orphan

执行：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -only-testing:BeforeShowTests/ListeningModelTests \
  -only-testing:BeforeShowTests/ListeningUniqueMutationTests \
  -only-testing:BeforeShowTests/ListeningArrayPersistenceTests \
  -only-testing:BeforeShowTests/ListeningDeletionIntegrationTests \
  -only-testing:BeforeShowTests/ListeningLocalDataResetTests \
  -only-testing:BeforeShowTests/ModelContainerFactoryTests
```

---

# 125. Phase 3 — MusicKit catalog + capability

实现：

```text
ListeningMusicContracts
MusicKitListeningCatalogService
catalog projection
catalog pagination
complete/partial semantics
last-good snapshot
subscription capability
preview metadata

Info.plist
3x InfoPlist.strings
UIBackgroundModes audio
```

保留现有：

```text
AppleMusicArtistSearchService
```

---

## Phase 3 验收测试

```text
MusicKitListeningProjectionTests
ListeningCatalogMergeTests
ListeningCatalogCompletenessTests
ListeningCatalogSnapshotTests
ListeningPlaybackCapabilityTests
InfoPlistMusicUsageTests
```

mock DTO / provider，不依赖真实 Apple Music 网络。

必须：

1. topSongs 顺序
2. album pagination
3. song ID 去重
4. compilation performer filter
5. music video 不入
6. partial 不覆盖 last-good snapshot
7. complete mutate existing snapshot
8. no subscription + preview = previewOnly
9. no preview = metadataOnly
10. subscriber = fullPlayback
11. 三套 NSAppleMusicUsageDescription 存在
12. deployment target 仍为 17.0

执行：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -only-testing:BeforeShowTests/MusicKitListeningProjectionTests \
  -only-testing:BeforeShowTests/ListeningCatalogMergeTests \
  -only-testing:BeforeShowTests/ListeningCatalogCompletenessTests \
  -only-testing:BeforeShowTests/ListeningPlaybackCapabilityTests \
  -only-testing:BeforeShowTests/InfoPlistMusicUsageTests
```

---

# 126. Phase 4 — Familiarity + opening baseline + Wants Live + queue

实现：

```text
FamiliarityEvidenceResolver
manual evidence
actual evidence repository seam
Undo semantics

OpeningFamiliarityCoordinator
Opening tier delayed resolution
Opening invalidation

WantsLiveMutationPolicy
ListeningQueuePolicy
```

---

## Phase 4 验收测试

```text
FamiliarityEvidenceTests
OpeningFamiliarityBaselineTests
OpeningArtistTierTests
WantsLiveMutationPolicyTests
ListeningQueuePolicyTests
```

必须覆盖：

1. manual → familiar
2. manual → undo → unfamiliar
3. manual → actual → undo → familiar
4. manual → showRecall → undo → familiar
5. 删除最后 showRecall 且无其他证据 → unfamiliar
6. baseline 保存 familiar song IDs
7. 开场无 catalog → baseline 仍生成
8. 开场后新增 familiar → later catalog tier 不包含它
9. Current=A、B 已开场；A 上的 mutation 前仍先 freeze B
10. baseline rerun 不覆盖
11. postponed future invalidates old baseline
12. canceled invalidates baseline/tier
13. artist rematch 重算 tier using same baseline
14. Wants Live 开场前可写
15. 开场后只读
16. Wants Live 不跨 show
17. queue unheard-first stable partition
18. round robin
19. swipe 无数据 mutation
20. duplicate collaboration song whole-show 只一次

执行：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -only-testing:BeforeShowTests/FamiliarityEvidenceTests \
  -only-testing:BeforeShowTests/OpeningFamiliarityBaselineTests \
  -only-testing:BeforeShowTests/OpeningArtistTierTests \
  -only-testing:BeforeShowTests/WantsLiveMutationPolicyTests \
  -only-testing:BeforeShowTests/ListeningQueuePolicyTests
```

---

# 127. Phase 5 — Playback + evidence tracker + audio state machine

实现：

```text
MusicKitListeningPlayer
AppleMusicPreviewPlayer
ListeningEvidenceTracker
AudioPlaybackCoordinator
ListeningSessionController
tab/scene playback state machine
```

现有 Memory/Dynamic Cover 音频接入新的 owner coordinator。

---

## Phase 5 验收测试

```text
ListeningEvidenceTests
ListeningSessionControllerTests
ListeningPlaybackStateMachineTests
ListeningAudioOwnershipTests
ListeningCurrentShowSwitchTests
```

必须：

1. 49% 不产生 actual evidence
2. 50% 产生
3. seek 前进不算跳过段
4. seek 后退重新听可累计
5. pause 不累计
6. preview 永远不自动 familiar
7. tab hide full pause
8. tab hide preview pause
9. full song 在 Listen tab + background 不被主动 pause
10. preview background pause
11. preview foreground 条件恢复
12. user pause 后 tab 返回不恢复
13. user pause 后 foreground 不恢复
14. Current Show switch 立即 stop old
15. audio owner 多 owner 不互相提前切 ambient
16. 最后 owner release 才回 ambient
17. playbackTime NaN 安全
18. natural end foreground auto-next

执行：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -only-testing:BeforeShowTests/ListeningEvidenceTests \
  -only-testing:BeforeShowTests/ListeningSessionControllerTests \
  -only-testing:BeforeShowTests/ListeningPlaybackStateMachineTests \
  -only-testing:BeforeShowTests/ListeningAudioOwnershipTests
```

---

# 128. Phase 6 — Listen Tab / card UI / i18n / accessibility

实现：

```text
BeforeShowTab.listen
RootView Listen tab
ListenRootView
ListeningSongCardView
ListeningPresentation
DEBUG fixtures
```

不同时扩艺人详情。

---

## Phase 6 Debug fixtures

至少：

```text
--listen-fixture no-current
--listen-fixture single-full
--listen-fixture multi-full
--listen-fixture preview-only
--listen-fixture metadata-only
--listen-fixture cached-error
--listen-fixture ended-current
```

---

## Phase 6 验收测试

```text
NavigationTests
ListeningPresentationTests
ListeningAccessibilityTests
ListeningLocalizationTests
ListeningWantsLivePresentationTests
```

必须：

1. 3 Tab 顺序正确
2. Current 无 show 空态
3. single card
4. multi card 明确 artist
5. preview 标识
6. metadata-only
7. ended current 仍可 Listen
8. Wants Live frozen presentation
9. Reduce Motion
10. VoiceOver actions
11. 简中所有新 key 存在
12. 繁中所有新 key 存在
13. 英文所有新 key 存在
14. 五档 tier 三语
15. 不出现缺 key 后 fallback 的简中 raw text

执行：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -only-testing:BeforeShowTests/NavigationTests \
  -only-testing:BeforeShowTests/ListeningPresentationTests \
  -only-testing:BeforeShowTests/ListeningAccessibilityTests \
  -only-testing:BeforeShowTests/ListeningLocalizationTests
```

---

# 129. Phase 7 — Artist page / matching / library

实现：

```text
ListeningArtistView
ListeningArtistMatchSheet
ListeningLibraryView

只听这位
不听这位
重新匹配
热门 / 全部 / 专辑
```

继续复用现有 iTunes Search artist candidate 服务。

---

## Phase 7 验收测试

```text
ListeningArtistMatchingTests
ListeningArtistPreferenceTests
ListeningArtistLibraryTests
ListeningArtistRematchTests
```

必须：

1. search result 不自动写
2. confirm 才写 ID
3. 未连接 B 不阻塞 A/C
4. rematch 清旧 show-scoped artist state
5. rematch 保留 global familiarity
6. only artist 不持久化
7. exclude 只当前 show
8. restore
9. artist-only 下 exclude 自动回 whole show
10. 热门只用 topSongIDs
11. 无 topSongs 隐藏热门
12. album order
13. 点击 library song 回 flow 并播放

执行：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -only-testing:BeforeShowTests/ListeningArtistMatchingTests \
  -only-testing:BeforeShowTests/ListeningArtistPreferenceTests \
  -only-testing:BeforeShowTests/ListeningArtistLibraryTests \
  -only-testing:BeforeShowTests/ListeningArtistRematchTests
```

---

# 130. Phase 8 — Footprint integration + complete regression

实现：

```text
FootprintListeningMemorySection
FootprintSetlistRecallSheet

opening tier display
Wants Live history
setlist recall
most surprising
```

然后完成整个 feature 的系统级验收。

---

## Phase 8 功能测试

```text
FootprintListeningMemoryTests
ShowSetlistMemoryTests
ListeningCrossFeatureIntegrationTests
```

必须：

1. opening tier 正确显示
2. 不展示伪 percentage
3. Wants Live 保持 opening history
4. catalog setlist 是 familiarity evidence
5. manual setlist 不 familiar
6. 删除 recall 正确重新解析 evidence
7. most surprising 同场一条
8. 删除 show 清 setlist / opening / wants-live
9. global familiarity 保留
10. clear-local-data 全删

执行：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -only-testing:BeforeShowTests/FootprintListeningMemoryTests \
  -only-testing:BeforeShowTests/ShowSetlistMemoryTests \
  -only-testing:BeforeShowTests/ListeningCrossFeatureIntegrationTests
```

---

# 131. 最终生成与架构检查

完成 Phase 8：

```bash
cd apps/ios

xcodegen generate

python3 scripts/check_architecture.py
```

必须：

```text
PASS
```

禁止通过提高 hotspot budget 达成 PASS。

---

# 132. 完整签名单测

AGENTS.md 明确要求命令行构建/测试带 Development Team，否则会发生 ad-hoc 签名并剥掉 iCloud/App Groups/WeatherKit entitlement。

最终完整测试：

```bash
cd apps/ios

xcodebuild test \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ
```

**任何本 Spec 中用于 build/test 验收的 xcodebuild 命令都不得省略：**

```text
-allowProvisioningUpdates
DEVELOPMENT_TEAM=29C8MS76CZ
```

---

# 133. 最终签名 build + entitlements 验证

如果需要单独 build：

```bash
cd apps/ios

xcodebuild \
  -project BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=29C8MS76CZ \
  -derivedDataPath DerivedData-listen-final \
  build
```

随后检查：

```text
DerivedData-listen-final/
Build/Intermediates.noindex/
...
Entitlements-Simulated.plist
```

必须包含：

```text
com.apple.developer.icloud-container-identifiers
```

不能接受 ad-hoc fallback。

---

# 134. 最终安装与启动存活

推荐有 PR 时直接：

```bash
scripts/verify-pr.sh <PR_NUMBER> --no-comment
```

仓库 verifier 已经执行：

- signed `xcodebuild test`
- entitlement 检查
- 安装到 iPhone 17 simulator
- `simctl launch`
- 5 秒进程存活检查。

最终验收：

> 单元测试通过但安装后闪退，不算通过。

---

# 135. 真机 MusicKit 验收

模拟器测试不能替代真实 MusicKit 验证。

### Apple Music subscriber

验证：

- MusicAuthorization
- catalog fetch
- full playback
- pause/resume
- seek
- natural end foreground next
- lock screen/background 当前歌继续
- tab 离开 pause
- 50% actual evidence

### 无订阅账号

验证：

- metadata
- preview
- preview 不产生 automatic familiar
- 手动听过仍工作

### denied authorization

验证：

- 不 crash
- 不循环 request
- cache 可浏览

---

# 136. 旧 artist-warmup 分支映射

### ShowArtist

```text
删除
```

使用：

```text
Show.artists + ArtistSlot
```

### ArtistInterest

```text
删除
```

不再有：

```text
想看 / 待定 / 不看
```

### ShowSongImpression

```text
删除
```

只有：

```text
ShowWantsLiveSong
```

### ShowArtistFamiliaritySnapshot

```text
删除
```

替换：

```text
ShowOpeningFamiliarityBaseline
+
ShowOpeningArtistTier
```

### WarmupListeningEvidence

只迁算法思想。

重写为：

```text
ListeningEvidenceTracker
```

### ArtistWarmupMusicService

不整体迁。

拆：

```text
MusicKitListeningCatalogService
MusicKitListeningPlayer
AppleMusicPreviewPlayer
```

### ArtistWarmupCoordinator

删除。

替换：

```text
ListeningSessionController
ListeningRepository
OpeningFamiliarityCoordinator
```

### ArtistWarmupViews

删除。

重新实现 Listen UI。

---

# 137. 明确不做

v1.1 不包含：

- 歌词
- 评论
- 音乐好友
- 排名
- 积分
- 每日任务
- 连续签到
- AI 艺人介绍
- AI 推荐理由
- setlist 网络抓取
- setlist 预测
- Apple Music playlist 创建
- 离线下载
- EQ
- 播放速度
- 用户可见随机模式
- 用户可见循环模式
- 复杂 queue editor
- 独立快速扫歌模式
- 独立熟悉度页面
- 独立曲库 Tab
- 跨现场 Wants Live
- swipe 推断 dislike
- artist dislike 模型
- warmup reminder

---

# 138. 最终不可违反的工程 Invariants

### I1

```text
时间流逝不能写 CurrentShowSelection
```

### I2

```text
Current Show == Listen show == Widget show
```

### I3

```text
Notification portfolio != Current Show
```

### I4

```text
所有 eligible upcoming shows 都可同时拥有 notification nodes
```

### I5

```text
Live Activity show != 必须 Current
```

### I6

```text
notification deep link 不改变 Current Show
```

### I7

```text
Song Familiarity 是跨现场
```

### I8

```text
Wants Live 是单场且开场冻结
```

### I9

```text
manual Undo 不删除 actual/showRecall evidence
```

### I10

```text
Preview 永远不自动 familiar
```

### I11

```text
Seek 跳过时间永远不计 actual listening
```

### I12

```text
Swipe 永远无偏好语义
```

### I13

```text
opening tier 必须来自 frozen opening baseline
```

### I14

```text
开场后新增 familiarity 永远不能污染 opening tier
```

### I15

```text
partial catalog 永远不能覆盖 last-good denominator
```

### I16

```text
unique model 永远 fetch-then-mutate
```

### I17

```text
删除 Show 不删除 global familiarity/catalog
```

### I18

```text
清除本地数据必须删除所有 Listening 数据
```

### I19

```text
full playback 后台不因 scene inactive 自动 pause
```

### I20

```text
离开 Listen tab 必须 pause
```

### I21

```text
三套语言必须同步
```

### I22

```text
任何 build/test xcodebuild 都必须显式 DEVELOPMENT_TEAM
```

---

# 139. B1–B11 交叉一致性检查

| Red-team 项 | 数据模型落点 | 实现落点 | 验收落点 |
|---|---|---|---|
| **B1 多场通知** | `NotificationSchedulingState.focusedShowID` 失效；records 按 show 共存 | `NotificationPortfolioPlanner` + 全局 diff，≤56 | Phase 1：B/C 同时排期、容量、补位 |
| **B2 Widget / Live Activity 分离** | 无新增单焦点字段 | `WidgetSnapshotSync` + `LiveActivityShowResolver`；cover cache 保留 union | Phase 1：Widget=A、LA=B、双封面 |
| **B3 非 Current 深链** | 不写 CurrentShowSelection | `CurrentShowFeatureRootView` + route coordinator | Phase 1：non-current / cold launch / deleted |
| **B4 opening snapshot 不可恢复** | `ShowOpeningFamiliarityBaseline` 保存 song IDs | 所有 familiarity mutation 前 capture all due shows；catalog 后延迟 resolve | Phase 4：无 catalog 开场→后续正确恢复 |
| **B5 Evidence / Undo** | manual + actual 分开；showRecall 由 setlist row 承担 | `FamiliarityEvidenceResolver`；Undo 仅撤 manual | Phase 4：manual→actual/showRecall→Undo 仍 familiar |
| **B6 unique / arrays** | 所有 unique schema 明确；数组 reassign | repository fetch→mutate/insert，禁止 blind insert | Phase 2：重复 upsert、array roundtrip |
| **B7 Current selection / migration** | CurrentShowSelection 保留轻 schema | `CurrentShowSelectionStore` deterministic canonical；单一 startup runner | Phase 1：duplicates + rerun idempotent |
| **B8 delete / clear** | show-scoped 与 global 明确分离 | `ListeningShowDataCleaner`；Settings 全模型 clear | Phase 2/8：单 show、debug seeder、full reset |
| **B9 background audio** | 无持久化状态 | tab/scene 明确状态机；AudioPlaybackCoordinator | Phase 5：background full、tab hide pause、user pause |
| **B10 i18n** | tier raw values 技术值 | 三套 Localizable + 三套 InfoPlist | Phase 3/6 localization tests |
| **B11 签名 / budget** | `ModelContainerFactory` 防 App hotspot 增长 | planner/audio/app 职责拆文件；禁止调高 budget | 每 Phase signed test + Phase 8 architecture/launch |

**B1–B11 均同时存在于：**

1. 数据/架构定义
2. 实现阶段
3. 验收测试

三处。

---

# 140. 最后一轮交叉检查发现并已额外修正的问题

在将 B1–B11 合并后再次检查现有 main，发现一个由 B2 引出的次生问题：

当前 `ShowLiveActivityController` 会对 Widget cover cache 执行单 source prune。Widget 与 Live Activity 一旦开始使用不同 show，这会导致：

```text
Widget 保存 A cover
↓
Live Activity 更新 B
↓
prune except B
↓
A cover 被删除
```

v1.1 已在：

- §63
- Phase 1
- `WidgetCoverRetentionTests`

三处增加：

```text
keepingSources = widgetSource ∪ liveActivitySource
```

因此该问题不再是未决 blocker。

---

# 141. 当前 main / API 最终核验

已重新核实：

- main HEAD：`e41c99c...` 
- iOS deployment target：17.0 
- Current Show 当前确实存在 automatic selection / retention 语义 
- Notifications 当前确实只围绕单 focus show 排期 
- Widget 与 Live Activity 当前确实共用同一 snapshot 
- non-current notification deep link 当前确实会被消费丢弃 
- Local clear 当前确实逐 model 删除且不包含 Listening 
- 当前 audio session 尚无 owner arbitration 
- 当前 SwiftData 已实际使用 unique composite string、Codable arrays  
- AGENTS 要求 iPhone 17 + signed command line builds 
- MusicKit 当前仍支持本 Spec 所需的 authorization、catalog、subscription capability、ApplicationMusicPlayer、preview assets、seek playback time；ApplicationMusicPlayer 在启用 background audio 后支持后台继续当前音乐项。

---

# 142. 最终结论

**v1.1 已验证无剩余实现 blocker。**

Codex 可以按：

```text
Phase 1
→ Phase 2
→ Phase 3
→ Phase 4
→ Phase 5
→ Phase 6
→ Phase 7
→ Phase 8
```

直接执行。

禁止重新解释已经锁定的产品语义；如果实现过程中发现 SDK/compiler 与本 Spec 的某个具体 API signature 不同：

> 适配 Infrastructure implementation，不改变 Domain/Product invariant。