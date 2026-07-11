# Plan 11 · 开屏与引导 UX

> **Audience:** 执行型 agent · `Agents.md` · iPhone 17

---

## 0. 问题

1. 引导极短，正确；但「先逛逛」进空首页后，价值说明不够。  
2. 开屏可加速点击，需保证不卡死 `onFinish`。  
3. 文案需对齐 App Store 副标题 vs 氛围句（产品 ADR：可区分）。

---

## 1. 目标

### 1.1 开屏 `SplashView`

- 保持暗场 + 品牌渐变字。  
- 动画结束后必调 `onFinish`；点击加速不双调（已有 `didFinish` guard 则保留）。  
- 无障碍：标题可读。

**本任务不做：** 大改动画时长、加营销轮播。

### 1.2 引导 `OnboardingPlaceholderView`

仅未完成 onboarding 且 `shows.isEmpty` 时出现。

- 主 CTA：`添加第一场现场` → 现有 sheet。  
- 次 CTA：`先逛逛` → `hasCompletedOnboarding = true`。  
- 文案保持产品感，不写功能大全。

**增强（最小）：** 在次 CTA 下加一行 tertiary：

`随时可以在首页右上角添加现场。`

### 1.3 空首页衔接

当 onboarding 完成但无现场，`CurrentShowEmptyStateView`：

- 确认主按钮 `添加现场` 显眼。  
- message 两行足够；可加一句：`放进来之后，会陪你慢慢靠近那一场。`  
- 与引导语气一致，避免两套话术冲突。

### 1.4 完成后不再出现

- `hasCompletedOnboarding` 为 true 后，即使后来删光现场，也 **不要** 再出引导页（只出空态）——与现逻辑对齐并验证。

---

## 2. 文件

| 文件 | |
|------|--|
| `RootView.swift` (`SplashView`, `OnboardingPlaceholderView`, `CurrentShowEmptyStateView`) | 主 |
| `StartupRouting.swift` | 仅逻辑不一致时 |

---

## 3. 步骤

1. 读 splash / onboarding 条件。  
2. 引导补充一句。  
3. 空态文案统一。  
4. 验证删光现场不回引导。  
5. Build。

```bash
cd apps/ios && xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 期望 |
|---|------|
| 1 | 冷启动见开屏后进引导或主页 |
| 2 | 添加第一场 / 先逛逛都可用 |
| 3 | 先逛逛后是空态不是死黑屏 |
| 4 | 完成 onboarding 后删现场不回引导 |
| 5 | 开屏不卡死 |

---

## 5. 禁止

- 多页功能教程轮播  
- 开屏强推 Pro  

---

## 6. 报告

改动的文案字符串；是否动动画。
