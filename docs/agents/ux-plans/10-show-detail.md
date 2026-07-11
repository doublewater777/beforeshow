# Plan 10 · 现场详情 UX

> **Audience:** 执行型 agent · `Agents.md` · iPhone 17

---

## 0. 问题

1. 详情同时承担「管理」与「工具入口」，与首页 `···` 重复但状态摘要有价值。  
2. 自定义隐藏 nav bar 时返回/安全区要可靠。  
3. 非当前现场时「设为当前」应比首页列表更醒目。  
4. 工具行状态文案应与 `ShowToolSummary` 一致且人话。

---

## 1. 目标

### 1.1 页结构

```
[Hero: 封面 + 名称 + 元数据 + 倒计时]
[管理行: 编辑 | 设为当前/当前标记]
[工具列表: 5 工具 + 状态 subtitle]
[变更说明 caption]
[危险区: 延期 / 取消 / 删除 — 可折叠或靠后]
```

### 1.2 设为当前

- 非当前：主按钮样式 `设为当前现场`（实心或描边清晰）。  
- 当前：显示 `当前现场` 不可点或轻样式。  
- 成功 toast。

### 1.3 工具列表

- 四行与首页目录一致：候选曲目、去程计划、现场准备、现场碎片。  
- subtitle 用 `ShowToolSummary` 状态；若准备状态在 Plan 06 已改，这里自动跟。  
- NavigationLink 进全屏工具页（详情在 NavigationStack 内，push 即可；**不要**再套 medium sheet）。

### 1.4 返回

- 若 `toolbar(.hidden)`：提供左上透明/圆形返回按钮 `chevron.left`，`dismiss()`。  
- 滑动返回手势保持。

### 1.5 危险操作

- 延期/取消/删除保持确认 sheet。  
- 删除文案说明碎片与计划会删、相册原图不删。

### 1.6 Hero

- 无封面：兜底封面策略已有则保持，勿暴露 broken。  
- 倒计时与首页语义一致（已结束/取消文案可读）。

---

## 2. 文件

| 文件 | |
|------|--|
| `ShowLibraryViews.swift` (`ShowDetailView`) | 主 |
| `ShowToolSummary.swift` | 仅文案 |

---

## 3. 步骤

1. 读 `ShowDetailView` body。  
2. 返回按钮。  
3. 强化设为当前。  
4. 工具列表与目录对齐命名。  
5. Build + 从首页海报点进再返回。

```bash
cd apps/ios && xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 期望 |
|---|------|
| 1 | 海报进入详情可稳定返回 |
| 2 | 非当前可一键设为当前 |
| 3 | 五工具可进且全屏 |
| 4 | 删除/取消有确认 |
| 5 | 状态 subtitle 人话 |

---

## 5. 禁止

- 把详情改成第二个首页大海报倒计时复制粘贴  
- 在详情 medium sheet 里嵌套推工具  

---

## 6. 报告

返回实现方式；设为当前 UI。
