# Plan 14 · 跨模块视觉与交互系统

> **Audience:** 执行型 agent · `Agents.md` · iPhone 17  
> **定位:** 统一「浮层 / 空态 / 底部安全区 / sheet 分层」，不改各业务规则。

---

## 0. 问题

1. 多处 sheet 纯黑贴舞台纯黑，浮层感差。  
2. `BSDrawerSheet` 仍可能 `Color.black`。  
3. `BSLayout.floatingTabBarClearance = 108` 为悬浮 Tab 预留，实际是系统 `TabView`，首页底部易空。  
4. 空态/错误/Loading 组件不统一。  
5. Toast 位置与 tab 重叠风险。

---

## 1. 目标

### 1.1 Sheet 分层标准（强制）

所有 **medium / 矮抽屉** sheet：

```swift
.presentationBackground(BSColor.surface)
// content root:
.background(BSColor.surface.ignoresSafeArea())
```

全屏工具 sheet（自带 `CurrentShowStageBackground` 的）：

- 不要强行 surface；保持舞台黑。  
- 可 `.preferredColorScheme(.dark)`。

### 1.2 更新点清单（逐个搜）

运行：

```bash
rg -n "presentationDetents|BSDrawerSheet|\\.sheet\\(" apps/ios/BeforeShow --glob '*.swift'
```

对每个 **非全屏舞台页** 的 sheet：

| 位置 | 动作 |
|------|------|
| `RootView` 工具目录 catalog | surface + presentationBackground |
| `DesignSystem.BSDrawerSheet` | surface + presentationBackground |
| 其他 `BSDrawerSheet` 调用方 | 自动受益 |
| Pro / 危险确认 sheet | 随 BSDrawerSheet |

**行卡片**在 surface 上：用 `BSColor.surfaceElevated` + `borderProminent`（工具目录已规划则对齐）。

### 1.3 顶缘高光（可选统一）

矮 sheet 顶部 28pt 白 10%→0 渐变，`allowsHitTesting(false)`。不要每个 sheet 复制花活；可在 `BSDrawerSheet` 做一次。

### 1.4 底部安全区

在 `DesignSystem.swift`：

```swift
enum BSLayout {
    /// 系统 TabView 内容底部留白（非悬浮玻璃 Tab）
    static let tabBarContentInset: CGFloat = 88
    // 若仍有 floatingTabBarClearance，标记 deprecated 并全局替换引用
}
```

替换：

```bash
rg -n "floatingTabBarClearance" apps/ios
```

所有引用改为 `tabBarContentInset`，数值 **先 88**；手测首页 Tips 不被 tab 挡住、也不要巨大空白。若 88 不够再调到 96，**禁止**无脑 +30 叠加大空白。

首页现有：

```swift
.padding(.bottom, BSLayout.floatingTabBarClearance + 30)
```

改为：

```swift
.padding(.bottom, BSLayout.tabBarContentInset)
```

### 1.5 空态统一

优先复用 `BSEmptyPanel`：

- icon + title + message + 可选主按钮  
- 各工具页空态能迁则迁，**不要**一次改所有文案业务含义（文案以各 plan 为准；本 plan 只统一 **组件**）。

### 1.6 Toast

- `bsToastOverlay` bottomPadding 考虑 tab：默认 ≥ 88。  
- 成功/失败色用既有 `BSToastTone`。

### 1.7 动效

- 仅：header 滚动背景、sheet present 系统默认。  
- 禁止新增大范围 spring 炫技。

---

## 2. 文件

| 文件 | |
|------|--|
| `DesignSystem.swift` | BSDrawerSheet、BSLayout、可选 Empty |
| `RootView.swift` | catalog sheet、bottom inset |
| 其它含 sheet/inset 的 View | 按 rg 结果最小改 |

---

## 3. 步骤

1. `rg` 列出 sheet 与 clearance。  
2. 改 `BSDrawerSheet` + `BSLayout`。  
3. 替换 clearance 引用。  
4. 修 catalog / 明显黑 sheet。  
5. Build。  
6. 手测：首页 `···`、Pro 墙、删除确认、设置清除。

```bash
cd apps/ios && xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 期望 |
|---|------|
| 1 | 工具目录 sheet 明显浅于舞台黑 |
| 2 | BSDrawerSheet 同类分层 |
| 3 | 首页底无巨大空洞；Tips/内容不被 tab 硬挡 |
| 4 | 全屏工具页仍是舞台感（未被错误涂成灰面板） |
| 5 | 编译通过 |

---

## 5. 禁止

- 白主题  
- 整页品牌彩虹渐变  
- 重写所有业务页 layout  
- 接入未使用的 `BSFloatingGlassTabBar`（除非产品明确要求；本 plan **不要求**） |

---

## 6. 报告

改了哪些 sheet；clearance 最终数值；截图可选。

---

## 附录 · 与历史 handoff 关系

若仍存在 `/tmp/beforeshow-handoff-sheet-visual/SHEET_VISUAL_PLAN.md`，以 **本文件为超集**；冲突时以本文件 + `BSColor.surface` token 为准。
