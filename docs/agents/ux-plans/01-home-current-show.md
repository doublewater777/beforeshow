# Plan 01 · 首页「当前现场」UX

> **Audience:** 低智能 / 执行型 coding agent  
> **状态：** 主路径已实现（`RootView` 主行动互斥 + 结束边界按类型时长估算）。  
> **Simulator:** iPhone 17 · **规范:** 仓库根 `Agents.md`

---

## 0. 背景

首页（`CurrentShowHomeView` / `CurrentShowContentView` in `RootView.swift`）主视觉已是：

海报 3:4 → 倒计时 → Tips（有则显示）→ `···` 工具目录

**用户问题：**

1. 倒计时 + Tips 常在首屏下方，行动区难发现。  
2. **>14 天** `ShowTipsResolver` 返回 nil → 首页只剩海报+数字，新用户不知道能干什么。  
3. **当天**有已保存出门方案时，只有弱 Tips，没有「出门时间 + 打开地图」情境卡（见 CONTEXT「出行提醒」）。  
本 plan 负责首页信息架构与当天/冷启动展示。**不要**实现或挂载「今晚先听」（该模块已删除）。

---

## 1. 目标行为

### 1.1 信息架构（从上到下，固定）

```
[顶栏 overlay: 当前现场 | + | ···]
[海报 3:4 → 点进 ShowDetailView]
[倒计时 + helperText]
[若当天且有已保存出门方案 → 出行提醒卡]   // 优先于普通 Tips
[否则若有 ShowTip → Tips 卡]             // 现有 CurrentShowTipsCard
[否则若 dayDistance > 14 → 冷启动轻提示卡] // 新
[底部 tab 安全区]
```

**规则：**

- **同时最多一条主行动区**：出行提醒 > Tips > 冷启动。不要三条叠满。  
- 出行提醒显示时，**不要再显示**同主题的 outbound Tips（避免重复）。  
- 冷启动 **仅当** `tip == nil` 且 `phase.kind == .before` 且 `phase.dayDistance > 14`。  
- 延期/取消/已结束：无 Tips、无冷启动（与 resolver 一致）；当天/散场后走 Tips 逻辑。

### 1.2 出行提醒卡（当天 + 已保存出门方案）

**显示条件（全部满足）：**

```
phase.kind == .today
&& Date() < phase.effectiveStartTime  // 开场前
&& roundTripPlan.hasSavedDeparturePlan
&& leaveAt / mode / duration / arriveAt 可用
```

**内容（一行主文案 + 短 CTA）：**

- 主文案示例：`18:20 出门 · 地铁约 35 分钟 · 预计 18:55 到`  
  （用 `RoundTripPlan` 已有字段；时间格式 `HH:mm`，locale `zh_CN`）  
- CTA：`打开地图` → 调用与去程页相同的打开地图逻辑（**不要复制糊一套**；抽或复用 `RoundTripPlanView` / plan 上已有方法）  
- **不要**做「已过出门时间 / 该出门了」分支：不判断用户是否真出门，也不根据 `now > leaveAt` 换文案；当天统一用出行提醒即可。

**视觉：** 与 Tips 同级玻璃卡，可略强调（边框 `travel` accent 低透明度）。不要做成第二海报。

### 1.3 冷启动卡（>14 天）

**文案（固定，勿改花哨）：**

- message: `离开场还有一阵。想的话，可以先整理一下候选曲目。`  
- button: `去看看`  
- action: 打开候选曲目工具（`HomeTipTool.candidateSongs`），与 Tips 同 sheet 路径。

### 1.4 不要做

- 不要恢复横向工具 shortcut 条（CONTEXT：首页不堆工具板）。  
- 不要多条 Tips。  
- 不要改海报 3:4、倒计时字体大改。  
- 不要改 `ShowTipsResolver` 的天数窗口规则（冷启动是 **UI 层** 补充，不是改 resolver >14 返回 tip）。

---

## 2. 改哪些文件

| 文件 | 操作 |
|------|------|
| `apps/ios/BeforeShow/RootView.swift` | **主改** |
| `apps/ios/BeforeShow/ShowToolSummary.swift` 或 `RoundTripPlan.swift` | 仅当打开地图逻辑需要抽出 **最小** 复用时 |
| `ShowTips.swift` | **禁止改** resolver 规则 |

---

## 3. 实现步骤

### Step A — 查数据

在 `CurrentShowContentView`（或 Home）已有 `@Query roundTripPlans`：

```swift
private var roundTripPlan: RoundTripPlan? {
    roundTripPlans.first { $0.showID == show.id }
}
```

确认 `RoundTripPlan` 属性：`hasSavedDeparturePlan`、`departureLeaveAt`、`savedDepartureMode`、`departureDurationMinutes`、`departureArriveAt`（以源码为准，名称若不同用实际属性）。

### Step B — 计算 `homeAction`

用 enum 避免 if 金字塔：

```swift
private enum HomePrimaryAction: Equatable {
    case departureAssistant(plan: RoundTripPlan) // 或拆成 display fields
    case tip(ShowTip)
    case coldStart
    case none
}
```

优先级：departure → tip → coldStart → none。

### Step C — UI

在倒计时下方：

```swift
switch homeAction {
case .departureAssistant(...):
    DepartureAssistantCard(...) // private struct in RootView.swift
case .tip(let tip):
    CurrentShowTipsCard(tip: tip) { onOpenTool(...) }
case .coldStart:
    // 可复用 CurrentShowTipsCard 外观，构造临时 ShowTip
    // ShowTip(message: "...", buttonTitle: "去看看", action: .candidateSongs)
case .none:
    EmptyView()
}
```

若 `ShowTip` 可直接构造 cold start，优先复用 `CurrentShowTipsCard`，**少一个组件**。

### Step D — 打开地图

找到 `RoundTripPlanView` 或相关 `openMap` / `openDepartureMap` 实现，抽成：

- `enum DepartureMapOpener` 或 `RoundTripPlan` 扩展方法 `openInMaps()`  

首页卡片 CTA 调用同一路径。失败 toast 与去程页一致。

### Step E — 编译与手测

```bash
cd apps/ios
xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 步骤 | 期望 |
|---|------|------|
| 1 | 现场在 20 天后 | 无 Tips；有冷启动卡；点「去看看」进曲目 |
| 2 | 现场在 10 天内无曲目 | 曲目 Tips（现有文案） |
| 3 | 当天 + 已保存出门方案 + 未开场 | 出行提醒卡；无 outbound Tips 重复 |
| 4 | 点打开地图 | 系统地图或既有兜底 |
| 5 | 已过 leaveAt 仍未开场 | **仍用同一套出行提醒文案**，无「该出门了」变体 |
| 6 | 海报/倒计时/3:4 | 未破坏 |
| 7 | `···` 目录→全屏工具 | 状态机未坏 |

---

## 5. 禁止

- 改 Tab 结构、设置、添加现场流程  
- 大重构 `CurrentShowTimeState`  
- 引入新依赖  

---

## 6. 完成后报告

改了哪些符号；出行卡是否与 Tips 互斥；地图复用方式；手测表。
