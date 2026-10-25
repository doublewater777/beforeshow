# Listening playback rules

「听」的播放行为以 Apple 的播放器和常见播放器习惯为准：完整播放交给 `ApplicationMusicPlayer`，试听交给 `AVQueuePlayer` + `MPNowPlayingSession`。App 只补 Apple 要求 App 自己决定的部分，不再为个别入口写特殊分支。改动播放器时以本表为准，每条规则都有以规则命名的测试。

## 规则

| 场景 | 规则 | 归属 |
| --- | --- | --- |
| 中断（来电、Siri、闹钟、其他 App） | 开始即暂停并显示中断；结束时仅当系统给出 `shouldResume` 且用户期间没有暂停才续播。用户在中断中按暂停优先于系统续播。`appWasSuspended` 不是中断，忽略 | 完整播放：系统。试听：`PreviewListeningPlaybackService` |
| 后台与锁屏 | 播放继续，暂停保持；切 Tab、进后台都不改变传输状态，回到前台重读播放器 | 系统 + `audio` 后台模式；Deck `resynchronize()` |
| 耳机或蓝牙断开 | 立即暂停；重新连接不自动播放，也不被未完成的中断续播唤醒 | 完整播放：系统。试听：服务 |
| 锁屏与控制中心 | 与 App 内按键同语义；显示曲名、艺人、唱片名与封面；试听在首尾曲时禁用上一首或下一首 | 完整播放：系统。试听：`MPNowPlayingSession` |
| 切歌 | 不改变播放或暂停：已装队列时始终用原生队列导航（`skipToNextEntry` / `advanceToNextItem` / `queue.currentEntry`），暂停中切歌仍暂停并保留 Now Playing；没有队列时只移动光标 | Deck |
| 整张放完 | 等同停止：回到当前唱片第一轨，进度归零，释放播放器 | Deck |
| 停止 | 唱片保留，回到第一轨，进度归零 | Deck |
| 失去完整播放能力 | 结束完整播放会话：保留唱片与当前曲目，进度归零（ADR 0036） | Deck `endSession()` |
| 重新打开 App | 恢复已装入唱片、曲目与位置，不自动播放；位置超出试听片段长度时从头播放 | Coordinator + 试听服务 |
| App 内多个声源 | 同一时刻只有一个发声：开始前取得发声权，其他声源暂停。默认不自动恢复；时刻表试听属于临时插播，结束后只恢复仍装着同一歌曲、同一唱片且保持暂停的原「听」会话 | `AppAudioSession.claimFocus` + `TimetablePreviewPlayer` |
| 开盖 | 暂停，保留曲目与位置 | Coordinator |

「上一首在播放超过 3 秒时回到本曲开头」不采用：`AVQueuePlayer` 没有原生支持，完整播放的锁屏行为也由系统决定，手写会让两种音源分叉。

## 声音会话与发声权

`AppAudioSession.Owner` 列出所有会发声的来源：「听」、时间表试听、回忆视频。

- **租约**：来源在可能发声期间持有 `playback`，每个来源各自持有，释放一个不会结束另一个。暂停时保留租约，使 App 仍是 Now Playing 候选；停止才释放。没有租约时回到 `ambient` + `mixWithOthers`。
- **发声权**：来源在真正发声前调用 `claimFocus`，同步通知其他来源暂停。默认不自动恢复；时刻表临时试听结束时，由 `TimetablePreviewPlayer` 检查原「听」会话仍未改变后明确恢复。

从外部恢复的完整播放（锁屏直接播放）不经过 App 代码，不会主动取得发声权；此时正在发声的试听拥有自己的 Now Playing，冲突概率低，不为此增加观察。

## Deck 的命令层

原生播放器在缓冲或加载期间不会立即报告「将要播放」，因此 Deck 保留一层未确认命令（`command`），让按键在点击当下翻转：

- `play` / `pause` 在播放器确认后清除；播放器 2 秒内没有确认时以播放器为准，中断期间除外。
- 用户的暂停若与系统续播竞争，暂停优先。
- 自己发起的导航完成前，光标不跟随播放器；之后由播放器决定当前曲目。

这一层只表达用户意图，不复制播放器状态；传输状态始终读自播放器。

## 中断时的播放控制

`.interrupted` 保留为原生中断状态，唱片停止旋转，按钮提供播放操作。用户点击一次就请求 `play()`；请求尚未被播放器确认时仍显示中断，不投影为缓冲或播放。

准备、缓冲、快进中的暂停操作保留现有命令反馈。完整播放暂由 MusicKit 处理自动续播；Apple 文档只说中断后「可能自动恢复」，没有保证一定会或一定不会。新增全曲主动续播策略前，先用真机确认缺失行为；不通过延时猜测暂停来源，也不因回到前台而强制播放。

## 迁移

iOS 27 SDK 将 `AVAudioSession.interruptionNotification` 的 type、option、reason 键标为弃用，改用 `didBecomeInactiveNotification` 与 `resumptionRecommendationNotification`。部署目标为 iOS 17.0（ADR 0043），暂用旧 API，不写两套并存的实现；最低版本升到 iOS 27 时整体迁移试听服务的中断处理。

## 验证

`ListeningDeckTests`（切歌、放完、结束会话）、`PreviewListeningPlaybackServiceTests`（中断、耳机、挂起恢复、发声权、超出片段的恢复位置、首尾曲）、`AppAudioSessionTests`（租约与发声权）、`ListeningPhase678Tests`（失去完整播放能力）覆盖上表。完整播放的切歌与 `queue.currentEntry` 跳转需在真机上验证，模拟器不能播放 Apple Music 曲目。
