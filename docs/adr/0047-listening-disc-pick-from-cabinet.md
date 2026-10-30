# Listening disc pick from cabinet

## 决定

- 「听」唱片柜顶部提供「帮我挑一张」：从**当前浏览范围**抽出一张现场唱片封套，确认后经现有「装入播放机」路径装入并开播。
- 单位是唱片，不是单曲。`.all` 的候选为现场预习合辑与所有已连接艺人碟；`.artist` 只含该艺人。
- 挑选偏好未充分听过的封套，并避开刚抽过的短历史；不改变每日 featured 头碟，不改听歌提醒队列。
- 播放只走 `ListeningRoomCoordinator.loadPlayableDisc`，遵守 ADR 0040；不开启 MusicKit shuffle。

## 明确不是

- 不是 Blind Listening / 猜歌（ADR 0032）。
- 不是提醒队列或通知推荐（ADR 0045 / 0037）。
- 不是推荐流、随机播放或歌单产品面。
