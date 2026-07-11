# Plan 13 · 设置与 Pro UX

> **Audience:** 执行型 agent · `Agents.md` · iPhone 17

---

## 0. 问题

1. Pro 价值说明要清楚：锁的是重复 AI/额度，不是本地碎片。  
2. 默认音乐平台路径：设置改了，搜歌要生效。  
3. 清除数据要足够吓人且可撤销确认。  
4. 反馈/关于信息完整即可，不堆营销。

---

## 1. 目标

### 1.1 设置列表信息架构

建议顺序（若已接近则微调文案）：

1. Pro 会员  
2. 默认音乐平台  
3. 隐私与本地数据  
4. 清除本地数据  
5. 意见反馈  
6. 关于开场前  

### 1.2 Pro

- `ProMembershipView`：说明 **解锁什么 / 不锁什么**。  
  - 解锁：重复生成候选曲目/视频等（以 `ProFeatureGate` 实际 feature 为准，读代码列举）。  
  - 不锁：已有现场、碎片添加、手动编辑。  
- 付费墙只在触发限制时出现；设置内是管理入口。  
- 恢复购买按钮若 StoreKit 已接则露出。

### 1.3 音乐平台

- 四选一：Apple Music / 网易云 / QQ / Spotify（以 `MusicPlatform` enum 为准）。  
- 保存后 `AppStorage` 立即影响候选曲目跳转。  
- 行内显示当前选择。

### 1.4 隐私与本地数据

- OCR 不上云、碎片引用相册等要点列表清晰。  
- 与 `SettingsSupport` 文案源一致，避免两处漂移——**单源**。

### 1.5 清除本地数据

- 二次确认：`BSDangerConfirmationSheet`。  
- 文案：删除所有现场、碎片、计划等且不可恢复；不删系统相册原图。  
- 成功后回到合理空态。

### 1.6 反馈 / 关于

- 反馈：邮件或表单保持可用；失败有提示。  
- 关于：版本号、标语「开场之前，先进入状态」。

---

## 2. 文件

| 文件 | |
|------|--|
| `SettingsViews.swift` | 主 |
| `SettingsSupport.swift` | 文案单源 |
| `ProSubscription.swift` / gate | 仅文案对齐 |
| `MusicPlatform.swift` | 仅必要时 |

---

## 3. 步骤

1. 读设置导航与 Pro gate 功能列表。  
2. 写清 Pro 边界文案。  
3. 平台选择与跳转联调。  
4. 清除数据确认。  
5. Build。

```bash
cd apps/ios && xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 期望 |
|---|------|
| 1 | Pro 页说清锁/不锁 |
| 2 | 改默认平台后搜歌跳对应平台（或 URL scheme） |
| 3 | 清除有二次确认 |
| 4 | 关于有版本 |
| 5 | 首页不硬推 Pro |

---

## 5. 禁止

- 假订阅、绕过 StoreKit 的假开通（DEBUG 本地 entitlement 除外且勿进 Release 文案）  
- 设置页塞功能大全入口墙  

---

## 6. 报告

Pro 功能列表最终文案；是否动 StoreKit。
