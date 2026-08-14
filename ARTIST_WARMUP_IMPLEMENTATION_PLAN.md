# 艺人预热开发计划

## Goal

在 BeforeShow iOS App 中交付一个围绕「当前现场」的独立「预热」Tab。用户可以确认现场艺人的 Apple Music 身份、浏览可枚举的完整音频曲库、通过真实收听建立跨现场歌曲熟悉记录、按艺人继续预热、留下当前现场的歌曲印象，并在散场后回记实际听到的歌。

产品行为以 `CONTEXT.md`、`PRODUCT_DEFINITION_V2.1.md` 与 ADR 0031 为准；UI 参考文件为 `/Users/water/Downloads/beforeshow-warmup-v1.2-dev-spec.html`，它只提供可借鉴的视觉元素与构图，不是状态模型、交互真相或需要逐像素还原的 UI 规格。

## 本轮范围

- 底部主导航增加独立「预热」Tab，并始终跟随当前现场。
- 明确区分现场艺人文字、用户确认的 Apple Music 艺人身份和 Apple Music 授权。
- 支持单艺人和多艺人现场；多艺人关注项只有「想看／待定／不看」。
- 聚合 Apple Music 可枚举的专辑、单曲、合辑和表演署名合作歌曲，形成去重音频曲库。
- 目录枚举完成后，按「听过独立歌曲数／当前曲库独立歌曲数」展示每位艺人的熟悉程度。
- 支持 Apple Music 完整播放、清楚标注的试听、未听歌曲优先队列、只听某位艺人和先跳过。
- 完整播放的真实累计收听达到歌曲时长 50% 后自动记为「听过」；拖动越过的时长不计入。
- 支持逐首补记或撤销「听过」，以及按专辑批量补记后逐首撤销。
- 支持当前现场内的「想现场听」「有感觉」和一句可选私人印象。
- 开场时冻结每位已连接艺人的熟悉度快照；散场后回记实际听到与最惊喜的歌曲。
- 所有数据默认本地私密；删除一场现场不删除跨现场歌曲熟悉记录。

## 不在本轮范围

- 盲听猜歌、多人玩法、排行榜或游戏中心。
- 歌词展示。
- 脱离当前现场的通用音乐首页、全局歌曲搜索或平台歌单创建。
- 最近播放自动导入、跨设备同步、公开分享或同行者共享。
- 音乐视频、演出 setlist 预测和网络 setlist 自动导入。
- BeforeShow Pro 门槛；完整播放资格只由 Apple Music 决定。

## 关键实现假设

1. App 尚未上线，不做旧数据兼容；新增 SwiftData 模型直接注册到当前本地 `ModelContainer`。
2. `Show.artist` 仍是导入得到的原始文字；新的现场艺人实体负责多艺人、匹配状态和观看意向。
3. Apple Music 目录没有单一“完整艺人曲库”调用。实现会遍历艺人的专辑、单曲、合辑、Top Songs 与各专辑歌曲关系并处理分页，再按歌曲/录音标识去重。
4. 只有目录刷新完整结束时才发布熟悉度分母。加载中或部分失败显示“正在整理曲库／暂时无法生成熟悉程度”，不把部分目录冒充完整目录。
5. MusicKit 通过 `MusicAuthorization`、`MusicSubscription.canPlayCatalogContent`、`MusicCatalogSearchRequest` 和 `ApplicationMusicPlayer` 接入；Info.plist 增加 `NSAppleMusicUsageDescription`。
6. UI 使用项目已有设计 token 和原生 SwiftUI 容器；参考稿中的固定 px、假封面和 HTML 状态变量不进入生产代码。

## 模块边界

### Domain

- `ShowArtist`: 某场现场中的艺人及观看意向、匹配状态。
- `ArtistCatalogSnapshot`: 一位 Apple Music 艺人的一次完整目录快照及刷新状态。
- `CatalogSong`: 去重后的 Apple Music 音频歌曲投影。
- `SongFamiliarityRecord`: 跨现场保存的一首歌曲「听过」记录。
- `ShowSongImpression`: `(showID, songID)` 唯一的当前现场歌曲印象。
- `ShowArtistFamiliaritySnapshot`: 开场时冻结的 `(showID, artistID)` 熟悉程度。
- `ShowSetlistMemory`: 散场后某首歌“现场听到了／最惊喜”的记录；允许无 Apple Music ID 的手动曲目。

### Services

- `ArtistWarmupCatalogProviding`: 搜索艺人、读取资料、枚举完整目录。
- `ArtistWarmupPlaying`: 设置队列、播放/暂停/切歌并上报真实累计收听证据。
- `ArtistWarmupRepository`: 读写连接、熟悉记录、印象、快照和回记。
- `MusicKitArtistWarmupService`: 生产 MusicKit 实现。
- `FixtureArtistWarmupService`: 测试与 DEBUG 截图使用的确定性实现。

### UI

- `ArtistWarmupRootView`: 当前现场生命周期路由。
- `ArtistMatchingView` / `ArtistMatchingSearchSheet`。
- `ArtistWarmupHomeView`（单艺人／多艺人）。
- `WarmupPlayerView` / `SongImpressionSheet`。
- `ArtistCatalogView`。
- `PostShowSetlistRecallView`。

## 垂直切片

### Slice 1 — 主导航与可运行骨架

- 新增「预热」Tab 和当前现场上下文。
- 无当前现场、尚未连接和 DEBUG fixture 已连接三种入口状态可运行。
- 增加仅在 DEBUG 生效的确定性启动参数 `--artist-warmup-fixture <state>`，支持 iPhone 17 截图；Release 构建必须忽略该参数。
- 修改 `CurrentShowSelector.isManuallySelectable`：用户手动设为当前的「延期且日期未定」现场保持当前，并允许进入预热；自动选择仍不得主动选中这种现场，已取消现场仍不可选。
- 为上述选择规则修改 `CurrentShowSelectionTests`：把现有“未定延期手动选择回退”的预期改为“保持手动当前”，并保留自动选择排除未定延期与取消现场回退的覆盖。
- 未定延期现场没有可用的开场时点，因此只能预热，不生成 `ShowArtistFamiliaritySnapshot`，也不创建任何基于开场日期的预热提醒；补 `ArtistWarmupLifecycleTests` 和提醒策略测试锁定这两个负面条件。

#### Slice 1 QA

自动化命令：

```bash
xcodebuild \
  -project apps/ios/BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test \
  -only-testing:BeforeShowTests/NavigationTests \
  -only-testing:BeforeShowTests/CurrentShowSelectionTests \
  -only-testing:BeforeShowTests/ArtistWarmupLifecycleTests
```

执行步骤与预期结果：

1. 运行上方命令；预期三个测试类全部通过，Tab 顺序固定为「当前／预热／足迹」。
2. 用 `no-current-show` fixture 启动并点「预热」；预期显示无当前现场空态。
3. 用 `postponed-undated` fixture 启动；预期该手动现场仍是当前且可预热，同时测试仓库内开场快照数和日期型提醒数都为 0。
4. 用 `canceled-show` fixture 启动；预期不展示主动预热队列，播放器没有待播歌曲。

### Slice 2 — 艺人匹配与 Apple Music 能力

- 现场艺人逐位确认；确认身份与音乐授权分开。
- MusicKit 搜索、授权状态、订阅能力和无订阅降级状态。
- 测试：不自动绑定、暂不连接可恢复、同名候选可区分、无授权/无订阅不丢当前现场。

#### Slice 2 QA

自动化命令：

```bash
xcodebuild \
  -project apps/ios/BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test \
  -only-testing:BeforeShowTests/ArtistWarmupMatchingTests \
  -only-testing:BeforeShowTests/MusicKitArtistWarmupServiceTests
```

执行步骤与预期结果：

1. 用 `matching-unconnected` fixture 打开预热；预期只显示待确认艺人，不显示 0% 熟悉程度，也不自动保存 Apple Music 艺人 ID。
2. 搜索同名艺人并选中一个候选；预期候选至少用头像、艺人名和 Apple Music 提供的可区分元数据显示差异，只有点确认后才建立连接。
3. 依次切换 `authorization-denied` 与 `no-subscription` fixture；预期当前现场和已确认艺人不丢失，界面分别提供重新授权说明或试听/不可播放降级，而不是伪装成完整播放。
4. 点「暂不连接」后重新进入匹配；预期可以继续搜索并确认。

### Slice 3 — 曲库与熟悉程度

- 完整枚举、分页、音频过滤、合作歌曲纳入和去重。
- 跨现场歌曲熟悉记录、手动补记/撤销、专辑批量补记。
- 测试：目录未完成无分母、重复收录只计一次、曲库新增会降低比例、身份边界准确。

#### Slice 3 QA

自动化命令：

```bash
xcodebuild \
  -project apps/ios/BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test \
  -only-testing:BeforeShowTests/ArtistCatalogTests \
  -only-testing:BeforeShowTests/SongFamiliarityTests
```

执行步骤与预期结果：

1. 用 `catalog-loading` fixture 打开预热；预期显示“正在整理曲库”，不出现百分比、已听首数或临时分母。
2. 切换到 `catalog-complete` fixture；预期重复收录被去重、表演署名合作曲被纳入、音乐视频被排除，页面显示确定的已听首数/总数和身份标签。
3. 对一首歌补记「听过」再撤销；预期已听首数和比例各只变化一次，跨页面返回后仍保持。
4. 给 fixture 增加一首新歌后刷新；预期已听首数不变、总数增加，比例允许下降。

### Slice 4 — 队列与真实播放证据

- 未听歌曲主线、多艺人轮换、关注意向和只听某位。
- 完整播放与试听状态；真实累计播放达到 50% 才自动「听过」。
- 测试：`不看` 排除、全部不看为空态、拖动不计时、重复播放不重复增加。

#### Slice 4 QA

自动化命令：

```bash
xcodebuild \
  -project apps/ios/BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test \
  -only-testing:BeforeShowTests/ArtistWarmupQueueTests \
  -only-testing:BeforeShowTests/ListeningEvidenceTests
```

执行步骤与预期结果：

1. 用 `pre-show-multi` fixture 启动；把一位艺人设为「不看」，预期后续队列不再出现该艺人的歌；全部设为「不看」时显示明确空态。
2. 对某位艺人点「只听这位」，连续切两首；预期歌曲都属于该艺人，退出后回到原现场的预热页。
3. 用确定性播放器累计真实播放至 49%；预期歌曲仍未听过；继续到 50% 时预期只新增一条熟悉记录。
4. 直接 Seek 到 90% 并播放少量时长；预期跳过区间不计入累计；重复完整播放同一首歌也不重复增加已听首数。
5. 用 `no-subscription` fixture 播放试听；预期界面标注试听且试听结束后不自动形成「听过」。

### Slice 5 — 歌曲印象与完整曲库 UI

- `(现场, 歌曲)` 唯一印象，可修改/撤销。
- 完整曲库的专辑/单曲/合作分组和补记入口。
- 测试：保存印象不增加熟悉度；删除现场删除印象但保留熟悉记录。

#### Slice 5 QA

自动化命令：

```bash
xcodebuild \
  -project apps/ios/BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test \
  -only-testing:BeforeShowTests/ShowSongImpressionTests \
  -only-testing:BeforeShowTests/ArtistCatalogPresentationTests
```

执行步骤与预期结果：

1. 用 `now-playing` fixture 打开歌曲印象 Sheet，先选「想现场听」并写一句印象，再改为「有感觉」；预期同一 `(现场, 歌曲)` 始终只有一条记录且显示最后修改内容。
2. 保存、修改或撤销印象；预期已听首数和熟悉比例都不变化。
3. 打开完整曲库；预期专辑、单曲、合作歌曲分组清楚，补记入口可用，重复歌曲不跨分组重复计入总数。
4. 删除当前现场；预期该现场歌曲印象被删除，但跨现场 `SongFamiliarityRecord` 仍存在。

### Slice 6 — 开场快照与散场回记

- 开场时冻结每位艺人的熟悉度；取消现场不生成快照。
- 散场后确认现场歌曲、补充手动曲目和最惊喜歌曲。
- 测试：散场后继续听不会改写开场快照；“现场听到了”会更新当前熟悉记录；手动曲目不计入艺人熟悉程度。

#### Slice 6 QA

自动化命令：

```bash
xcodebuild \
  -project apps/ios/BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test \
  -only-testing:BeforeShowTests/ArtistFamiliaritySnapshotTests \
  -only-testing:BeforeShowTests/PostShowSetlistRecallTests
```

执行步骤与预期结果：

1. 用有明确开场时间的 fixture 跨过开场边界两次；预期每位已连接艺人只创建一份不可变快照。
2. 快照生成后再听一首歌；预期当前熟悉度更新，快照的已听首数、总数和比例保持原值。
3. 用 `post-show-recall` fixture 勾选“现场听到了”；预期该 Apple Music 歌曲进入当前熟悉记录，但不改写开场快照。
4. 添加 Apple Music 不存在的翻唱/新歌并标为最惊喜；预期回记被保存，但艺人熟悉度分子与分母均不变化。
5. 用取消现场与 `postponed-undated` fixture 检查；预期二者都不生成开场快照，未定延期仍可继续预热。

## 验收标准

### Navigation & lifecycle

- [ ] 底部 Tab 按「当前／预热／足迹」排列，均有至少 44×44pt 点击区域和选中语义。
- [ ] 「预热」只展示当前现场；切换当前现场后停止旧队列的后续排队。
- [ ] 延期且无新日期时仍可预热；取消后停止主动预热；散场后三天内优先展示现场歌单回记。
- [ ] 猜歌入口、占位和文案均不存在。

### Artist matching

- [ ] 系统推荐候选不会自动建立连接，用户必须确认。
- [ ] 搜索结果能区分同名艺人；暂不连接后可再次匹配。
- [ ] 艺人身份确认与 Apple Music 授权是两个可恢复状态。
- [ ] 未连接艺人不显示 0% 熟悉程度、不进入队列或提醒。

### Catalog & familiarity

- [ ] 只在目录完整枚举成功后展示已听首数、总数、进度和熟悉身份。
- [ ] 同一录音的重复专辑收录只计一次；现场版/重混版等实质版本分别保留。
- [ ] 合作歌曲只有在艺人具有表演署名时纳入；音乐视频不纳入。
- [ ] 身份边界为 0%、1–24%、25–49%、50–74%、75–99%、100%。
- [ ] 新歌进入曲库后分母变化可以使比例下降。

### Playback & queue

- [ ] 有完整播放资格时使用 `ApplicationMusicPlayer`；无资格时清楚展示试听或不可播放状态。
- [ ] 试听不会自动形成「听过」。
- [ ] 只有真实累计播放时长达到歌曲总时长 50% 才自动「听过」；Seek 跳过部分不计入。
- [ ] 「想看」优先、「待定」参与、「不看」排除；全部不看时不偷偷回退到任意艺人。
- [ ] “只听这位”保持正确艺人和返回上下文；重复播放不会重复增加熟悉程度。

### Impressions, snapshots & recall

- [ ] 保存歌曲印象不会改变「听过」或熟悉程度。
- [ ] 同一现场同一歌曲只有一条可编辑印象；不同现场可以有不同印象。
- [ ] 开场前熟悉度是不可变快照；散场后的收听不改写它。
- [ ] 确认“现场听到了”会更新当前歌曲熟悉记录，但不改写开场快照。
- [ ] Apple Music 中不存在的翻唱、新歌或串烧可以手动回记，但不进入艺人熟悉程度。

### Accessibility & quality

- [ ] 关键文字使用 Dynamic Type；超大字号下卡片可增长、主要操作仍可达。
- [ ] 所有交互目标至少 44×44pt；Sheet 使用原生模态语义和正确焦点顺序。
- [ ] VoiceOver 能读出现场、艺人、熟悉身份、已听首数/总数和选择状态。
- [ ] Reduce Motion 下无循环或依赖位移动画。
- [ ] 所有新增单元/集成测试通过，完整 `BeforeShowTests` 通过。
- [ ] 在 iPhone 17 模拟器保存至少六张关键状态截图；截图存临时目录且不进入 Git。

## iPhone 17 截图验收

DEBUG 构建统一读取启动参数 `--artist-warmup-fixture <state>`。每个状态必须重置为独立、确定性的内存数据，并在启动后选中「预热」Tab；Release 构建不读取 fixture。首批 fixture 注册表至少包含 `no-current-show`、`canceled-show`、`postponed-undated`、`matching-unconnected`、`authorization-denied`、`no-subscription`、`pre-show-single`、`pre-show-multi`、`catalog-loading`、`catalog-complete`、`now-playing` 和 `post-show-recall`。截图统一保存到仓库根目录下已被 `.gitignore` 排除的 `tmp-screenshots/artist-warmup/`，不得放进源码、Asset Catalog 或 Git 暂存区。

先构建、安装并准备目录：

```bash
mkdir -p tmp-screenshots/artist-warmup
xcrun simctl boot 'iPhone 17'
xcodebuild \
  -project apps/ios/BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath apps/ios/DerivedData \
  build
xcrun simctl install \
  'iPhone 17' \
  apps/ios/DerivedData/Build/Products/Debug-iphonesimulator/BeforeShow.app
```

如果 iPhone 17 已启动，`xcrun simctl boot 'iPhone 17'` 返回“already booted”可以忽略；其余命令必须成功。每次 `launch` 后等待界面稳定，再执行紧随其后的 `screenshot`：

```bash
xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture no-current-show
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/01-no-current-show.png

xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture matching-unconnected
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/02-matching-unconnected.png

xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture pre-show-single
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/03-pre-show-single.png

xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture pre-show-multi
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/04-pre-show-multi.png

xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture catalog-loading
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/05-catalog-loading.png

xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture no-subscription
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/06-no-subscription.png

xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture now-playing
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/07-now-playing.png

xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture postponed-undated
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/08-postponed-undated.png

xcrun simctl launch --terminate-running-process \
  'iPhone 17' com.doublewaterapps.beforeshow \
  --artist-warmup-fixture post-show-recall
xcrun simctl io 'iPhone 17' screenshot \
  tmp-screenshots/artist-warmup/09-post-show-recall.png
```

逐张验收：

| fixture / 文件 | 必须看见 | 不得出现 |
| --- | --- | --- |
| `no-current-show` / `01-no-current-show.png` | 无当前现场说明与去「当前」添加/选择现场的动作 | 艺人百分比、播放器 |
| `matching-unconnected` / `02-matching-unconnected.png` | 当前现场信息、待确认艺人、搜索/暂不连接动作 | 自动绑定、0% 熟悉度 |
| `pre-show-single` / `03-pre-show-single.png` | 单艺人身份标签、已听首数/总数、继续预热主动作 | 多艺人观看意向控件 |
| `pre-show-multi` / `04-pre-show-multi.png` | 多艺人列表、想看/待定/不看、轮换预热入口 | 被标记不看的艺人进入待播队列 |
| `catalog-loading` / `05-catalog-loading.png` | “正在整理曲库”及加载/重试状态 | 临时百分比、部分分母 |
| `no-subscription` / `06-no-subscription.png` | 无完整播放资格的清楚说明及试听/不可播放状态 | 暗示已在完整播放的文案 |
| `now-playing` / `07-now-playing.png` | 当前歌曲、艺人、播放控制、歌曲印象入口与实际收听进度 | Seek 后虚增的听过状态 |
| `postponed-undated` / `08-postponed-undated.png` | “延期·日期待定”语义和仍可使用的预热动作 | 开场倒计时、基于日期的提醒、开场快照文案 |
| `post-show-recall` / `09-post-show-recall.png` | 现场听到的歌曲选择、手动补歌、最惊喜入口 | 猜歌入口、开场快照被实时改写的暗示 |

截图完成后执行以下检查，预期只列出 PNG 文件且 `git status` 不出现 `tmp-screenshots/`：

```bash
find tmp-screenshots/artist-warmup -maxdepth 1 -name '*.png' -print
git status --short -- tmp-screenshots
```

## 验证命令

```bash
xcodebuild \
  -project apps/ios/BeforeShow.xcodeproj \
  -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

垂直切片开发时优先运行对应测试类，最终再运行完整测试目标。UI 验收使用 iPhone 17 模拟器和 DEBUG fixture，不依赖开发者个人 Apple Music 订阅才能生成确定性截图。
