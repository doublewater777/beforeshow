# Plan 07 · 现场碎片 UX

> **Audience:** 执行型 agent · `Agents.md` · iPhone 17

---

## 0. 问题

1. 从 Tips「记一笔」进入后，新增路径可能偏长。  
2. 相册引用失效时易破图无说明。  
3. 空态偏「空文件夹」。  
4. 录音权限/失败反馈要稳。

---

## 1. 目标

### 1.1 空态

文案方向：

- 标题：`还给这场留一点痕迹`  
- 副文：`OOTD、路上吃到的、朋友合照、散场那句话……只属于这一场。`  
- 主按钮：`记一笔` → **直接**进入新建流程（现有编辑 sheet/页），少一层菜单若可能。

### 1.2 列表

- 时间序（已有则保持）。  
- 无分类标签（产品约束）。  
- 每条：图/文/语音标识清晰。

### 1.3 失效媒体

- 图片/视频加载失败：显示占位 + 文案 `原相册内容可能已删除`，不要崩溃或纯黑。  
- 不自动删除碎片。

### 1.4 从 Tips 进入

- `ShowFragmentListView` 可接受可选参数 `opensComposerOnAppear: Bool = false`。  
- 首页 Tips `.showFragments` 打开 sheet 时传 `true`，appear 一次后打开新建并复位。  
- 避免每次返回都弹。

### 1.5 录音

- 无麦克风权限：引导去系统设置，不静默失败。  
- 录制中可见波形/时长（已有则保留）。  
- 删除碎片时删沙盒音频（已有逻辑则验证）。

### 1.6 隐私

- 不做分享按钮（V2.1）。  
- 文案避免「动态/广场」。

---

## 2. 文件

| 文件 | |
|------|--|
| `ShowToolViews.swift` (`ShowFragmentListView` 等) | 主 |
| `ShowFragment.swift` / Media services | 失效占位 |
| `RootView.swift` | Tips 打开碎片时传参（若 sheet 在 Home） |

---

## 3. 步骤

1. 读碎片列表与新建/编辑 sheet。  
2. 空态文案 + 主 CTA。  
3. 缩略图失败占位。  
4. `opensComposerOnAppear`。  
5. 权限失败路径。  
6. Build + 手测。

```bash
cd apps/ios && xcodebuild -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 4. 验收

| # | 期望 |
|---|------|
| 1 | 空态有温度、一点就新建 |
| 2 | Tips 记一笔 → 少步到达编辑 |
| 3 | 失效图有说明 |
| 4 | 无分享入口 |
| 5 | 录音无权限时有提示 |

---

## 5. 禁止

- 社交 feed、公开、跨现场复制碎片  
- 把碎片做成日记 App 信息架构  

---

## 6. 报告

是否加 `opensComposerOnAppear`；占位实现方式。
