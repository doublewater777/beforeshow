# Plan 09 · 我的现场 UX

> **Audience:** 执行型 agent · `Agents.md` · iPhone 17

---

## 0. 问题

1. **设为当前** 主要靠左滑，可发现性差。  
2. 「当前」标记可能不够强。  
3. 取消/延期在列表中的区分弱。  
4. 空态/说明文案可能残留「演出」等避免词。

---

## 1. 目标

### 1.1 设为当前（可发现）

在每条 **非当前** 行上增加一种明显方式（实现 **至少一种**，推荐两种都做轻量）：

1. **行内：** 当前行显示 pill `当前`；非当前显示文字按钮 `设为当前`（或 context menu）。  
2. **长按菜单：** `设为当前` / `查看详情`。  
3. 保留左滑（兼容已学会的用户）。

点击「设为当前」：调用现有 `selectCurrent`，toast `已设为当前现场`。

### 1.2 当前标记

- pill：背景 `white.opacity(0.12)`，文案 `当前`，放在标题旁。  
- 不要只靠颜色点。

### 1.3 分组

保持：即将开始 / 已结束 / 变更。  

- **变更** 组内：取消 vs 延期用 subtitle 区分（`已取消` / `待定` / `延期至 x`）。  
- 取消现场仍显示，不隐藏。

### 1.4 排序

- 确认与 `CurrentShowSelector` / 列表 sort 一致：即将开始按日期近→远。  
- 当前现场若在即将开始，可置顶（若未置顶，**做最小置顶**）：当前 ID 排在 upcoming 第一。

### 1.5 文案

- 全局用户可见「演出」→「现场」（空态 message 检查）。  
- 底注：`左滑或点「设为当前」可切换当前现场`。

### 1.6 空态

- 主按钮添加现场。  
- message 对齐产品语气。

---

## 2. 文件

| 文件 | |
|------|--|
| `ShowLibraryViews.swift` (`MyShowsListView`, `ShowRowView`) | 主 |
| `CurrentShowSelection.swift` | 仅 selector bug |

---

## 3. 步骤

1. 读 `ShowRowView` 与 `selectCurrent`。  
2. 加 pill + 设为当前按钮/菜单。  
3. 当前置顶（upcoming）。  
4. 文案清理。  
5. Build + 手测双现场切换。

```bash
cd apps/ios && xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 期望 |
|---|------|
| 1 | 不依赖左滑也能设为当前 |
| 2 | 当前行有明确 pill |
| 3 | 切换后首页跟当前现场 |
| 4 | 取消现场仍在列表且可识别 |
| 5 | 无「演出」用户文案（尽量） |

---

## 5. 禁止

- 归档系统（V2.1 不做）  
- 复杂筛选器/标签  

---

## 6. 报告

设为当前的交互形态；是否置顶。
