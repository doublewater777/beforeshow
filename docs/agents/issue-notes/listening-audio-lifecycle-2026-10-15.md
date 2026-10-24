# 播放行为与系统接入

## 原则

全曲由 `ApplicationMusicPlayer` 管理；试听使用 `AVQueuePlayer`、`MPNowPlayingSession` 自动发布 Now Playing 信息。播放状态从原生播放器读取，不另建播放状态机。

`AVPlayer` 负责激活音频会话、缓冲、队列推进和音频路由。中断由接入层处理：`AVPlayer` 被系统暂停后不会自己恢复，`ApplicationMusicPlayer` 也一样，两者都只保留跨中断的用户播放意图，检查系统的 `shouldResume` 后请求原生播放器恢复。共享的意图判断在 `ListeningPlaybackIntent`。

## 行为约定

| 场景 | 行为 |
| --- | --- |
| 来电、Siri 等临时中断 | 全曲与试听都在此前有播放意图、系统允许、用户未暂停时恢复原曲和位置 |
| 用户在其他 App 开始新的音频播放 | 不自行抢回声音；系统未允许恢复时保持暂停 |
| 中断前、期间或恢复请求排队时主动暂停 | 保持暂停，旧播放请求不能覆盖用户操作 |
| 耳机或蓝牙输出断开 | 系统暂停；取消待恢复意图，重新连接不自动播放 |
| 切换根 Tab、锁屏、切到后台 | 保持音频播放；页面动画按可见性暂停 |
| 暂停后再次播放 | 从当前曲目和位置继续 |
| 暂停时切歌 | 保持暂停 |
| 显式选择歌曲播放 | 播放所选歌曲；装载队列本身不启动播放 |
| 队列自然播完 | 停止，不额外循环；再次播放从保留的最后一首开始 |
| 停止按钮 | 停止播放，回到当前唱片第一首 |
| 重开 App | 恢复已保存的唱片、曲目和位置，不自动播放 |
| 从多任务界面划掉 App | 播放随进程结束；运行资源由系统回收，无需依赖退出回调清理 |
| 未开始播放的试听实例停止 | 不释放其他播放器持有的音频会话配置 |

## 播放按钮

播放按钮只表示播放器是否真的在发声：`.playing` 显示暂停，`.paused`、`.interrupted` 都显示播放。中断期间界面显示播放，用户点一次即请求恢复；不能把 `.interrupted` 当作"正在播放"。

锁屏、控制中心、耳机控制继续使用原生播放器和系统 Remote Command Center。演出时间表试听通过原生 Observation 接收状态变化，不轮询播放器。

## 依据

- [HIG: Playing audio](https://developer.apple.com/design/human-interface-guidelines/playing-audio)
- [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
- [AVPlayer.TimeControlStatus.paused](https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum/paused)
- [MusicPlayer.PlaybackStatus.interrupted](https://developer.apple.com/documentation/musickit/musicplayer/playbackstatus/interrupted)
- [Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)

项目最低版本为 iOS 17.0（ADR 0043），因此试听使用该版本支持的音频会话中断通知。
