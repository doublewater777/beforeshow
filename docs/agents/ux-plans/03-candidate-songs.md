# Plan 03 · 歌单猜想 UX

> 状态：**以 ADRs 0014–0020 + `CONTEXT.md` 为准**。旧「候选曲目 / 播放预留 / 默认音乐平台试听」方向已废止。

## 当前约定（摘要）

- App 内名称：**歌单猜想**（猜一份歌单）；不用「候选曲目」
- 行字段：歌名、艺人、**四档曲目档位**、**曲目短因**、爱心**最想看**（可多选）
- 三面：首页歌单卡 + 歌单 sheet（含 sheet 内编辑）+ 分享层海报；对齐 home feature-cards 原型 1:1（ADR 0019）
- 生成：一键猜；重猜确认；保留手加 + 最想看；缺档位/短因时客户端补全（ADR 0020）
- 不做：音乐平台试听跳转、官方 setlist 承诺、逐条来源 URL、数值置信度、长推荐文

## 文件

- `apps/ios/BeforeShow/ShowToolViews.swift`（`CandidateSongsView`）
- `apps/ios/BeforeShow/SetlistPrototypeChrome.swift`
- `apps/ios/BeforeShow/CandidateSongs.swift` / `CandidateSongsSession.swift`
- 术语：`CONTEXT.md`；决策：`docs/adr/0014`–`0020`
