# Plan 12 · 本地通知 UX

> **Audience:** 执行型 agent · `Agents.md` · iPhone 17

---

## 0. 问题

1. 通知文案偏品牌，点进 App 后可能只是冷首页，**没有落到行动**。  
2. 切换当前现场时取消/重排要正确。  
3. 权限拒绝后设置内缺引导（若已有则加强）。

产品节点（保持）：

- T-14 20:00  
- T-1 20:00  
- 当天开场前 3 小时  
- 缺开场时间兜底当天 12:00（产品说明）

---

## 1. 目标

### 1.1 通知内容

可略具体化（仍短）：

| 节点 | 标题/body 方向 |
|------|----------------|
| T-14 | 开场之前，先进入状态 · 可以先听听可能的曲目 |
| T-1 | 明天见 · 确认一下怎么去 |
| T-3h | 快开场了 · 看出门时间和准备 |

不要变成营销推送堆砌。

### 1.2 深链 / 落地（关键）

通知 `userInfo` 带：

```swift
["showID": uuidString, "destination": "candidateSongs" | "outboundPlan" | "home"]
```

App 启动或 `onOpenURL`/通知响应：

1. 将该 show 设为当前（若仍存在）。  
2. 打开对应工具 sheet 或首页（destination）。  

实现位置：查 `LocalNotificationScheduling.swift`、`BeforeShowApp`、`RootView` 通知 delegate。

**若工程尚无 UNUserNotificationCenterDelegate：** 最小接入：

- App 启动时 `setDelegate`  
- `didReceive` / cold start `getResponse` 读 userInfo  

### 1.3 调度规则（勿破坏）

- 只围绕 **当前现场**。  
- 切换当前：取消旧、排新。  
- 错过的节点不补发。  
- 添加现场成功后再请求权限。

### 1.4 权限拒绝

设置 → 隐私说明或通知相关行：`去系统设置开启通知` 打开 `UIApplication.openSettingsURLString`。

---

## 2. 文件

| 文件 | |
|------|--|
| `LocalNotificationScheduling.swift` | 主 |
| `BeforeShowApp.swift` / `RootView.swift` | delegate 与落地 |
| `SettingsViews.swift` | 权限引导 |
| 测试若有通知测试 | 更新 |

---

## 3. 步骤

1. 读现有 schedule/cancel API。  
2. 写入 userInfo + 文案微调。  
3. 接入点击落地。  
4. 设置页引导。  
5. Build；模拟器通知受限，代码路径用单元测试或 DEBUG 日志验证解析。

```bash
cd apps/ios && xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 期望 |
|---|------|
| 1 | 新当前现场会排程（DEBUG 可打印 pending） |
| 2 | 切换当前取消旧通知 |
| 3 | userInfo 含 showID + destination |
| 4 | 点击路径：解析函数有单测或可调用 DEBUG 入口 |
| 5 | 权限拒绝时设置可跳系统 |

---

## 5. 禁止

- 营销通知风暴、每日推送  
- 非当前现场批量通知  
- 服务端推送（本产品本地通知） |

---

## 6. 报告

落地如何实现；文案最终值；是否加测试。
