# Plan 06 · 现场准备 UX（去任务化）

> **Audience:** 执行型 agent · `Agents.md` · iPhone 17

---

## 0. 问题

`PRODUCT_DEFINITION_V2.1`：现场准备是 **轻量阅读建议**，**不是**购物清单/待办；V2.1 **不做勾选完成**。  

当前 `ShowPreparationView` 使用：

- `checkedSuggestionCount` / `totalSuggestionCount`  
- 勾选行  
- 「差不多准备好了」完成态  

与产品语言冲突，用户会当成任务。

---

## 1. 目标

### 1.1 信息架构

```
[Tips 语气卡：轻轻确认，不是待办]
[分组建议列表：只读勾选 → 改为「标记有用」可选 或 纯阅读]
[可选：个人备注 notes]
[可选：准备提醒 Toggle + 时间]
```

### 1.2 去任务化（选一种，默认 A）

**A（推荐）：纯阅读 + 备注 + 提醒**

- 删除完成进度 `3/12`。  
- 行不再显示 checklist 圆圈；改为普通列表行。  
- 可保留「点按淡化/隐藏已不需要的建议」但不叫「完成」。  

**B：轻量「对我有用」星标**

- 不显示总数进度。  
- 不把全选当成功。

**禁止：** 保持「已确认 x/y」任务进度。

### 1.3 文案

- eyebrow 保持 `Tips · 出门前` 类。  
- message：强调从容，不制造消费焦虑（音乐节装备列表语气克制）。  
- 去掉「待办一样紧张」若仍在，可保留对比句，但 UI 不能像 Todo。

### 1.4 数据

- 若去掉勾选：`ShowPreparationPlan` 的 checked 存储可保留字段以免迁移，但 **UI 不读完成度**；或继续写但不展示 count。  
- **不要**做复杂 SwiftData migration 除非必要；未上线可直接改模型用法。  
- `ShowToolSummary.preparationStatus` 若展示「x/y 已确认」，改为：  
  - `已设提醒` / `未设提醒` 或 `有备注` / `可查看建议`  
  同步详情页/摘要文案。

### 1.5 提醒

- Toggle + 日期保留。  
- 与去程出门提醒并存可接受；文案写「出门前轻轻提醒一下」。

---

## 2. 文件

| 文件 | |
|------|--|
| `ShowToolViews.swift` (`ShowPreparationView`) | 主 |
| `ShowPreparation.swift` | plan 模型/勾选 API |
| `ShowToolSummary.swift` | 状态文案 |
| 详情/任何展示 preparationStatus 处 | 跟文案 |

---

## 3. 步骤

1. 读 `ShowPreparationView` + `ShowPreparationPlan.isChecked`。  
2. 按 A 去掉进度与 checklist 样式。  
3. 更新 `ShowToolSummary.preparationStatus`。  
4. 全局搜「已确认」「准备好了」用户文案。  
5. Build。  
6. 若有 preparation 测试，更新断言。

```bash
cd apps/ios && xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 期望 |
|---|------|
| 1 | 进入页看不到 x/y 完成进度 |
| 2 | 列表像阅读建议不是 Todo |
| 3 | 备注与提醒仍可用 |
| 4 | 摘要/详情状态文案不再像任务完成度 |
| 5 | 音乐节建议无胁迫消费语气 |

---

## 5. 禁止

- 购物车、电商链接  
- 把准备做成强制 checklist 成就系统  

---

## 6. 报告

选了 A 还是 B；`preparationStatus` 新文案；是否保留底层 checked 字段。
