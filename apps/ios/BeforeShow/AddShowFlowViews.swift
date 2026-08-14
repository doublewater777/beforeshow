import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddShowLinkFailurePresentation: Equatable {
    let title: String
    let message: String

    static func resolve(_ error: Error) -> Self {
        if let parserError = error as? ShowLinkDraftParser.ParseError {
            switch parserError {
            case .unsupportedSource:
                return Self(
                    title: "这个链接暂不支持",
                    message: "目前支持：\(ShowLinkPlatformCatalog.supportSummary)。你可以继续在下方手动填写。"
                )
            case .missingDate:
                return Self(
                    title: "还缺少现场信息",
                    message: "没有解析到有效日期，请在下方补充后再保存。"
                )
            }
        }

        guard let parsingError = error as? ShowLinkParsingError else {
            return Self(
                title: "链接解析失败",
                message: "暂时没能读出完整信息。你可以重试，或继续在下方手动填写。"
            )
        }

        switch parsingError {
        case .unsupportedSource:
            return Self(
                title: "这个链接暂不支持",
                message: "目前支持：\(ShowLinkPlatformCatalog.supportSummary)。你可以继续在下方手动填写。"
            )
        case .networkFailure:
            return Self(
                title: "网络连接失败",
                message: "请检查网络后重试，已经填写的内容会保留。"
            )
        case .invalidResponse:
            return Self(
                title: "还缺少现场信息",
                message: "没有解析到有效日期，请在下方补充后再保存。"
            )
        case .parseFailed:
            return Self(
                title: "链接解析失败",
                message: "暂时没能读出完整信息。你可以重试，或继续在下方手动填写。"
            )
        }
    }
}

enum AddShowSheet: String, Identifiable, Hashable {
    case manual
    case screenshot
    case link

    var id: String { rawValue }
}

enum AddShowMethodCopy {
    case manual
    case screenshot
    case link

    var subtitle: String {
        switch self {
        case .manual:
            return "自己填写现场的基本信息。"
        case .screenshot:
            return "选择票务截图，仅在本机识别，图片不会上传。"
        case .link:
            return "粘贴支持平台的票务链接，需要联网解析。"
        }
    }
}

enum ShowDraftEditorExitPolicy {
    static func requiresDiscardConfirmation(current: ShowDraft, initial: ShowDraft) -> Bool {
        current != initial
    }
}

struct AddShowCoordinatorSheet: View {
    var intent: AddShowIntent = .upcoming
    /// Skip method picker and open a specific flow. Only for tests / deep links — normal entry leaves this nil.
    var initialSheet: AddShowSheet? = nil
    var onShowAdded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSheet: AddShowSheet?

    init(
        intent: AddShowIntent = .upcoming,
        initialSheet: AddShowSheet? = nil,
        onShowAdded: @escaping () -> Void = {}
    ) {
        self.intent = intent
        self.initialSheet = initialSheet
        self.onShowAdded = onShowAdded
        _selectedSheet = State(initialValue: initialSheet)
    }

    var body: some View {
        NavigationStack {
            AddShowEntryView { sheet in
                selectedSheet = sheet
            }
            .navigationTitle("添加现场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .navigationDestination(item: $selectedSheet) { sheet in
                AddShowFlowView(
                    sheet: sheet,
                    intent: intent,
                    onSaved: {
                        dismiss()
                        onShowAdded()
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

enum AddShowIntent: Equatable {
    case upcoming
    case historicalBackfill
}

enum AddShowPersistenceError: Error, Equatable {
    case historicalBackfillRequiresCompletedShow
}

@MainActor
enum AddShowPersistenceCoordinator {
    static func persist(
        _ show: Show,
        intent: AddShowIntent,
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext
    ) throws -> NotificationSchedulingState? {
        if intent == .historicalBackfill {
            let timeState = CurrentShowTimeState(show: show, now: Date())
            guard timeState.kind == .postShow || timeState.kind == .ended else {
                throw AddShowPersistenceError.historicalBackfillRequiresCompletedShow
            }
        }

        modelContext.insert(show)

        guard intent == .upcoming else {
            try modelContext.save()
            return nil
        }

        let selection = selections.first ?? CurrentShowSelection()
        if selections.isEmpty {
            modelContext.insert(selection)
        }
        selection.select(showID: show.id)

        let notificationState = notificationStates.first
            ?? NotificationSchedulingState(focusedShowID: show.id)
        if notificationStates.isEmpty {
            modelContext.insert(notificationState)
        } else {
            notificationState.focus(showID: show.id)
        }

        try modelContext.save()
        return notificationState
    }
}

struct AddShowMenu: View {
    @Binding var addSheet: AddShowSheet?

    var body: some View {
        Menu {
            AddShowMethodButtons(addSheet: $addSheet)
        } label: {
            Label("添加现场", systemImage: "plus")
        }
    }
}

struct AddShowMethodButtons: View {
    @Binding var addSheet: AddShowSheet?

    var body: some View {
        Button {
            addSheet = .manual
        } label: {
            Label("手动添加", systemImage: "square.and.pencil")
        }

        Button {
            addSheet = .screenshot
        } label: {
            Label("截图识别", systemImage: "text.viewfinder")
        }

        Button {
            addSheet = .link
        } label: {
            Label("链接解析", systemImage: "link")
        }
    }
}

private struct AddShowEntryView: View {
    let onSelect: (AddShowSheet) -> Void

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        Text("三种方式任选，识别出的内容保存前都能改。")
                            .font(BSFont.body)
                            .foregroundColor(BSColor.textTertiary)
                            .lineSpacing(3)

                        VStack(spacing: BSSpacing.md) {
                            AddShowMethodCard(
                                title: "手动填写",
                                subtitle: AddShowMethodCopy.manual.subtitle,
                                iconName: "square.and.pencil",
                                tint: BSColor.Accent.prepare
                            ) {
                                onSelect(.manual)
                            }

                            AddShowMethodCard(
                                title: "截图识别",
                                subtitle: AddShowMethodCopy.screenshot.subtitle,
                                iconName: "camera.fill",
                                tint: BSColor.Accent.violet
                            ) {
                                onSelect(.screenshot)
                            }

                            AddShowMethodCard(
                                title: "链接解析",
                                subtitle: AddShowMethodCopy.link.subtitle,
                                iconName: "link",
                                tint: BSColor.Stage.accent
                            ) {
                                onSelect(.link)
                            }
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct AddShowFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""

    let sheet: AddShowSheet
    let intent: AddShowIntent
    let linkParser: ShowLinkDraftParser
    private let onSaved: (() -> Void)?

    @State private var draft: ShowDraft
    @State private var selectedScreenshotItem: PhotosPickerItem?
    @State private var linkText = ""
    @State private var message: String?
    @State private var linkFailure: AddShowLinkFailurePresentation?
    @State private var isRecognizingScreenshot = false
    @State private var isParsingLink = false
    @State private var isSaving = false
    @State private var hasImportedDraft = false
    @State private var showsManualFallback = false
    @State private var paywallSheet: AddShowPaywallSheet?
    @State private var toast: BSToastPayload?
    @State private var coverLifecycle = ShowCoverLifecycle()
    @State private var didSave = false
    @State private var didSwitchToManual = false
    @State private var ocrActiveStep = 0
    /// 每次成功导入（链接 / 截图）+1，驱动表单重建以重置内部时间影子状态。
    @State private var importRevision = 0
    /// 每次发起解析 / 识别 +1；返回时若 revision 已过期则丢弃结果，避免旧请求覆盖新请求。
    @State private var importRequestRevision = 0
    /// 用户自上次 import 后手改过的字段;下次 import 时跳过这些字段,
    /// 防止 OCR / link 解析偷偷覆盖用户输入。import 完成后清空。
    @State private var userEditedFields: Set<ShowDraftField> = []
    /// Apple Music 艺人搜索;可注入 Stub 跑测试。
    private let artistSearch: any ArtistSearchServicing = AppleMusicArtistSearchService()
    /// 当前进行中的解析 / OCR 任务；关闭页面时取消，避免后台继续写回。
    @State private var importTask: Task<Void, Never>?
    /// OCR 未识别日期（回退为今天）时，用户需显式确认后才可保存。
    @State private var fallbackDateConfirmed = false
    init(
        sheet: AddShowSheet,
        intent: AddShowIntent = .upcoming,
        linkParser: ShowLinkDraftParser = AddShowFlowView.defaultLinkParser(),
        onSaved: (() -> Void)? = nil
    ) {
        self.sheet = sheet
        self.intent = intent
        self.linkParser = linkParser
        self.onSaved = onSaved
        var initialDraft = ShowDraft(source: sheet.draftSource)
        if sheet == .manual {
            initialDraft.startTime = Calendar.current.date(
                bySettingHour: 19,
                minute: 30,
                second: 0,
                of: initialDraft.date
            )
        }
        _draft = State(initialValue: initialDraft)
    }

    static func defaultLinkParser() -> ShowLinkDraftParser {
        ShowLinkDraftParser(service: RemoteShowLinkParsingService(client: .production()))
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        methodContent

                        if hasImportedDraft {
                            AddShowImportedBanner(source: sheet)
                        }

                        if shouldShowDraftFields {
                            ShowDraftFormFields(
                                draft: $draft,
                                recognizedHighlight: hasImportedDraft,
                                coverEmptyPlaceholder: true,
                                requiresDateConfirmation: needsDateConfirmation,
                                onConfirmFallbackDate: {
                                    fallbackDateConfirmed = true
                                },
                                onCoverImported: { coverLifecycle.register(previous: $0, new: $1) },
                                artistSearch: artistSearch,
                                userEditedFields: $userEditedFields
                            )
                            // 重新导入时重建表单，清空 startTime / hasEndTime 等内部影子状态
                            .id(importRevision)
                            // 重新识别期间锁定旧表单，避免编辑后被新 draft 整表覆盖
                            .disabled(isImportingDraft)
                            .opacity(isImportingDraft ? 0.55 : 1)
                            .animation(.easeInOut(duration: 0.18), value: isImportingDraft)
                        }

                        if let message {
                            AddShowNoteCard(text: message, iconName: "info.circle")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                if shouldShowDraftFields {
                    addSaveBar
                }
            }
        }
        .navigationTitle(flowNavTitle)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .onChange(of: selectedScreenshotItem) { _, newItem in
            guard let newItem else { return }
            beginImportTask {
                await recognizeScreenshot(from: newItem)
            }
        }
        .onDisappear {
            // 页面离开时作废进行中的导入，避免任务在 dismiss 后继续写状态 / 弹 toast
            abandonInFlightImport()
            guard !didSave else { return }
            coverLifecycle.cancel()
        }
        .sheet(item: $paywallSheet) { sheet in
            switch sheet {
            case .limit:
                BSProLimitSheet(
                    title: ProLimitReason.saveLimit.title,
                    message: ProLimitReason.saveLimit.message
                ) {
                    paywallSheet = .membership
                } onSecondary: {
                    paywallSheet = nil
                }
            case .membership:
                ProMembershipSheetView()
            }
        }
        .bsToastOverlay(toast, bottomPadding: 28)
    }

    /// 识别后直接进可编辑表单，和手动填写同一套导航标题，不再多一层「确认」。
    private var flowNavTitle: String {
        didSwitchToManual ? "手动填写" : sheet.navigationTitle
    }

    /// 粘贴即识别链接来源，不用等一次失败往返。
    /// 只匹配官方域名及其子域名，避免查询参数或仿冒域名误报。
    /// 与 `ShowLinkDraftParser.normalizedLink` 使用同一套规范化，避免 chip 成功但提交失败。
    private var detectedLinkSource: String? {
        let candidate = ShowLinkDraftParser.normalizedLink(linkText)
        guard !candidate.isEmpty,
              let host = URL(string: candidate)?.host()?.lowercased() else { return nil }
        return ShowLinkPlatformCatalog.displayName(forHost: host)
    }

    /// OCR 没识别到日期（回退为今天）且用户尚未确认：金色「待确认」，并挡住保存。
    private var needsDateConfirmation: Bool {
        hasImportedDraft
            && !draft.recognizedFields.contains(.date)
            && !fallbackDateConfirmed
    }

    /// 链接解析或截图识别进行中：此时旧草稿不可保存/编辑，避免保存到上一次结果。
    private var isImportingDraft: Bool {
        isParsingLink || isRecognizingScreenshot
    }

    @ViewBuilder
    private var methodContent: some View {
        if didSwitchToManual {
            EmptyView()
        } else {
            switch sheet {
            case .manual:
                EmptyView()
            case .link:
                linkContent
            case .screenshot:
                screenshotContent
            }
        }
    }

    @ViewBuilder
    private var linkContent: some View {
        // 解析成功后只留结果表单；失败时保留输入与失败卡方便重试
        if !hasImportedDraft {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                EditShowFormCard(
                    title: "票务链接",
                    icon: "link",
                    tint: BSColor.Stage.accent
                ) {
                    AddShowMultilineInput(
                        placeholder: "https://...",
                        text: $linkText,
                        minHeight: 96,
                        keyboardType: .URL
                    )
                    // 解析期间锁定输入，避免返回结果与当前输入不一致
                    .disabled(isParsingLink)
                    .opacity(isParsingLink ? 0.55 : 1)

                    if let detectedLinkSource {
                        HStack(spacing: 8) {
                            Text("已识别来源")
                                .font(.system(size: 12))
                                .foregroundColor(BSColor.textTertiary)

                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text(detectedLinkSource)
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(BSColor.Accent.prepare)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(BSColor.Accent.prepare.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(BSColor.Accent.prepare.opacity(0.28), lineWidth: 1)
                            )
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Button {
                        dismissKeyboard()
                        beginImportTask {
                            await parseLink()
                        }
                    } label: {
                        HStack(spacing: BSSpacing.sm) {
                            if isParsingLink {
                                ProgressView()
                                    .tint(Color(red: 0.15, green: 0.11, blue: 0.04))
                            }
                            Text(isParsingLink ? "正在解析…" : "开始解析")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditShowSaveButtonStyle())
                    .disabled(isParsingLink || linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(isParsingLink ? "正在解析" : "开始解析")

                    Text("目前支持：\(ShowLinkPlatformCatalog.supportSummary)")
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.Stage.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        dismissKeyboard()
                        guard let url = URL(string: "https://beforeshow.doublewaterapps.com/link-guide/") else { return }
                        openURL(url)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 13, weight: .semibold))
                            Text("如何获取链接？")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(BSColor.Accent.violet)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看如何获取票务链接")
                }

                if let linkFailure, !isParsingLink {
                    AddShowLinkFailureCard(
                        failure: linkFailure,
                        onRetry: {
                            guard !isParsingLink else { return }
                            self.linkFailure = nil
                            linkText = ""
                        },
                        onManual: {
                            didSwitchToManual = true
                        }
                    )
                }
            }
        }
    }

    private var screenshotContent: some View {
        let isRecognizing = isRecognizingScreenshot
        // 识别成功后只留结果表单，不再占位「点选截图」和隐私说明
        let showsPicker = !hasImportedDraft

        return VStack(alignment: .leading, spacing: BSSpacing.md) {
            if isRecognizing {
                EditShowFormCard(
                    title: "识别进度",
                    icon: "text.viewfinder",
                    tint: BSColor.Accent.violet,
                    pillText: "设备端 · 不上传",
                    pillTint: BSColor.Accent.violet
                ) {
                    AddShowOCRStepsView(activeStep: ocrActiveStep)
                }
            }

            if showsPicker {
                PhotosPicker(selection: $selectedScreenshotItem, matching: .images) {
                    VStack(spacing: BSSpacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(BSColor.Accent.violet.opacity(0.13))
                                .frame(width: 64, height: 64)
                            Image(systemName: isRecognizing ? "text.viewfinder" : "camera.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(BSColor.Accent.violet)
                        }

                        Text(isRecognizing ? "重新选择截图" : "点击选择截图")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(BSColor.textSecondary)

                        Text("建议包含现场名称、日期、场馆的页面")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: isRecognizing ? 200 : 280)
                    .padding(.vertical, BSSpacing.xl)
                    .background(Color.white.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                BSColor.Accent.violet.opacity(0.40),
                                style: StrokeStyle(lineWidth: 2, dash: [7, 7])
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRecognizing)
                .simultaneousGesture(TapGesture().onEnded {
                    dismissKeyboard()
                })

                if showsManualFallback && sheet == .screenshot {
                    BSEmptyPanel(
                        iconName: "text.viewfinder",
                        title: "截图识别失败",
                        message: "没有识别到可用的现场信息。可以继续在下方手动填写。",
                        buttonTitle: "手动填写",
                        buttonIconName: "square.and.pencil"
                    ) {
                        didSwitchToManual = true
                    }
                }
            }
        }
    }

    private var shouldShowDraftFields: Bool {
        sheet == .manual || didSwitchToManual || hasImportedDraft
    }

    // MARK: - 吸底保存栏：始终可见，状态行说明缺什么

    private var addSaveBar: some View {
        VStack(spacing: 10) {
            // 进度阶梯：名称 → 开场时间；全部就绪转薄荷绿
            HStack(spacing: 5) {
                saveProgressSegment(
                    filled: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                saveProgressSegment(filled: draft.startTime != nil)
            }

            Text(saveBarStatus.text)
                .font(.system(size: 12))
                .foregroundColor(saveBarStatus.tint)
                .frame(maxWidth: .infinity)

            Button {
                Task {
                    await save()
                }
            } label: {
                HStack(spacing: BSSpacing.sm) {
                    if isSaving {
                        ProgressView()
                            .tint(Color(red: 0.15, green: 0.11, blue: 0.04))
                    }
                    Text(isSaving ? "正在保存" : sheet.saveButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditShowSaveButtonStyle())
            .disabled(!draft.isReadyToSave || isSaving || needsDateConfirmation || isImportingDraft)
            .accessibilityLabel(
                isImportingDraft
                    ? "正在导入，暂不可保存"
                    : (isSaving ? "正在保存" : sheet.saveButtonTitle)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private func saveProgressSegment(filled: Bool) -> some View {
        let ready = draft.isReadyToSave && !needsDateConfirmation && !isImportingDraft
        let fill: Color = filled
            ? (ready ? BSColor.Accent.prepare : BSColor.Stage.accent)
            : Color.white.opacity(0.10)
        return RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .frame(height: 3)
            .shadow(
                color: filled ? fill.opacity(0.5) : .clear,
                radius: 3
            )
            .animation(.easeInOut(duration: 0.18), value: filled)
            .animation(.easeInOut(duration: 0.18), value: ready)
    }

    private struct SaveBarStatus {
        let text: String
        let tint: Color
    }

    /// 按优先级说明距离可保存还差什么（导入中 → 名称 → 日期确认 → 开场时间 → 时间范围）。
    private var saveBarStatus: SaveBarStatus {
        if isImportingDraft {
            return SaveBarStatus(
                text: isParsingLink ? "正在解析链接…" : "正在识别截图…",
                tint: BSColor.Stage.muted
            )
        }
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SaveBarStatus(text: "还差现场名称", tint: BSColor.Stage.muted)
        }
        if needsDateConfirmation {
            return SaveBarStatus(
                text: "还差确认开场日期 · 截图没读到日期，已先填今天",
                tint: BSColor.Stage.muted
            )
        }
        if draft.startTime == nil {
            return SaveBarStatus(
                text: "还差开场时间 · 用于开场前提醒，可先填大概时间",
                tint: BSColor.Stage.muted
            )
        }
        if !draft.hasValidEndTime() {
            return SaveBarStatus(
                text: "时间范围无效，结束时间需要晚于开始时间",
                tint: BSColor.Accent.danger
            )
        }
        return SaveBarStatus(
            text: "可以添加了 · 封面等可之后再补",
            tint: BSColor.Stage.dim
        )
    }

    /// 启动解析 / OCR 任务；替换上一轮未完成的导入。
    private func beginImportTask(_ work: @escaping @MainActor () async -> Void) {
        importTask?.cancel()
        importTask = Task { @MainActor in
            await work()
        }
    }

    /// 作废进行中的链接解析 / OCR：revision 失效 + 取消 Task + 清 UI 标志。
    /// 关闭页面或返回时调用，防止任务在 sheet 消失后继续写状态。
    private func abandonInFlightImport() {
        importRequestRevision += 1
        importTask?.cancel()
        importTask = nil
        isParsingLink = false
        isRecognizingScreenshot = false
        ocrActiveStep = 0
    }

    /// 当前导入请求是否仍有效（未被新请求或页面关闭作废）。
    private func isActiveImportRequest(_ requestRevision: Int) -> Bool {
        requestRevision == importRequestRevision && !Task.isCancelled
    }

    @MainActor
    private func recognizeScreenshot(from item: PhotosPickerItem) async {
        guard !isRecognizingScreenshot else { return }
        isRecognizingScreenshot = true
        ocrActiveStep = 1
        importRequestRevision += 1
        let requestRevision = importRequestRevision

        // 分步进度为视觉呈现：OCR 是一次性调用，步骤按节奏推进，
        // 最多停在「整理现场信息」，识别结束后随面板一起消失。
        let stepTask = Task { @MainActor in
            while !Task.isCancelled && ocrActiveStep < 3 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if !Task.isCancelled {
                    ocrActiveStep += 1
                }
            }
        }

        defer {
            stepTask.cancel()
            if requestRevision == importRequestRevision {
                isRecognizingScreenshot = false
                ocrActiveStep = 0
                selectedScreenshotItem = nil
            }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                guard isActiveImportRequest(requestRevision) else { return }
                // 与 catch 分支一致：读取失败统一清除导入状态，
                // 不保留上一次识别成功的标题 / 横幅 / 标记
                draft.source = .manual
                hasImportedDraft = false
                showsManualFallback = true
                message = "没有读到这张截图，请改用手动填写。"
                presentToast(.failure, message: "读取失败")
                return
            }

            let recognized = try await OnDeviceShowScreenshotRecognizer().draft(from: image)
            guard isActiveImportRequest(requestRevision) else { return }
            stepTask.cancel()
            // 第四步「生成可编辑草稿」短暂停留，完成状态可见后再切到确认表单
            ocrActiveStep = 4
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard isActiveImportRequest(requestRevision) else { return }

            // 用 merge 而非整段替换:用户已手改的字段（userEditedFields）保留原值,
            // 避免 OCR 偷偷冲掉用户输入。import 完成后清空,下一轮 import 重新开始。
            draft.mergeRespectingUserEdits(from: recognized, userEdited: userEditedFields)
            userEditedFields = []
            hasImportedDraft = true
            showsManualFallback = false
            importRevision += 1
            fallbackDateConfirmed = false
            if !recognized.recognizedFields.contains(.date) {
                // OCR 日期回退为当天不算识别成功，必须引导用户确认
                message = "截图里没有识别到日期，已先填今天，请改成实际开场日期。"
            } else if recognized.startTime == nil {
                message = "已识别部分信息，请确认日期并补充开场时间。"
            } else {
                message = nil
            }
            presentToast(.success, message: "识别完成")
        } catch is CancellationError {
            // 页面关闭或新请求取消：不写失败态
            return
        } catch {
            guard isActiveImportRequest(requestRevision) else { return }
            draft.source = .manual
            hasImportedDraft = false
            showsManualFallback = true
            message = "没有识别到可用的现场信息，请改用手动填写。"
            presentToast(.failure, message: "识别失败")
        }
    }

    @MainActor
    private func parseLink() async {
        guard !isParsingLink else { return }
        dismissKeyboard()
        let requestedLink = linkText
        linkFailure = nil
        isParsingLink = true
        importRequestRevision += 1
        let requestRevision = importRequestRevision
        defer {
            if requestRevision == importRequestRevision {
                isParsingLink = false
            }
        }

        do {
            let parsed = try await linkParser.draft(from: requestedLink)
            guard isActiveImportRequest(requestRevision) else { return }
            // 同上:merge 而非整段替换,保护用户已手改的字段。
            draft.mergeRespectingUserEdits(from: parsed, userEdited: userEditedFields)
            userEditedFields = []
            hasImportedDraft = true
            showsManualFallback = false
            linkFailure = nil
            importRevision += 1
            fallbackDateConfirmed = false
            message = draft.startTime == nil
                ? "链接里没有明确开场时间，请确认后再添加。"
                : nil
            presentToast(.success, message: "解析完成")
        } catch is CancellationError {
            return
        } catch {
            guard isActiveImportRequest(requestRevision) else { return }
            draft.source = .manual
            hasImportedDraft = false
            showsManualFallback = true
            linkFailure = AddShowLinkFailurePresentation.resolve(error)
            message = nil
            presentToast(.failure, message: "解析失败")
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        // 重新解析 / 识别期间只允许保存新结果，避免写入上一次草稿
        guard !isImportingDraft else { return }
        // OCR 回退日期未确认时不允许保存，与保存栏状态文案一致
        guard !needsDateConfirmation else { return }
        isSaving = true
        dismissKeyboard()

        do {
            let entitlement = ProEntitlementStorage.decode(entitlementRawValue)
            guard ProFeatureGate().canAddShow(savedShowCount: shows.count, entitlement: entitlement) else {
                paywallSheet = .limit
                presentToast(.neutral, message: "保存上限")
                isSaving = false
                return
            }

            let show = try draft.makeShow()
            let notificationState = try AddShowPersistenceCoordinator.persist(
                show,
                intent: intent,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext
            )

            if let notificationState {
                await activateNotifications(for: show, state: notificationState)
            }
            didSave = true
            coverLifecycle.finalize(keeping: draft.coverImageURL)

            if let onSaved {
                onSaved()
            } else {
                dismiss()
            }
        } catch ShowValidationError.invalidEndTime {
            message = "结束时间需要晚于开始时间。"
            presentToast(.failure, message: "时间范围无效")
            isSaving = false
        } catch ShowValidationError.missingStartTime {
            message = "请确认开场时间。"
            presentToast(.failure, message: "还缺开场时间")
            isSaving = false
        } catch ShowValidationError.emptyName {
            message = "请填写现场名称。"
            presentToast(.failure, message: "保存失败")
            isSaving = false
        } catch AddShowPersistenceError.historicalBackfillRequiresCompletedShow {
            message = "补录历史仅支持已经结束的现场。"
            presentToast(.failure, message: "日期还未结束")
            isSaving = false
        } catch {
            modelContext.rollback()
            message = "请填写必填信息。"
            presentToast(.failure, message: "保存失败")
            isSaving = false
        }
    }

    @MainActor
    private func activateNotifications(
        for show: Show,
        state: NotificationSchedulingState
    ) async {
        let center = LocalNotificationCenter.shared
        let authorizationState = await center.authorizationState()
        let shouldRequest = NotificationPermissionPolicy().shouldRequestPermission(
            hasAddedShow: true,
            authorizationState: authorizationState,
            hasRequestedPermissionAfterFirstShow: state.hasRequestedPermissionAfterFirstShow
        )

        if shouldRequest {
            _ = await center.requestAuthorization()
            state.recordPermissionRequest()
            try? modelContext.save()
        }

        await center.applyFocusChange(to: show, in: modelContext)
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }
}

private extension ShowDraft {
    var isReadyToSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && startTime != nil
            && hasValidEndTime()
    }
}

@MainActor
private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

enum ShowCoverLocalImageStore {
    static func directory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("ShowCovers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func removeManagedLocalImage(at urlString: String) {
        guard let url = URL(string: urlString),
              url.isFileURL,
              let managedDirectory = try? directory().standardizedFileURL,
              url.standardizedFileURL.deletingLastPathComponent() == managedDirectory else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

}

/// Tracks imported cover URLs that haven't been committed to a saved 现场, and owns
/// the temp-to-permanent lifecycle: commit one on save, discard the rest on cancel.
///
/// Deletion test: without this, `AddShowFlowView` and `ShowDraftEditorView` each
/// re-implemented register/cleanup/finalize over `ShowCoverLocalImageStore`; a cleanup
/// bug had to be fixed twice. The store stays an internal detail; this is the module
/// callers touch. `remove` is injected so tests assert keep/discard logic without file I/O.
struct ShowCoverLifecycle {
    private let remove: (String) -> Void
    private var temporaryCoverURLs: Set<String> = []

    init(remove: @escaping (String) -> Void = ShowCoverLocalImageStore.removeManagedLocalImage(at:)) {
        self.remove = remove
    }

    /// A newly imported cover replaces `previous` (if it was temp) and is tracked as temp.
    mutating func register(previous: String, new: String) {
        if temporaryCoverURLs.contains(previous) {
            remove(previous)
            temporaryCoverURLs.remove(previous)
        }
        temporaryCoverURLs.insert(new)
    }

    /// Cancel: discard every temp cover.
    mutating func cancel() {
        for urlString in temporaryCoverURLs {
            remove(urlString)
        }
        temporaryCoverURLs.removeAll()
    }

    /// Commit on save: keep `keptURL`, discard every other temp, plus any
    /// `additionalDiscards` (e.g. an original cover replaced during edit).
    mutating func finalize(keeping keptURL: String?, additionalDiscards: [String] = []) {
        for urlString in temporaryCoverURLs where urlString != keptURL {
            remove(urlString)
        }
        for urlString in additionalDiscards where urlString != keptURL {
            remove(urlString)
        }
        temporaryCoverURLs.removeAll()
    }
}

/// 状态操作结果：文案 + 提示语气，避免保存失败被显示成绿色成功 toast。
struct ShowStatusActionResult {
    let tone: BSToastTone
    let message: String
}

/// 编辑现场 sheet 内的现场状态管理上下文：状态展示 + 立即生效的状态操作。
/// 由详情页注入；为 nil 时编辑器不渲染现场状态卡（例如仅编辑草稿的场景）。
/// 状态操作不走「保存」按钮，沿用详情页语义立即生效，闭包返回 toast 的语气与文案。
struct ShowStatusEditingContext {
    let changeStatus: ShowChangeStatus
    let postponedDate: Date?
    let title: String
    let description: String
    let restoreTitle: String
    let onRestore: @MainActor () async -> ShowStatusActionResult
    let onPostpone: @MainActor (Date?) async -> ShowStatusActionResult
    let onCancel: @MainActor () async -> ShowStatusActionResult
    let onDelete: @MainActor () async -> Void
}

struct ShowDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let saveTitle: String
    /// 摘要卡右上角的状态胶囊文案（如「即将开场」「已延期」），nil 则不显示。
    var statusPillText: String? = nil
    /// 延期现场：摘要卡下方追加紫金横幅，说明这里编辑的是原定信息。
    var isPostponed: Bool = false
    /// 现场状态管理（延期 / 取消 / 恢复 / 删除），nil 时不渲染现场状态卡。
    var statusEditing: ShowStatusEditingContext? = nil
    let onSave: @MainActor (ShowDraft) async throws -> Void
    private let initialDraft: ShowDraft
    private let originalCoverURL: String

    @State private var draft: ShowDraft
    @State private var message: String?
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false
    @State private var coverLifecycle = ShowCoverLifecycle()
    @State private var didSave = false
    @State private var postponeDate = Date()
    @State private var showsPostponeSheet = false
    @State private var showsCancelConfirm = false
    @State private var showsDeleteConfirm = false
    @State private var isApplyingStatus = false
    @State private var statusToast: BSToastPayload?
    /// 编辑现场时无 import 流程,这个 binding 留空集合即可。
    @State private var userEditedFields: Set<ShowDraftField> = []
    private let artistSearch: any ArtistSearchServicing = AppleMusicArtistSearchService()

    init(
        title: String,
        draft: ShowDraft,
        saveTitle: String,
        statusPillText: String? = nil,
        isPostponed: Bool = false,
        statusEditing: ShowStatusEditingContext? = nil,
        onSave: @escaping @MainActor (ShowDraft) async throws -> Void
    ) {
        self.title = title
        _draft = State(initialValue: draft)
        self.saveTitle = saveTitle
        self.statusPillText = statusPillText
        self.isPostponed = isPostponed
        self.statusEditing = statusEditing
        self.onSave = onSave
        initialDraft = draft
        originalCoverURL = draft.coverImageURL
    }

    private var hasUnsavedChanges: Bool {
        ShowDraftEditorExitPolicy.requiresDiscardConfirmation(current: draft, initial: initialDraft)
    }

    private var isEndTimeRangeValid: Bool {
        draft.startTime == nil || draft.hasValidEndTime()
    }

    var body: some View {
        NavigationStack {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.md) {
                        editorSummaryCard
                        if isPostponed {
                            postponedBanner
                        }

                        ShowDraftFormFields(
                            draft: $draft,
                            onCoverImported: { coverLifecycle.register(previous: $0, new: $1) },
                            artistSearch: artistSearch,
                            userEditedFields: $userEditedFields
                        )

                        if let statusEditing {
                            statusCard(statusEditing)
                            deleteShowEntry
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                saveBar
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .interactiveDismissDisabled(hasUnsavedChanges || isSaving || isApplyingStatus)
        .onChange(of: draft) { _, _ in
            message = nil
        }
        .sheet(isPresented: $showsPostponeSheet) {
            PostponeShowSheet(
                newDate: $postponeDate,
                calendar: draft.timingCalendar(),
                onUndated: {
                    showsPostponeSheet = false
                    Task { @MainActor in
                        await applyStatusAction { await statusEditing?.onPostpone(nil) }
                    }
                },
                onDated: {
                    showsPostponeSheet = false
                    let newDate = ShowDateSelectionPolicy.normalizedDay(
                        postponeDate,
                        calendar: draft.timingCalendar()
                    )
                    Task { @MainActor in
                        await applyStatusAction { await statusEditing?.onPostpone(newDate) }
                    }
                }
            )
        }
        .confirmationDialog(
            DangerConfirmation.cancelShowFromEditor.title,
            isPresented: $showsCancelConfirm,
            titleVisibility: .visible
        ) {
            Button(DangerConfirmation.cancelShowFromEditor.confirmTitle, role: .destructive) {
                Task { @MainActor in
                    await applyStatusAction { await statusEditing?.onCancel() }
                }
            }
        } message: {
            Text(DangerConfirmation.cancelShowFromEditor.message)
        }
        .confirmationDialog(
            DangerConfirmation.deleteShowFromEditor.title,
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(DangerConfirmation.deleteShowFromEditor.confirmTitle, role: .destructive) {
                Task { @MainActor in
                    await statusEditing?.onDelete()
                }
            }
        } message: {
            Text(DangerConfirmation.deleteShowFromEditor.message)
        }
        .bsToastOverlay(statusToast, bottomPadding: 96)
        .alert("放弃修改？", isPresented: $showsDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) {
                coverLifecycle.cancel()
                dismiss()
            }
        } message: {
            Text("尚未保存的现场信息会丢失。")
        }
        .onDisappear {
            guard !didSave else { return }
            coverLifecycle.cancel()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { requestDismiss() }
                    .accessibilityLabel("取消编辑")
            }
        }
        }
    }

    private func requestDismiss() {
        dismissKeyboard()
        if hasUnsavedChanges {
            showsDiscardConfirmation = true
        } else {
            coverLifecycle.cancel()
            dismiss()
        }
    }

    // MARK: - 摘要卡：滚动时始终知道在编辑哪一场

    private var editorSummaryCard: some View {
        HStack(spacing: 14) {
            ShowCoverImageView(
                urlString: draft.coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                cornerRadius: 10
            )
            .frame(width: 45, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名现场" : draft.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(2)

                Text(summaryDateText)
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let statusPillText {
                editorStatusPill(text: statusPillText)
            }
        }
        .padding(14)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    private var summaryDateText: String {
        let calendar = draft.timingCalendar()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_Hans_CN")
        dateFormatter.dateFormat = "M月d日"
        dateFormatter.timeZone = calendar.timeZone
        var text = (isPostponed ? "原定 " : "") + dateFormatter.string(from: draft.date)
        if let startTime = draft.startTime {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "zh_Hans_CN")
            timeFormatter.dateFormat = "HH:mm"
            timeFormatter.timeZone = calendar.timeZone
            text += " " + timeFormatter.string(from: startTime)
        }
        let venue = draft.venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            text += " · \(venue)"
        }
        return text
    }

    private func editorStatusPill(text: String) -> some View {
        let tint = isPostponed
            ? Color(red: 0.84, green: 0.76, blue: 1.0)
            : BSColor.Stage.accent
        return HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.32), lineWidth: 1)
        )
    }

    // MARK: - 延期横幅

    private var postponedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSColor.Accent.violet)

            Text("这场已延期。这里编辑的是原定信息；延期日期在下方「现场状态」中更新。")
                .font(.system(size: 12.5))
                .foregroundColor(Color(red: 0.80, green: 0.74, blue: 0.92))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Accent.violet.opacity(0.12),
                    BSColor.Stage.accent.opacity(0.07)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(BSColor.Accent.violet.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - 现场状态卡（并入编辑现场，操作立即生效）

    private func statusTint(for status: ShowChangeStatus) -> Color {
        switch status {
        case .scheduled: return BSColor.Accent.prepare
        case .postponed: return Color(red: 0.84, green: 0.76, blue: 1.0)
        case .canceled: return BSColor.Accent.danger
        }
    }

    private func statusIconName(for status: ShowChangeStatus) -> String {
        switch status {
        case .scheduled: return "checkmark.circle.fill"
        case .postponed: return "calendar.badge.clock"
        case .canceled: return "xmark.circle.fill"
        }
    }

    private func statusCard(_ context: ShowStatusEditingContext) -> some View {
        let tint = statusTint(for: context.changeStatus)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.13))
                    Image(systemName: statusIconName(for: context.changeStatus))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 26, height: 26)

                Text("现场状态")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)

                Spacer(minLength: 0)

                Text(context.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.30), lineWidth: 1)
                    )
            }

            Text(context.description)
                .font(.system(size: 12.5))
                .foregroundColor(BSColor.textTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                if context.changeStatus != .scheduled {
                    Button {
                        Task { @MainActor in
                            await applyStatusAction { await statusEditing?.onRestore() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BSColor.textTertiary)
                            Text(context.restoreTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(BSColor.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplyingStatus)
                    .accessibilityLabel(context.restoreTitle)
                }

                if context.changeStatus != .canceled {
                    HStack(spacing: 12) {
                        statusActionButton(
                            title: context.changeStatus == .postponed ? "更新延期信息" : "记录延期",
                            systemImage: "calendar.badge.clock",
                            tint: Color(red: 0.84, green: 0.76, blue: 1.0)
                        ) {
                            postponeDate = context.postponedDate ?? draft.date
                            showsPostponeSheet = true
                        }

                        statusActionButton(
                            title: "记录取消",
                            systemImage: "xmark.circle",
                            tint: BSColor.Accent.danger
                        ) {
                            showsCancelConfirm = true
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    private func statusActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(tint.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isApplyingStatus)
        .accessibilityLabel(title)
    }

    private var deleteShowEntry: some View {
        Button {
            showsDeleteConfirm = true
        } label: {
            Text("删除现场")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(BSColor.Accent.danger.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(minHeight: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isApplyingStatus)
        .accessibilityLabel("删除现场")
    }

    @MainActor
    private func applyStatusAction(
        _ action: @MainActor () async -> ShowStatusActionResult?
    ) async {
        guard !isApplyingStatus else { return }
        isApplyingStatus = true
        let result = await action()
        isApplyingStatus = false
        if let result {
            presentStatusToast(result.tone, message: result.message)
        }
    }

    private func presentStatusToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        statusToast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if statusToast == payload {
                statusToast = nil
            }
        }
    }

    // MARK: - 吸底保存栏

    private var saveBar: some View {
        VStack(spacing: 10) {
            saveBarStatus
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)

            Button {
                Task { @MainActor in
                    await save()
                }
            } label: {
                HStack(spacing: BSSpacing.sm) {
                    if isSaving {
                        ProgressView()
                            .tint(Color(red: 0.15, green: 0.11, blue: 0.04))
                    }
                    Text(isSaving ? "正在保存" : saveTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditShowSaveButtonStyle())
            .disabled(!draft.isReadyToSave || isSaving)
            .accessibilityLabel(isSaving ? "正在保存" : saveTitle)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var saveBarStatus: some View {
        if let message {
            Text(message)
                .foregroundColor(BSColor.Accent.danger)
        } else if !isEndTimeRangeValid {
            Text("结束时间需晚于开始时间，请修正后保存")
                .foregroundColor(BSColor.Stage.muted)
        } else if hasUnsavedChanges {
            HStack(spacing: 7) {
                Circle()
                    .fill(BSColor.Stage.accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: BSColor.Stage.accent.opacity(0.7), radius: 4)
                Text("有未保存的修改")
                    .foregroundColor(BSColor.Stage.muted)
            }
        } else {
            Text("所有修改已保存")
                .foregroundColor(BSColor.Stage.dim)
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard draft.hasValidEndTime() else {
            message = "结束时间需晚于开始时间，请修正后保存"
            return
        }

        isSaving = true
        message = nil
        dismissKeyboard()

        do {
            try await onSave(draft)
            coverLifecycle.finalize(keeping: draft.coverImageURL, additionalDiscards: [originalCoverURL])
            didSave = true
            dismiss()
        } catch {
            message = "没有保存成功，请重试。你的修改仍保留在这里。"
            isSaving = false
        }
    }

}

private struct ShowDraftFormFields: View {
    @Binding var draft: ShowDraft
    /// 添加现场·识别导入（链接 / 截图）：识别出的字段标「✓ 已识别」薄荷绿描边。
    let recognizedHighlight: Bool
    /// 添加现场：无封面时显示虚线引导占位。
    let coverEmptyPlaceholder: Bool
    /// OCR 未识别日期（回退为今天）且未确认：日期瓷贴金色「待确认」并显示确认按钮。
    let requiresDateConfirmation: Bool
    let onConfirmFallbackDate: () -> Void
    let onCoverImported: (String, String) -> Void
    /// Apple Music 艺人搜索;可注入 Stub 跑测试。Phase 5 加。
    var artistSearch: any ArtistSearchServicing = AppleMusicArtistSearchService()
    /// 用户自上次 import 后手改过的字段;下次 import 会跳过这些字段,
    /// 防止 OCR / link 解析偷偷覆盖用户输入。
    @Binding var userEditedFields: Set<ShowDraftField>
    @State private var startTime: Date
    @State private var hasEndTime: Bool
    @State private var endDate: Date
    @State private var endTime: Date
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isImportingCover = false
    @State private var coverImportMessage: String?
    @State private var showsLinkField = false

    /// 「已识别」标记只读字段级 provenance，不按字段是否有值推断。
    private var nameRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.name)
    }
    private var cityRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.city)
    }
    private var venueRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.venueName)
    }
    private var dateRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.date)
    }
    private var startTimeRecognized: Bool {
        recognizedHighlight && draft.recognizedFields.contains(.startTime)
    }

    init(
        draft: Binding<ShowDraft>,
        recognizedHighlight: Bool = false,
        coverEmptyPlaceholder: Bool = false,
        requiresDateConfirmation: Bool = false,
        onConfirmFallbackDate: @escaping () -> Void = {},
        onCoverImported: @escaping (String, String) -> Void = { _, _ in },
        artistSearch: any ArtistSearchServicing = AppleMusicArtistSearchService(),
        userEditedFields: Binding<Set<ShowDraftField>>
    ) {
        let initialDraft = draft.wrappedValue
        let eventCalendar = initialDraft.timingCalendar()
        let fallbackStart = eventCalendar.date(
            bySettingHour: 19,
            minute: 30,
            second: 0,
            of: initialDraft.date
        ) ?? initialDraft.date
        let initialEndDate = initialDraft.endDate ?? initialDraft.date
        let fallbackEnd = initialDraft.endTimingCalendar().date(
            bySettingHour: 23,
            minute: 55,
            second: 0,
            of: initialEndDate
        ) ?? initialEndDate

        self._draft = draft
        self.recognizedHighlight = recognizedHighlight
        self.coverEmptyPlaceholder = coverEmptyPlaceholder
        self.requiresDateConfirmation = requiresDateConfirmation
        self.onConfirmFallbackDate = onConfirmFallbackDate
        self.onCoverImported = onCoverImported
        self.artistSearch = artistSearch
        self._userEditedFields = userEditedFields
        // Picker display state may use a fallback clock; draft.startTime stays nil until confirmed.
        _startTime = State(initialValue: initialDraft.startTime ?? fallbackStart)
        // End section covers both end clock and multi-day end date.
        _hasEndTime = State(initialValue: initialDraft.endTime != nil || initialDraft.endDate != nil)
        _endDate = State(initialValue: initialEndDate)
        _endTime = State(initialValue: initialDraft.endTime ?? fallbackEnd)
    }

    var body: some View {
        formCards
        .environment(\.calendar, draft.timingCalendar())
        .environment(\.timeZone, draft.timingCalendar().timeZone)
        .onChange(of: hasEndTime) { _, newValue in
            syncEndTimeToDraft(isEnabled: newValue)
        }
        .onChange(of: startTime) { _, _ in
            // Only write committed start times; unconfirmed picker value stays local.
            if draft.startTime != nil {
                draft.startTime = mergedStartTime()
            }
            if hasEndTime {
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: endTime) { _, _ in
            if hasEndTime {
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: endDate) { _, _ in
            if hasEndTime {
                let startDay = draft.timingCalendar().startOfDay(for: draft.date)
                if draft.endTimingCalendar().startOfDay(for: endDate) < startDay {
                    endDate = startDay
                }
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: draft.date) { _, _ in
            if draft.startTime != nil {
                draft.startTime = mergedStartTime()
            }
            if hasEndTime {
                let startDay = draft.timingCalendar().startOfDay(for: draft.date)
                if draft.endTimingCalendar().startOfDay(for: endDate) < startDay {
                    endDate = startDay
                }
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: selectedCoverItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importCover(from: newItem)
            }
        }
    }

    /// 四张卡片布局（Stage 色板，与首页 V4 / 现场状态卡同一语言）。
    private var formCards: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditShowFormCard(title: "基本信息", icon: "square.and.pencil", tint: BSColor.Stage.accent) {
                AddShowLabeledTextField(
                    title: "现场名称",
                    placeholder: "例：五月天上海演唱会",
                    text: $draft.name,
                    isRequired: true,
                    isRecognized: nameRecognized
                )
                .onChange(of: draft.name) { _, _ in
                    userEditedFields.insert(.name)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("艺人 / 阵容")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BSColor.textSecondary)
                        Spacer()
                        if artistRowRecognized {
                            Label("已识别", systemImage: "checkmark.seal.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(BSColor.Accent.prepare)
                        }
                    }
                    ForEach(Array(draft.artists.enumerated()), id: \.offset) { index, _ in
                        ArtistInputRow(
                            index: index,
                            name: Binding(
                                get: { draft.artists[safe: index]?.name ?? "" },
                                set: { newValue in
                                    ensureArtistSlot(at: index)
                                    draft.artists[index].name = newValue
                                }
                            ),
                            avatar: Binding(
                                get: { draft.artists[safe: index]?.avatarURL ?? nil },
                                set: { newValue in
                                    ensureArtistSlot(at: index)
                                    draft.artists[index].avatarURL = newValue
                                }
                            ),
                            artistSearch: artistSearch,
                            canDelete: draft.artists.count > 1,
                            onPick: { recognition in
                                ensureArtistSlot(at: index)
                                draft.artists[index].name = recognition.canonicalName
                                draft.artists[index].avatarURL = recognition.avatarURL?.absoluteString
                                draft.recognizedFields.remove(.artist)
                            },
                            onDelete: { removeArtistRow(at: index) },
                            onTextChange: { userEditedFields.insert(.artist) }
                        )
                    }
                    Button {
                        draft.artists.append(ArtistSlot(name: "", avatarURL: nil))
                    } label: {
                        Label("+ 新增艺人", systemImage: "plus.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(BSColor.Accent.violet)
                    }
                    .buttonStyle(.plain)
                }
                .onAppear {
                    if draft.artists.isEmpty {
                        draft.artists = [ArtistSlot(name: "", avatarURL: nil)]
                    }
                    Task { await artistSearch.requestAuthorizationIfNeeded() }
                }
            }

            EditShowFormCard(
                title: "日期与时间",
                icon: "clock",
                tint: BSColor.Accent.violet
            ) {
                AddShowScheduleFields(
                    draft: $draft,
                    startTime: $startTime,
                    isStartTimeConfirmed: draft.startTime != nil,
                    onConfirmStartTime: {
                        draft.startTime = mergedStartTime()
                        userEditedFields.insert(.startTime)
                    },
                    hasEndTime: $hasEndTime,
                    endDate: $endDate,
                    endTime: $endTime,
                    dateRecognized: dateRecognized,
                    dateNeeded: requiresDateConfirmation,
                    startTimeRecognized: startTimeRecognized,
                    onConfirmFallbackDate: onConfirmFallbackDate
                )
                .onChange(of: draft.date) { _, _ in
                    userEditedFields.insert(.date)
                }

                if draft.startTime != nil && !draft.hasValidEndTime() {
                    Label("结束时间需要晚于开始时间", systemImage: "exclamationmark.circle.fill")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Accent.danger)
                        .accessibilityLabel("时间范围无效，结束时间需要晚于开始时间")
                }
            }

            EditShowFormCard(title: "地点", icon: "mappin.and.ellipse", tint: BSColor.Accent.prepare) {
                AddShowLabeledTextField(
                    title: "城市",
                    placeholder: "上海",
                    text: $draft.city,
                    isRecognized: cityRecognized
                )
                .onChange(of: draft.city) { _, _ in
                    userEditedFields.insert(.city)
                }

                BSVenueField(
                    venueName: $draft.venueName,
                    venueAddress: $draft.venueAddress,
                    city: draft.city,
                    isRecognized: venueRecognized
                )
                .onChange(of: draft.venueName) { _, _ in
                    userEditedFields.insert(.venueName)
                }
            }

            EditShowFormCard(
                title: "封面",
                icon: "photo",
                tint: BSColor.Stage.accent
            ) {
                if !draft.coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ShowDraftCoverPreview(urlString: draft.coverImageURL)
                } else if coverEmptyPlaceholder {
                    HStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(BSColor.Accent.violet)
                        Text("还没加封面")
                            .font(.system(size: 12.5))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .background(Color.white.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                Color.white.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                            )
                    )
                }

                AddShowCoverActions(
                    selectedItem: $selectedCoverItem,
                    showsLinkField: $showsLinkField,
                    isImporting: isImportingCover,
                    message: coverImportMessage
                )

                if showsLinkField {
                    AddShowLabeledTextField(
                        title: "图片链接",
                        placeholder: "https://...",
                        text: $draft.coverImageURL,
                        keyboardType: .URL
                    )
                }
            }
        }
    }

    private func mergedStartTime() -> Date {
        draft.mergedTime(startTime, into: draft.date, calendar: draft.timingCalendar())
    }

    private func syncEndTimeToDraft(isEnabled: Bool) {
        guard isEnabled else {
            draft.endDate = nil
            draft.endTime = nil
            return
        }

        let resolvedEndDay = max(
            draft.endTimingCalendar().startOfDay(for: endDate),
            draft.timingCalendar().startOfDay(for: draft.date)
        )
        endDate = resolvedEndDay
        draft.endDate = resolvedEndDay
        draft.endTime = draft.mergedTime(
            endTime,
            into: resolvedEndDay,
            calendar: draft.endTimingCalendar()
        )
    }

    @MainActor
    private func ensureArtistSlot(at index: Int) {
        if draft.artists.count <= index {
            while draft.artists.count <= index {
                draft.artists.append(ArtistSlot(name: "", avatarURL: nil))
            }
        }
    }

    @MainActor
    private func removeArtistRow(at index: Int) {
        guard draft.artists.indices.contains(index) else { return }
        draft.artists.remove(at: index)
        if draft.artists.isEmpty {
            draft.artists.append(ArtistSlot(name: "", avatarURL: nil))
        }
    }

    private var artistRowRecognized: Bool {
        recognizedHighlight
            && draft.recognizedFields.contains(.artist)
            && draft.artists.contains { $0.avatarURL != nil }
    }

    @MainActor
    private func importCover(from item: PhotosPickerItem) async {
        isImportingCover = true
        coverImportMessage = nil
        defer {
            isImportingCover = false
            selectedCoverItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpegData = image.jpegData(compressionQuality: 0.86) else {
                coverImportMessage = "没有读到这张图片"
                return
            }

            let directory = try ShowCoverLocalImageStore.directory()
            let fileURL = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            try jpegData.write(to: fileURL, options: [.atomic])
            let previousURL = draft.coverImageURL
            draft.coverImageURL = fileURL.absoluteString
            onCoverImported(previousURL, draft.coverImageURL)
            coverImportMessage = "已换成本地封面"
        } catch {
            coverImportMessage = "封面图导入失败"
        }
    }
}

private struct AddShowMethodCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: BSSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(tint.opacity(0.13))
                    Image(systemName: iconName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundColor(BSColor.textTertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.dim)
                    .frame(maxHeight: .infinity)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(BSColor.Stage.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct AddShowLabeledTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isRequired = false
    var isRecognized = false
    var keyboardType: UIKeyboardType = .default
    var helperText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(
                title: title,
                isRequired: isRequired,
                mark: isRecognized ? .recognized : nil
            )
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .textContentType(keyboardType == .URL ? .URL : nil)
                .keyboardType(keyboardType)
                .addShowInputChrome()
                .overlay {
                    if isRecognized {
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.Accent.prepare.opacity(0.30), lineWidth: 1)
                    }
                }

            if let helperText {
                Text(helperText)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AddShowScheduleFields: View {
    @Binding var draft: ShowDraft
    @Binding var startTime: Date
    let isStartTimeConfirmed: Bool
    let onConfirmStartTime: () -> Void
    @Binding var hasEndTime: Bool
    @Binding var endDate: Date
    @Binding var endTime: Date
    /// 识别导入：开场日期标「已识别」薄荷绿描边。
    var dateRecognized: Bool = false
    /// 识别导入但日期是回退值（OCR 没读到日期）：金色「待确认」+ 确认按钮。
    var dateNeeded: Bool = false
    /// 识别导入：开场时间标「已识别」。
    var startTimeRecognized: Bool = false
    /// 日期回退值的确认回调：点确认按钮或手动改日期都会触发。
    var onConfirmFallbackDate: () -> Void = {}

    /// 两列瓷贴中间固定间距，不被中文长日期挤没。
    private static let columnSpacing: CGFloat = 14

    private var eventCalendar: Calendar { draft.timingCalendar() }
    private var endCalendar: Calendar { draft.endTimingCalendar() }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            HStack(alignment: .top, spacing: Self.columnSpacing) {
                AddShowDatePickerField(
                    title: "开场日期",
                    selection: $draft.date,
                    displayedComponents: .date,
                    calendar: eventCalendar,
                    isRecognized: dateRecognized,
                    isNeeded: dateNeeded,
                    onConfirmNeeded: onConfirmFallbackDate
                )

                AddShowStartTimeField(
                    title: "开场时间",
                    startTime: $startTime,
                    calendar: eventCalendar,
                    isConfirmed: isStartTimeConfirmed,
                    onConfirm: onConfirmStartTime,
                    isRecognized: startTimeRecognized
                )
            }

            AddShowEndTimeField(
                hasEndTime: $hasEndTime,
                endDate: $endDate,
                endTime: $endTime,
                calendar: endCalendar
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: hasEndTime)
    }
}

/// 把系统紧凑 DatePicker 箍进固定瓷贴，避免中文日期把邻列挤叠。
/// 控件按内容缩宽并左对齐；列宽由外层 HStack 等分，溢出裁剪，间距才能保留。
private struct AddShowConstrainedDatePicker: View {
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    let calendar: Calendar
    var borderColor: Color? = nil

    var body: some View {
        HStack(spacing: 0) {
            DatePicker("", selection: $selection, displayedComponents: displayedComponents)
                .labelsHidden()
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                .tint(BSColor.Accent.violet)
                .datePickerStyle(.compact)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // minWidth: 0 才能在等分列里被压窄，否则会撑破 HStack 间距
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(borderColor ?? BSColor.borderProminent, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: BSRadius.md))
    }
}

private struct AddShowDatePickerField: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    let calendar: Calendar
    var isRequired = true
    var isRecognized = false
    var isNeeded = false
    /// isNeeded 时的确认回调：点按钮或手动改动选择器都算确认。
    var onConfirmNeeded: (() -> Void)? = nil

    private var borderColor: Color? {
        if isNeeded {
            return BSColor.Stage.accent.opacity(0.50)
        }
        return isRecognized ? BSColor.Accent.prepare.opacity(0.30) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(
                title: title,
                isRequired: isRequired,
                mark: isNeeded ? .needed : (isRecognized ? .recognized : nil)
            )
            AddShowConstrainedDatePicker(
                selection: $selection,
                displayedComponents: displayedComponents,
                calendar: calendar,
                borderColor: borderColor
            )
            .onChange(of: selection) { _, _ in
                if isNeeded {
                    onConfirmNeeded?()
                }
            }
            if isNeeded, let onConfirmNeeded {
                Button("确认使用这个日期", action: onConfirmNeeded)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Accent.violet)
                    .frame(minHeight: BSLayout.minTouchTarget)
                    .accessibilityHint("确认后才可以保存现场")
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddShowStartTimeField: View {
    let title: String
    @Binding var startTime: Date
    let calendar: Calendar
    let isConfirmed: Bool
    let onConfirm: () -> Void
    var isRecognized = false

    private var borderColor: Color? {
        if !isConfirmed {
            return BSColor.Stage.accent.opacity(0.50)
        }
        return isRecognized ? BSColor.Accent.prepare.opacity(0.30) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(
                title: title,
                isRequired: true,
                mark: isConfirmed ? (isRecognized ? .recognized : nil) : .needed
            )
            AddShowConstrainedDatePicker(
                selection: $startTime,
                displayedComponents: .hourAndMinute,
                calendar: calendar,
                borderColor: borderColor
            )
            if !isConfirmed {
                Button("确认使用这个时间", action: onConfirm)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Accent.violet)
                    .frame(minHeight: BSLayout.minTouchTarget)
                    .accessibilityHint("确认后才可以保存现场")
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddShowEndTimeField: View {
    @Binding var hasEndTime: Bool
    @Binding var endDate: Date
    @Binding var endTime: Date
    let calendar: Calendar

    private static let columnSpacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(alignment: .center, spacing: BSSpacing.sm) {
                Text("结束时间")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BSColor.textTertiary)
                Spacer(minLength: 0)
                Toggle("结束时间", isOn: $hasEndTime)
                    .labelsHidden()
                    .tint(BSColor.Accent.violet)
                    .frame(minWidth: BSLayout.minTouchTarget, minHeight: BSLayout.minTouchTarget)
            }

            if hasEndTime {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    AddShowDatePickerField(
                        title: "结束日期",
                        selection: $endDate,
                        displayedComponents: .date,
                        calendar: calendar,
                        isRequired: false
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        AddShowFieldLabel(title: "结束时间", isRequired: false)
                        AddShowConstrainedDatePicker(
                            selection: $endTime,
                            displayedComponents: .hourAndMinute,
                            calendar: calendar
                        )
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// 封面双入口：相册 + 图片链接，并排避免「本地封面图 / 使用图片链接」层层嵌套。
private struct AddShowCoverActions: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var showsLinkField: Bool
    let isImporting: Bool
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    AddShowCoverActionChip(
                        icon: isImporting ? nil : "photo.on.rectangle.angled",
                        title: isImporting ? "正在导入…" : "从相册选择",
                        isActive: false,
                        showsSpinner: isImporting
                    )
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .frame(maxWidth: .infinity)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsLinkField.toggle()
                    }
                } label: {
                    AddShowCoverActionChip(
                        icon: "link",
                        title: showsLinkField ? "收起链接" : "图片链接",
                        isActive: showsLinkField,
                        showsSpinner: false
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(BSFont.caption)
                    .foregroundColor(
                        message.contains("失败") || message.contains("没有")
                            ? BSColor.Accent.danger
                            : BSColor.Accent.prepare
                    )
            }
        }
    }
}

private struct AddShowCoverActionChip: View {
    let icon: String?
    let title: String
    let isActive: Bool
    let showsSpinner: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(BSColor.Accent.violet)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isActive ? BSColor.Stage.accent : BSColor.Accent.violet)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isActive ? BSColor.Stage.accent : BSColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            isActive
                ? BSColor.Stage.accent.opacity(0.10)
                : Color.white.opacity(0.045)
        )
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(
                    isActive
                        ? BSColor.Stage.accent.opacity(0.35)
                        : BSColor.borderProminent,
                    lineWidth: 1
                )
        )
    }
}

private struct AddShowFieldLabel: View {
    enum Mark {
        /// 识别导入成功：薄荷绿「✓ 已识别」
        case recognized
        /// 缺确认：金色「待确认」
        case needed
    }

    let title: String
    let isRequired: Bool
    var mark: Mark? = nil

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BSColor.textTertiary)
            if isRequired {
                Text("*")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
            }

            Spacer(minLength: 0)

            switch mark {
            case .recognized:
                Label("已识别", systemImage: "checkmark")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(BSColor.Accent.prepare)
            case .needed:
                Label("待确认", systemImage: "exclamationmark")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
            case nil:
                EmptyView()
            }
        }
    }
}

private struct AddShowMultilineInput: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textTertiary.opacity(0.74))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }

            TextEditor(text: $text)
                .font(BSFont.body)
                .foregroundColor(BSColor.textPrimary)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .textContentType(keyboardType == .URL ? .URL : nil)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: minHeight)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(BSColor.borderProminent, lineWidth: 1)
        )
    }
}

private struct AddShowNoteCard: View {
    let text: String
    let iconName: String

    var body: some View {
        HStack(alignment: .top, spacing: BSSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(BSColor.textTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.borderProminent, lineWidth: 1)
        )
    }
}

/// 链接解析失败卡：原因可行动化（重试 / 转手动双按钮），并承诺已填内容保留。
private struct AddShowLinkFailureCard: View {
    let failure: AddShowLinkFailurePresentation
    let onRetry: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(BSColor.Accent.danger.opacity(0.14))
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Accent.danger)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                    Text(failure.message)
                        .font(.system(size: 12.5))
                        .foregroundColor(BSColor.textTertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(action: onRetry) {
                    Text("换个链接重试")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onManual) {
                    Text("转手动填写")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(BSColor.Stage.accent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(BSColor.Stage.accent.opacity(0.30), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Label("已填写的内容会保留，不用重打", systemImage: "checkmark")
                .font(.system(size: 11.5))
                .foregroundColor(BSColor.Accent.prepare)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Accent.danger.opacity(0.08),
                    BSColor.Accent.danger.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(BSColor.Accent.danger.opacity(0.26), lineWidth: 1)
        )
    }
}

/// 识别导入成功横幅：提示结果来自链接 / 截图，需核对；金色标出的还需补充。
private struct AddShowImportedBanner: View {
    let source: AddShowSheet

    private var sourceName: String {
        source == .link ? "链接" : "截图"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Accent.prepare)

            Text("已从\(sourceName)识别出信息，请核对；金色标出的还需补充。")
                .font(.system(size: 12.5))
                .foregroundColor(Color(red: 0.79, green: 0.92, blue: 0.87))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Accent.prepare.opacity(0.11),
                    BSColor.Stage.accent.opacity(0.06)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(BSColor.Accent.prepare.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// 截图识别分步进度：完成打勾、进行中转圈、未开始置灰。
/// 步骤由识别期间的节奏任务驱动，最多停在「整理现场信息」直到识别结束。
private struct AddShowOCRStepsView: View {
    /// 当前进行中的步骤（1...4）；0 表示未开始。
    let activeStep: Int

    private let steps = ["读取截图", "提取文字", "整理现场信息", "生成可编辑草稿"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                let step = index + 1
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(stepBackground(for: step))
                        if step < activeStep {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(BSColor.Accent.prepare)
                        } else if step == activeStep {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(BSColor.Accent.violet)
                        } else {
                            Text("\(step)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(BSColor.Stage.dim)
                        }
                    }
                    .frame(width: 26, height: 26)

                    Text(title)
                        .font(.system(size: 13, weight: step == activeStep ? .medium : .regular))
                        .foregroundColor(stepForeground(for: step))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stepBackground(for step: Int) -> Color {
        if step < activeStep {
            return BSColor.Accent.prepare.opacity(0.15)
        } else if step == activeStep {
            return BSColor.Accent.violet.opacity(0.16)
        }
        return Color.white.opacity(0.06)
    }

    private func stepForeground(for step: Int) -> Color {
        if step < activeStep {
            return BSColor.textTertiary
        } else if step == activeStep {
            return BSColor.textPrimary
        }
        return BSColor.Stage.dim
    }
}

/// 编辑现场的分组卡片：图标 chip + 标题 + 可选提示 / 状态胶囊，Stage 色板。
/// 与首页 V4 功能卡、详情页现场状态卡保持同一卡片语言。
private struct EditShowFormCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var hint: String? = nil
    var pillText: String? = nil
    var pillTint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.13))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)

                Spacer(minLength: 0)

                if let pillText {
                    let tint = pillTint ?? BSColor.Stage.accent
                    Text(pillText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(tint.opacity(0.30), lineWidth: 1)
                        )
                } else if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                }
            }

            VStack(alignment: .leading, spacing: BSSpacing.md) {
                content
            }
        }
        .padding(16)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }
}

/// 封面预览：模糊海报底 + 居中 3:4 海报，不裁切海报画面。
private struct ShowDraftCoverPreview: View {
    let urlString: String

    var body: some View {
        ZStack {
            ShowCoverImageView(
                urlString: urlString,
                aspectRatio: 16.0 / 9.0,
                contentMode: .fill,
                enforcesAspectRatio: false,
                cornerRadius: 14
            )
            .blur(radius: 20)
            .overlay(Color.black.opacity(0.42))

            ShowCoverImageView(
                urlString: urlString,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fit,
                cornerRadius: 10
            )
            .frame(height: 186)
            .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Text("当前封面")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(BSColor.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .padding(10)
        }
        .accessibilityHidden(true)
    }
}

/// 编辑现场吸底保存按钮：钨金渐变主按钮；禁用时降为灰底，由保存栏说明原因。
private struct EditShowSaveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(
                isEnabled
                    ? Color(red: 0.15, green: 0.11, blue: 0.04)
                    : BSColor.Stage.dim
            )
            .padding(.vertical, 15)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.9 : 1)
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        if isEnabled {
            LinearGradient(
                colors: [
                    Color(red: 0.82, green: 0.67, blue: 0.42),
                    Color(red: 0.91, green: 0.78, blue: 0.56),
                    Color(red: 0.95, green: 0.86, blue: 0.66)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .opacity(isPressed ? 0.85 : 1)
        } else {
            Color.white.opacity(0.08)
        }
    }
}

private struct AddShowSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(BSColor.textSecondary)
            .padding(.vertical, 15)
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            )
    }
}

private struct AddShowInputChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(BSFont.body)
            .foregroundColor(BSColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            )
    }
}

private extension View {
    func addShowInputChrome() -> some View {
        modifier(AddShowInputChrome())
    }
}

/// Apple Music 艺人候选下拉;挂在艺人 input 下方,debounce 后实时刷新。
/// 选中后回写 canonical name + 头像,「✓ 已识别」描边消失。
private struct ArtistSearchPicker: View {
    let options: [RecognizedArtist]
    let isLoading: Bool
    let onPick: (RecognizedArtist) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BSColor.textTertiary)
                Text("iTunes 候选")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BSColor.textTertiary)
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(BSColor.textTertiary)
                }
            }
            .padding(.horizontal, 4)

            if options.isEmpty && !isLoading {
                Text("暂无匹配，可直接保存手输名字")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(BSColor.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 {
                            Divider()
                                .background(BSColor.borderProminent.opacity(0.5))
                                .padding(.leading, 44)
                        }
                        ArtistSearchRow(
                            option: option,
                            onPick: { onPick(option) }
                        )
                    }
                }
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.md)
                        .stroke(BSColor.borderProminent, lineWidth: 1)
                )
            }
        }
        .padding(.top, 2)
    }
}

private struct ArtistSearchRow: View {
    let option: RecognizedArtist
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 10) {
                Text(option.canonicalName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(BSColor.Stage.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 一行艺人输入:TextField + Apple Music 候选下拉 + 已识别头像 + × 删除。
/// 每行自带 debounce Task,互不干扰。
private struct ArtistInputRow: View {
    let index: Int
    @Binding var name: String
    @Binding var avatar: String?
    let artistSearch: any ArtistSearchServicing
    let canDelete: Bool
    let onPick: (RecognizedArtist) -> Void
    let onDelete: () -> Void
    let onTextChange: () -> Void

    @State private var searchTask: Task<Void, Never>?
    @State private var recognizedOptions: [RecognizedArtist] = []
    @State private var isSearching = false
    /// 选中候选项后,parent 通过 binding 写回新名字,onChange 会再次触发新一轮搜索。
    /// 用这个 flag 吃掉那次多余的搜索,让 picker 真收起。
    @State private var suppressNextSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("艺人名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(BSColor.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .fill(BSColor.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.border, lineWidth: 1)
                    )
                    .onChange(of: name) { _, newValue in
                        if suppressNextSearch {
                            suppressNextSearch = false
                            return
                        }
                        onTextChange()
                        scheduleSearch(for: newValue)
                    }

                if let avatar, let url = URL(string: avatar) {
                    ArtistAvatarThumb(url: url, size: 28)
                }

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(BSColor.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canDelete)
                .opacity(canDelete ? 1 : 0.35)
            }

            if isSearching || !recognizedOptions.isEmpty {
                ArtistSearchPicker(
                    options: recognizedOptions,
                    isLoading: isSearching,
                    onPick: handlePick
                )
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    @MainActor
    private func handlePick(_ option: RecognizedArtist) {
        searchTask?.cancel()
        recognizedOptions = []
        isSearching = false
        suppressNextSearch = true
        onPick(option)
    }

    @MainActor
    private func scheduleSearch(for rawQuery: String) {
        searchTask?.cancel()
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            recognizedOptions = []
            return
        }
        isSearching = true
        let service = artistSearch
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            do {
                let results = try await service.searchArtists(query: trimmed)
                if Task.isCancelled { return }
                recognizedOptions = Array(results.prefix(5))
                isSearching = false
            } catch {
                if Task.isCancelled { return }
                recognizedOptions = []
                isSearching = false
            }
        }
    }
}

private extension Array {
    /// 越界返回 nil,form 写入路径用,避免每次 append 后都要判 range。
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension AddShowSheet {
    var navigationTitle: String {
        switch self {
        case .manual: return "手动填写"
        case .screenshot: return "截图识别"
        case .link: return "链接解析"
        }
    }

    var draftSource: ShowDraftSource {
        switch self {
        case .manual: return .manual
        case .screenshot: return .screenshotOCR
        case .link: return .link
        }
    }

    var saveButtonTitle: String {
        "添加现场"
    }
}
