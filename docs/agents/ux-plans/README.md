# BeforeShow UX Plans（给执行型 agent）

每个文件是一份 **可独立丢给低智能 coding agent** 的实现计划。  
风格对齐既有 handoff：范围硬切、文件白名单、步骤、禁止项、验收表。

## 怎么用

1. 一次只给 agent **一个** plan 文件全文。  
2. 附上仓库根 `Agents.md` / `AGENTS.md`。  
3. 要求：严格按文档、手术式改动、iPhone 17 `xcodebuild`。  
4. 完成后按文末验收表勾选。

## 建议执行顺序（依赖）

| 顺序 | 文件 | 优先级 | 依赖 |
|------|------|--------|------|
| 1 | `01-home-current-show.md` | P0 | 可先做；与 05 有衔接点 |
| 2 | `05-departure-plan.md` | P0/P1 | 当天提醒卡依赖已保存出门方案 |
| 3 | `08-add-show.md` | P0/P1 | 主转化 |
| 4 | `12-notifications.md` | P1 | 最好在 01 稳定后 |
| 5 | `03-candidate-songs.md` | P1 | |
| 6 | `09-my-shows.md` | P1 | |
| 7 | `10-show-detail.md` | P1 | |
| 8 | `06-show-preparation.md` | P2 | |
| 9 | `07-show-fragments.md` | P2 | |
| 10 | `11-onboarding-splash.md` | P2 | |
| 11 | `13-settings-pro.md` | P2 | |
| 12 | `14-cross-cutting-visual.md` | P2 | 可最后统一视觉 |

> **已移除：** `02-tonight-first-listen.md`（「今晚先听」产品与代码均已删除，勿再实现）。

## 全局约束（所有 plan 默认继承）

- App 未上线，不需要向后兼容。  
- Simulator：`platform=iOS Simulator,name=iPhone 17`。  
- 产品语言：现场 / 进入状态 / Tips 单条；不做工具仪表盘、打卡任务、社交、验票、歌词、真导航。  
- 领域术语见 `CONTEXT.md`；产品边界见 `PRODUCT_DEFINITION_V2.1.md`。  
- 主代码在 `apps/ios/BeforeShow/`。

## 相关但独立的既有 plan

- 工具 sheet 目录架构：历史 handoff（`RootView` catalog → 全屏工具）  
- Sheet 视觉分层：`/tmp/beforeshow-handoff-sheet-visual/SHEET_VISUAL_PLAN.md`（若仍在）→ 细节并入 `14-cross-cutting-visual.md`
