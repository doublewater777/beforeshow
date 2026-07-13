# Issue #43 · 首页顶部重构与封面驱动全面屏背景

两个独立可构建、可视觉评审的切片。Slice 1 重做顶部（Poster Stage + 倒计时精简）；Slice 2 把首页背景换成封面驱动的全面屏舞台。Tips / 工具区 / 出行小助手 / 当前现场选择逻辑 / SwiftData 全部不动。

## 已核对的关键事实
- 首页视图 `CurrentShowContentView`（`RootView.swift:155`）。当前顶部 `compactHeader`（`RootView.swift:376`，52×69 小封面 + 标题/日期/场馆，NavigationLink→ShowDetailView）即要删除的「顶部工具栏/紧凑卡片」。
- 倒计时 `countdownHero`（`RootView.swift:440`）= `countdownEyebrow`（`RootView.swift:805`，"还有/就是今天/散场后…"）+ `countdownDisplay`（`RootView.swift:461`）。eyebrow 即将移除的「重复生命周期标签」。
- 背景 `CurrentShowStageBackground`（`DesignSystem.swift:131`，紫/绿/红泛光）= Slice 2 替换目标。已有未被任何处使用的 `CurrentShowAmbientBackground`（`DesignSystem.swift:344`，封面模糊回声）可安全演进。
- 封面组件 `ShowCoverImageView`（`DesignSystem.swift:637`），走 `ImageCache.shared`（`DesignSystem.swift:688`，NSCache+URLSession）——环境光复用此路径，不引入第二个网络客户端；占位回声 `ShowCoverPlaceholderView`（`DesignSystem.swift:609`）自动兜底。
- 概念 C 原型：`apps/ios/design-exploration/onboarding-poster-stage-v2.html` 的 `HomeScreenC`（行 756）。关键 token：封面满宽 3:4、28pt 圆角；更多按钮 44×44 圆形（`.native-more`，行 461）；倒计时仅 `76`+`天`；封面-倒计时 `space-5`≈20pt；环境回声 `blur(38) saturate(.82) opacity(.22)`；封面顶 scrim 0.52 保证状态栏对比。
- 可复用面：编辑 `ShowDraftEditorView`（`AddShowFlowViews.swift:606`）；选当前 `CurrentShowSelection.select`（用法见 `ShowLibraryViews.swift:189`）；删除 `LocalAppDataDeletionService.deleteShow`（`ShowLibraryViews.swift:502`）；确认/延期 sheet `BSDangerConfirmationSheet` / `PostponeShowSheet`（`ShowLibraryViews.swift`）；保存编辑 `apply(draft)`（`ShowLibraryViews.swift` ShowDetailView 内）。

## Slice 1 · 顶部 Poster Stage + 倒计时精简
改 `CurrentShowContentView`（`RootView.swift`）：

1. **删除 `compactHeader`** 及其在 `body` 的引用（`RootView.swift:327-329`）。
2. **新增 `posterStage`** 替换其位置：
   - `NavigationLink { ShowDetailView(show: show) } label: { 封面 }`，保留封面作为进入详情的入口。
   - 封面：`ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3/4, contentMode: .fill, enforcesAspectRatio: false, cornerRadius: 28)`，`.frame(maxWidth:.infinity)`，3:4（宽≈屏宽-2×18≈357pt→高≈476pt，贴近 367×489 基线），圆角 28，阴影。
   - 底部 scrim：`LinearGradient`(透明→黑) 叠 `show.name`（大字、最多 2 行、`minimumScaleFactor`）+ `formatter.dateText(for: show)` + `locationText`（复用 `RootView.swift:822`）。
   - 顶部 scrim：弱暗化（概念 C 顶部 0.52）保状态栏对比。
   - **右上角 44×44「更多」按钮**：`Image(systemName:"ellipsis")`，圆形、`Color.white.opacity(0.18)` 底 + `borderProminent` 描边 + `.background(.ultraThinMaterial)`。放在 NavigationLink label **外层** `.overlay(alignment:.topTrailing)` 并用独立 `Button`，确保点按只触发 Menu、不冒泡到 NavigationLink。
3. **更多 Menu（用户确认的三项）**：
   - **编辑现场** → `.sheet` 展示 `ShowDraftEditorView(title:"编辑现场", draft: ShowDraft(show: show), saveTitle:"保存", onSave: apply)`，`apply` 复用 ShowDetailView 同款保存逻辑（提取为共享函数或在当前视图内复制）。
   - **切换当前现场** → 仅 `shows.count > 1` 显示；`Submenu` 列出其它现场，选中调 `selectCurrent(_:)`（复用 `ShowLibraryViews.swift:189` 模式，不新建切换器 UI、不改选择逻辑）。
   - **删除现场** → `.destructive` role；展示现有 `BSDangerConfirmationSheet`（复用 `ShowLibraryViews.swift:485` 文案 + `deleteShow`）。删除当前现场后首页自然落到空状态。
   - 延期/取消：归属「编辑现场」范畴，本期仍经封面→ShowDetailView 操作（见「待确认」）。
4. **倒计时精简**：删 `countdownHero` 内 `countdownEyebrow` Text（`RootView.swift:447-450`），仅留 `countdownDisplay`（number+unit 或状态短语）；字号/配色不动（保留 178pt 大数字）。
5. **20pt 停顿**：`posterStage` 与 `countdownHero` 间 20pt（替换 `countdownHero` 现有 `.padding(.top, 8)` 为 20）。
6. **安全区**：封面作为第一块内容，顶部 8–12pt 呼吸，遵守安全区（不 ignoreSafeArea）。
7. **VoiceOver**：封面 `accessibilityElement(children:.combine)` 标「现场封面，{name}」+`.isButton`；更多按钮 `accessibilityLabel("更多现场操作")`；倒计时汇总 label。聚焦顺序：封面→更多→倒计时→Tips→工具。

**验收**：iPhone 17 模拟器构建通过；手动截图（普通封面、长中文标题、南京展示封面）确认无顶部工具栏、封面 3:4、更多独立可点、封面点按进详情、倒计时无 eyebrow/日期/地点。跑现有测试套件，无关失败单列。

## Slice 2 · 封面驱动全面屏背景
改 `CurrentShowHomeView`（`RootView.swift:118`）+ `DesignSystem.swift`：

1. **演进 `CurrentShowAmbientBackground`**（`DesignSystem.swift:344`，未被使用可安全改）为四层（spec 顺序）：
   - ① stage-void 底：`Color.black` + 极淡竖向渐变。
   - ② 固定冷暖舞台光：上左冷光（`Accent.travel` 系 `RadialGradient`+blur）、上右暖光（`Accent.music` 系），低透明度，`blendMode(.screen)`（参考概念 C `native-home` 双 radial）。
   - ③ 封面模糊回声：`ShowCoverImageView(同封面URL, enforcesAspectRatio:false, cornerRadius:0).blur(38).scaleEffect(1.16).saturation(0.82).opacity(0.22)`（saturation 低于源、低 opacity，不像第二张海报）。
   - ④ 竖向对比 scrim：`LinearGradient` 顶部最强（状态栏白字）+ 底部次强（Home Indicator/Tab 衔接），中部较弱。
2. **安全区**：背景 `.ignoresSafeArea()`（唯一忽略安全区的层）；封面/倒计时/Tips/工具继续遵守安全区。
3. **接入**：`CurrentShowHomeView` 的 `CurrentShowStageBackground()`（`RootView.swift:133`）换成新背景，传 `show?.coverImageURL`；空状态用同一背景（无封面时 `ShowCoverImageView` 走占位→中性舞台光，不暴露破损态，不残留旧封面）。
4. **状态栏对比**：顶层 scrim 顶部暗化，白字状态栏始终清晰，不依赖具体海报。
5. **动效**：环境层静止，不新增循环/视差/parallax；装饰层全 `accessibilityHidden(true)`。Reduce Motion 下本就静止。
6. 不做主色提取/Metal/第三方库（spec 明确）。

**验收**：四组 fixture 截图——亮封面、暗封面、缺失封面、南京展示封面。确认背景延至状态栏与 Home Indicator、状态栏白字对比稳定、无「第二张海报」感、空状态不残留旧封面。跑现有测试套件。

## 测试策略
- 最高验收缝：iPhone 17 模拟器跑真 SwiftUI app + `--seed-add-show-samples`（`RootView.swift:1135`）seed 当前现场，手动操作 Current tab。
- 不新增断言私有 SwiftUI 结构的测试；现有单测全跑，无关失败单列。
- before/after 截图存 `apps/ios/screenshots/manual-qa-2026-07-10/`。
- 状态覆盖：today/ended/postponed/canceled 倒计时短语不重复元数据；Tips 可见性与路由不变；工具区与各 sheet 仍可打开；VoiceOver 聚焦顺序；Reduce Motion。

## 待确认 / 偏差
- **更多菜单的延期/取消**：用户把「记录延期或取消」归在「编辑现场」下。本期「编辑现场」打开编辑 sheet（名/时/场/封面），延期/取消仍经封面→ShowDetailView。若要把「记录延期」「记录取消」也作为独立菜单项，告诉我即加。
- **切换当前现场**：issue 原文「Out of Scope: adding a new current-show switcher」，但用户当次明确要求加该菜单项——按用户指示执行，复用现有 `CurrentShowSelection`，不新建切换器 UI、不改选择逻辑。
- **HomeStageLightRig**：`countdownHero` 内现有一层 `splash_bg` 装饰（`RootView.swift:869`）。Slice 1 保留；Slice 2 评估是否与新环境背景冲突，冲突则移除（纯装饰、不影响业务）。
- **死代码**：`CurrentShowHeroLayoutPresentation` / `CurrentShowHeroActionPlacement` / `heroAspectRatio` / `imageSaturation`（`CurrentShowTimeState.swift:13-46,205-226`）未被使用——按 AGENTS.md「不删既有死代码」仅 mention，不动。
