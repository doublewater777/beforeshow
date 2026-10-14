# Toolbar chrome tint leak (2026-10-14)

## Symptom

时刻表「演出详情」sheet 右上角仍是黄色「完成」文案，而不是中性图标。

## Root cause

完成 chrome 被涂成了 feature accent：

- `TimetablePerformanceInspectorSheet` 用 `Text("完成")` + `foregroundStyle(TimetableStyle.mine)`
- `TimetableStyle.mine == BSColor.Stage.accent`（暖金/黄）
- 这不是系统自动传色，是主动把内容强调色套到了导航栏 chrome 上

同类坑：父级 `.tint(TimetableStyle.mine)` / `.tint(BSColor.Accent.warm)` 也会染到未显式设色的 toolbar `Button`。

## Rule

- 需要图标化「完成」时：用 `checkmark` + `BSColor.Stage.foreground`，`accessibilityLabel` 仍是「完成」
- 真正的关闭控件才用 `BSChromeToolbarCloseButton` / `xmark`
- **不要**用 `TimetableStyle.mine`、`BSColor.Stage.accent`、`BSColor.Accent.warm` 给 dismiss/done chrome 上色
- Accent / mine 只给内容区动作（想看、添加、强调 CTA），不给导航栏 chrome
- 改成图标 ≠ 改语义：完成还是完成，关闭还是关闭

## Fix landing

- `apps/ios/BeforeShow/Features/Timetable/TimetablePerformanceInspectorSheet.swift`
