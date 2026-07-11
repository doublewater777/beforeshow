# Plan 03 · 候选曲目 UX（已实现方向）

> 状态：**核心 UI 已按歌单原型落地**（`CandidateSongsView`）。下文为产品约定，后续只做修补。

## 已落地

- 猜歌单 hero：3:4 海报、标题、首数、操作区（播放预留 / 复制 / 分享 / 编辑）
- **无序号**、无行左小图；多艺人「全部 + 艺人」筛选，单艺人不显示筛选
- **编辑** → sheet：List 删除 + 拖动排序 + 添加入口
- **添加** → sheet：歌名 + 艺人
- **复制** 纯文本；**分享** 文本 + 简单卡片图
- 去掉显眼 Tips 卡；重新生成仍需确认
- 全局 `order` 作为演出顺序

## 后续可选

- 分享卡更精致 / 保存相册
- 播放接入
- 编辑弹窗内改歌名（现 ··· 仅移除确认；可补编辑信息）
- 音乐节艺人关注管理

## 文件

- `apps/ios/BeforeShow/ShowToolViews.swift`（`CandidateSongsView` 等）
- 原型：`apps/ios/BeforeShow/prototypes/candidate-songs-playlist.html`
