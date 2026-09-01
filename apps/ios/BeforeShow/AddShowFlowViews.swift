import Foundation
import PhotosUI
import PostHog
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
                    title: BSLocalization.text("这个链接暂不支持"),
                    message: BSLocalization.format("目前支持：%@。你可以继续在下方手动填写。", ShowLinkPlatformCatalog.supportSummary)
                )
            case .missingDate:
                return Self(
                    title: BSLocalization.text("还缺少现场信息"),
                    message: BSLocalization.text("没有解析到有效日期，请在下方补充后再保存。")
                )
            }
        }

        guard let parsingError = error as? ShowLinkParsingError else {
            return Self(
                title: BSLocalization.text("链接解析失败"),
                message: BSLocalization.text("暂时没能读出完整信息。你可以重试，或继续在下方手动填写。")
            )
        }

        switch parsingError {
        case .unsupportedSource:
            return Self(
                title: BSLocalization.text("这个链接暂不支持"),
                message: BSLocalization.format("目前支持：%@。你可以继续在下方手动填写。", ShowLinkPlatformCatalog.supportSummary)
            )
        case .networkFailure:
            return Self(
                title: BSLocalization.text("网络连接失败"),
                message: BSLocalization.text("请检查网络后重试，已经填写的内容会保留。")
            )
        case .invalidResponse:
            return Self(
                title: BSLocalization.text("还缺少现场信息"),
                message: BSLocalization.text("没有解析到有效日期，请在下方补充后再保存。")
            )
        case .notAShow:
            return Self(
                title: BSLocalization.text("这不是演出链接"),
                message: BSLocalization.text("这个链接指向的是周边商品，没有演出场次信息。你可以换个演出链接重试，或在下方手动填写。")
            )
        case .parseFailed:
            return Self(
                title: BSLocalization.text("链接解析失败"),
                message: BSLocalization.text("暂时没能读出完整信息。你可以重试，或继续在下方手动填写。")
            )
        }
    }
}


struct AddShowFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""

    let sheet: AddShowSheet
    let linkParser: ShowLinkDraftParser
    private let onSaved: ((UUID) -> Void)?
    private let onFinished: (() -> Void)?

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
    /// 首次请求通知权限前的说明页。`nil` = 不展示。
    @State private var isShowingNotificationPrimer = false
    /// 说明页的用户选择回传。保存流程会一直等到用户在说明页上做出选择，
    /// 再决定是否弹系统权限弹窗，之后才继续 dismiss。
    @State private var notificationPrimerDecision: CheckedContinuation<Bool, Never>?
    @State private var showsLinkGuide = false
    /// 引导页里点过「打开 XX」才置真；关闭引导页时只有这种情况才读剪贴板，
    /// 避免只是翻翻平台也触发系统粘贴弹窗。
    @State private var didOpenPlatformFromGuide = false
    /// 引导页关闭后检测到剪贴板里有支持平台的链接时，出「粘贴XX链接？」chip。
    @State private var linkPasteSuggestion: (link: String, platform: String)?
    @State private var coverLifecycle = ShowCoverLifecycle()
    @State private var didSave = false
    @State private var savedShowConfirmation: SavedShowConfirmation?
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
    @State private var pendingLifecycleConfirmation: PendingAddShowLifecycleConfirmation?
    @State private var detailTarget: AddShowDetailDestination?

    init(
        sheet: AddShowSheet,
        linkParser: ShowLinkDraftParser = AddShowFlowView.defaultLinkParser(),
        prefilledDraft: ShowDraft? = nil,
        onSaved: ((UUID) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        self.sheet = sheet
        self.linkParser = linkParser
        self.onSaved = onSaved
        self.onFinished = onFinished
        if let prefilledDraft {
            _draft = State(initialValue: prefilledDraft)
            _hasImportedDraft = State(initialValue: true)
        } else {
            let initialDraft = sheet == .manual
                ? AddShowConfiguration.initialManualDraft()
                : ShowDraft(source: sheet.draftSource)
            _draft = State(initialValue: initialDraft)
        }
    }

    static func defaultLinkParser() -> ShowLinkDraftParser {
        ShowLinkDraftParser(service: RemoteShowLinkParsingService(client: .production()))
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            if let savedShowConfirmation {
                AddShowSavedConfirmationView(
                    confirmation: savedShowConfirmation,
                    onOpen: { presentDetail(for: savedShowConfirmation) },
                    onDone: finishFlow
                )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
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
        }
        .navigationTitle(flowNavTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(savedShowConfirmation == nil ? .automatic : .hidden, for: .navigationBar)
        .interactiveDismissDisabled(isSaving)
        .preferredColorScheme(.dark)
        .environment(\.locale, AppLanguageManager.persisted.locale)
        .onChange(of: selectedScreenshotItem) { _, newItem in
            guard let newItem else { return }
            beginImportTask {
                await recognizeScreenshot(from: newItem)
            }
        }
        .onChange(of: linkText) { _, _ in
            // 用户手动编辑后，之前的剪贴板建议已过期
            linkPasteSuggestion = nil
        }
        .onDisappear {
            // 页面离开时作废进行中的导入，避免任务在 dismiss 后继续写状态 / 弹 toast
            abandonInFlightImport()
            guard !didSave else { return }
            coverLifecycle.cancel()
        }
        .navigationDestination(item: $detailTarget) { target in
            Group {
                if let show = shows.first(where: { $0.id == target.showID }) {
                    switch target.kind {
                    case .show:
                        ShowDetailView(show: show)
                    case .footprint:
                        FootprintDetailView(
                            show: show,
                            archive: FootprintArchiveBuilder.make(shows: shows)
                        )
                    }
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(item: $pendingLifecycleConfirmation) { pending in
            AddShowLifecycleConfirmationSheet(
                showName: pending.show.name,
                showStart: AddShowLifecyclePolicy.minimumEndTime(
                    for: pending.show,
                    calendar: pending.show.timingCalendar()
                ),
                canConfirmEnd: AddShowLifecyclePolicy.canConfirmEnd(
                    for: pending.show,
                    calendar: pending.show.timingCalendar()
                ),
                calendar: pending.show.endTimingCalendar(),
                onLive: {
                    pendingLifecycleConfirmation = nil
                    Task { @MainActor in
                        await persistPreparedShow(pending.show, lifecycle: .live)
                    }
                },
                onEnded: { endTime in
                    pending.show.markEnded(at: endTime)
                    pendingLifecycleConfirmation = nil
                    Task { @MainActor in
                        await persistPreparedShow(pending.show, lifecycle: .ended)
                    }
                }
            )
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
                ProPaywallSheetView()
            }
        }
        .sheet(isPresented: $showsLinkGuide, onDismiss: {
            if didOpenPlatformFromGuide {
                detectPasteboardLink()
            }
            didOpenPlatformFromGuide = false
        }) {
            AddShowLinkGuideView(onOpenPlatform: {
                didOpenPlatformFromGuide = true
            })
        }
        .sheet(isPresented: $isShowingNotificationPrimer, onDismiss: {
            // 下划关闭等同「暂时不用」：不能让保存流程悬在 continuation 上。
            resumeNotificationPrimer(accepted: false)
        }) {
            NotificationPermissionPrimerView(
                onContinue: {
                    isShowingNotificationPrimer = false
                    resumeNotificationPrimer(accepted: true)
                },
                onSkip: {
                    isShowingNotificationPrimer = false
                    resumeNotificationPrimer(accepted: false)
                }
            )
        }
        .bsToastOverlay(toast, bottomPadding: 28)
        #if DEBUG
        .task {
            if Self.debugOpenNotificationPrimer {
                isShowingNotificationPrimer = true
            }
        }
        #endif
    }

    #if DEBUG
    /// 截图 / 验证用：直接拉起通知说明页，不必先走完保存流程。
    private static var debugOpenNotificationPrimer: Bool {
        ProcessInfo.processInfo.arguments.contains("--open-notification-primer")
    }
    #endif

    /// 识别后直接进可编辑表单，和手动填写同一套导航标题，不再多一层「确认」。
    private var flowNavTitle: String {
        didSwitchToManual ? BSLocalization.text("手动填写") : sheet.navigationTitle
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
                    title: BSLocalization.text("票务链接"),
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

                    // 从引导页回来、剪贴板里有支持平台的链接时，一键粘贴并直接解析
                    if let linkPasteSuggestion, !isParsingLink {
                        Button {
                            applyPasteSuggestion()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(BSLocalization.format("粘贴%@链接？", linkPasteSuggestion.platform))
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(BSColor.Accent.prepare)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(BSColor.Accent.prepare.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: BSRadius.md)
                                    .stroke(BSColor.Accent.prepare.opacity(0.28), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(BSLocalization.format("粘贴%@链接并开始解析", linkPasteSuggestion.platform))
                    }

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

                    Text(BSLocalization.format("目前支持：%@。你可以继续在下方手动填写。", ShowLinkPlatformCatalog.supportSummary))
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.Stage.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        dismissKeyboard()
                        showsLinkGuide = true
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
                    title: BSLocalization.text("识别进度"),
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
                        title: BSLocalization.text("截图识别失败"),
                        message: BSLocalization.text("没有识别到可用的现场信息。可以继续在下方手动填写。"),
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
                    Text(isSaving ? BSLocalization.text("正在保存") : AddShowConfiguration.saveButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditShowSaveButtonStyle())
            .disabled(!draft.isReadyToSave || isSaving || needsDateConfirmation || isImportingDraft)
            .accessibilityLabel(
                isImportingDraft
                    ? BSLocalization.text("正在导入，暂不可保存")
                    : (isSaving ? BSLocalization.text("正在保存") : AddShowConfiguration.saveButtonTitle)
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
            return SaveBarStatus(text: BSLocalization.text("还差现场名称"), tint: BSColor.Stage.muted)
        }
        if needsDateConfirmation {
            return SaveBarStatus(
                text: BSLocalization.text("还差确认开场日期 · 截图没读到日期，已先填今天"),
                tint: BSColor.Stage.muted
            )
        }
        if draft.startTime == nil {
            return SaveBarStatus(
                text: BSLocalization.text("还差开场时间 · 用于开场前提醒，可先填大概时间"),
                tint: BSColor.Stage.muted
            )
        }
        if !draft.hasValidEndTime() {
            return SaveBarStatus(
                text: BSLocalization.text("时间范围无效，结束时间需要晚于开始时间"),
                tint: BSColor.Accent.danger
            )
        }
        return SaveBarStatus(
            text: BSLocalization.text("可以添加了 · 封面等可之后再补"),
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
                message = BSLocalization.text("没有读到这张截图，请改用手动填写。")
                presentToast(.failure, message: BSLocalization.text("读取失败"))
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
                message = BSLocalization.text("截图里没有识别到日期，已先填今天，请改成实际开场日期。")
            } else if recognized.startTime == nil {
                message = BSLocalization.text("已识别部分信息，请确认日期并补充开场时间。")
            } else {
                message = nil
            }
            PostHogSDK.shared.capture("screenshot_recognized")
            presentToast(.success, message: BSLocalization.text("识别完成"))
        } catch is CancellationError {
            // 页面关闭或新请求取消：不写失败态
            return
        } catch {
            guard isActiveImportRequest(requestRevision) else { return }
            draft.source = .manual
            hasImportedDraft = false
            showsManualFallback = true
            message = BSLocalization.text("没有识别到可用的现场信息，请改用手动填写。")
            presentToast(.failure, message: BSLocalization.text("识别失败"))
        }
    }

    /// 引导页关闭时读一次剪贴板：是支持平台的链接就提示一键粘贴。
    /// 直接读内容会出一次系统粘贴提示横幅，换取 chip 里能带上平台名。
    private func detectPasteboardLink() {
        guard sheet == .link, !hasImportedDraft,
              linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let raw = UIPasteboard.general.string else { return }
        let candidate = ShowLinkDraftParser.normalizedLink(raw)
        guard !candidate.isEmpty,
              let host = URL(string: candidate)?.host()?.lowercased(),
              let platform = ShowLinkPlatformCatalog.displayName(forHost: host) else { return }
        linkPasteSuggestion = (candidate, platform)
    }

    /// chip 确认后：填入链接并直接开始解析，意图已足够明确。
    private func applyPasteSuggestion() {
        guard let suggestion = linkPasteSuggestion else { return }
        linkPasteSuggestion = nil
        linkText = suggestion.link
        beginImportTask {
            await parseLink()
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
                ? BSLocalization.text("链接里没有明确开场时间，请确认后再添加。")
                : nil
            PostHogSDK.shared.capture("show_link_parsed")
            presentToast(.success, message: BSLocalization.text("解析完成"))
        } catch is CancellationError {
            return
        } catch {
            guard isActiveImportRequest(requestRevision) else { return }
            draft.source = .manual
            hasImportedDraft = false
            showsManualFallback = true
            linkFailure = AddShowLinkFailurePresentation.resolve(error)
            message = nil
            presentToast(.failure, message: BSLocalization.text("解析失败"))
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard !isImportingDraft else { return }
        guard !needsDateConfirmation else { return }
        isSaving = true
        dismissKeyboard()

        do {
            let show = try draft.makeShow()
            if let duplicate = ShowDuplicateMatcher.firstDuplicate(of: show, in: shows) {
                PostHogSDK.shared.capture("duplicate_show_blocked", properties: [
                    "method": sheet.rawValue,
                    "existing_show_id": duplicate.id.uuidString
                ])
                savedShowConfirmation = SavedShowConfirmation(
                    showID: duplicate.id,
                    name: duplicate.name,
                    coverImageURL: duplicate.coverImageURL,
                    kind: .duplicate(detailOutcome(for: duplicate))
                )
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                isSaving = false
                return
            }

            let entitlement = ProEntitlementStorage.decode(entitlementRawValue)
            let gate = ProFeatureGate()
            let addedThisMonth = gate.showsAddedThisMonth(from: shows)
            guard gate.canAddShow(showsAddedThisMonth: addedThisMonth, entitlement: entitlement) else {
                PostHogSDK.shared.capture("pro_limit_reached")
                paywallSheet = .limit
                presentToast(.neutral, message: BSLocalization.text("保存上限"))
                isSaving = false
                return
            }

            switch AddShowLifecyclePolicy.resolution(for: show) {
            case .future:
                await persistPreparedShow(show, lifecycle: .future)
            case .ended:
                await persistPreparedShow(show, lifecycle: .ended)
            case .needsEndConfirmation:
                pendingLifecycleConfirmation = PendingAddShowLifecycleConfirmation(show: show)
                isSaving = false
            }
        } catch ShowValidationError.invalidEndTime {
            message = BSLocalization.text("结束时间需要晚于开始时间。")
            presentToast(.failure, message: BSLocalization.text("时间范围无效"))
            isSaving = false
        } catch ShowValidationError.missingStartTime {
            message = BSLocalization.text("请确认开场时间。")
            presentToast(.failure, message: BSLocalization.text("还缺开场时间"))
            isSaving = false
        } catch ShowValidationError.emptyName {
            message = BSLocalization.text("请填写现场名称。")
            presentToast(.failure, message: BSLocalization.text("保存失败"))
            isSaving = false
        } catch {
            modelContext.rollback()
            message = BSLocalization.text("请填写必填信息。")
            presentToast(.failure, message: BSLocalization.text("保存失败"))
            isSaving = false
        }
    }

    @MainActor
    private func persistPreparedShow(
        _ show: Show,
        lifecycle: AddShowFinalLifecycle
    ) async {
        isSaving = true
        do {
            let result = try AddShowPersistenceCoordinator.persist(
                show,
                lifecycle: lifecycle,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext
            )

            if let notificationState = result.notificationState {
                let notificationFocusShow = notificationState.focusedShowID.flatMap { focusedShowID in
                    if focusedShowID == show.id {
                        return show
                    }
                    return shows.first(where: { $0.id == focusedShowID })
                }
                await activateNotifications(for: notificationFocusShow, state: notificationState)
            }

            PostHogSDK.shared.capture("show_added", properties: [
                "method": sheet.rawValue,
                "lifecycle": result.outcome.rawValue
            ])
            AppReviewPrompt.consider(.addedShow)
            didSave = true
            coverLifecycle.finalize(keeping: draft.coverImageURL)

            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                savedShowConfirmation = SavedShowConfirmation(
                    showID: show.id,
                    name: show.name,
                    coverImageURL: show.coverImageURL,
                    kind: .saved(result.outcome)
                )
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSaving = false
            onSaved?(show.id)
        } catch AddShowPersistenceError.duplicateShow(let existingShowID) {
            modelContext.rollback()
            if let duplicate = shows.first(where: { $0.id == existingShowID }) {
                savedShowConfirmation = SavedShowConfirmation(
                    showID: duplicate.id,
                    name: duplicate.name,
                    coverImageURL: duplicate.coverImageURL,
                    kind: .duplicate(detailOutcome(for: duplicate))
                )
            } else {
                message = BSLocalization.text("这场已经在 BeforeShow 里了")
                presentToast(.neutral, message: BSLocalization.text("这场已经在 BeforeShow 里了"))
            }
            isSaving = false
        } catch {
            modelContext.rollback()
            message = BSLocalization.text("请填写必填信息。")
            presentToast(.failure, message: BSLocalization.text("保存失败"))
            isSaving = false
        }
    }

    private func detailOutcome(for show: Show) -> AddShowSaveOutcome {
        let state = CurrentShowTimeState(show: show)
        if state.kind == .postShow || state.kind == .ended {
            return .footprint
        }
        if CurrentShowSession().isCurrent(
            show,
            among: shows,
            manualSelection: selections.first
        ) {
            return .current
        }
        return .future
    }

    private func presentDetail(for confirmation: SavedShowConfirmation) {
        detailTarget = AddShowDetailDestination(
            showID: confirmation.showID,
            kind: confirmation.outcome == .footprint ? .footprint : .show
        )
    }

    private func finishFlow() {
        if let onFinished {
            onFinished()
        } else {
            dismiss()
        }
    }

    @MainActor
    private func activateNotifications(
        for show: Show?,
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
            // 先解释再请求：系统弹窗只有一次机会，用户得先知道会收到什么。
            let accepted = await presentNotificationPrimer()
            // 无论用户是否接受，都记下已经问过，不再反复打扰。
            state.recordPermissionRequest()
            try? modelContext.save()
            if accepted {
                _ = await center.requestAuthorization()
            }
        }

        await center.applyFocusChange(to: show, in: modelContext)
    }

    /// 展示说明页并等待用户选择。返回 `true` 表示可以继续弹系统权限弹窗。
    @MainActor
    private func presentNotificationPrimer() async -> Bool {
        await withCheckedContinuation { continuation in
            notificationPrimerDecision = continuation
            isShowingNotificationPrimer = true
        }
    }

    @MainActor
    private func resumeNotificationPrimer(accepted: Bool) {
        guard let continuation = notificationPrimerDecision else { return }
        notificationPrimerDecision = nil
        continuation.resume(returning: accepted)
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


extension ShowDraft {
    var isReadyToSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && startTime != nil
            && hasValidEndTime()
    }
}

@MainActor
func dismissKeyboard() {
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


/// 编辑现场 sheet 内的现场状态管理上下文：状态展示 + 立即生效的状态操作。
/// 由详情页注入；为 nil 时编辑器不渲染现场状态卡（例如仅编辑草稿的场景）。
/// 状态操作不走「保存」按钮，沿用详情页语义立即生效，闭包返回 toast 的语气与文案。


/// 自己画日期文案，系统 compact DatePicker 只负责点按弹出。
/// 否则系统内框比半列瓷贴宽，右边会被 clip 成贴边。


/// 「待确认」字段的显式确认 CTA：整宽紫底按钮，替代容易漏看的小字文本按钮。


/// 封面双入口：相册 + 图片链接，并排避免「本地封面图 / 使用图片链接」层层嵌套。


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
        source == .link ? BSLocalization.text("链接") : BSLocalization.text("截图")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Accent.prepare)

            Text(BSLocalization.format("已从%@识别出信息，请核对；金色标出的还需补充。", sourceName))
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

    private let steps = [BSLocalization.text("读取截图"), BSLocalization.text("提取文字"), BSLocalization.text("整理现场信息"), BSLocalization.text("生成可编辑草稿")]

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
struct EditShowFormCard<Content: View>: View {
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


/// 编辑现场吸底保存按钮：钨金渐变主按钮；禁用时降为灰底，由保存栏说明原因。
struct EditShowSaveButtonStyle: ButtonStyle {
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

extension View {
    func addShowInputChrome() -> some View {
        modifier(AddShowInputChrome())
    }
}

/// Apple Music 艺人候选下拉;挂在艺人 input 下方,debounce 后实时刷新。
/// 选中后回写 canonical name + 头像,「✓ 已识别」描边消失。


/// 一行艺人输入:TextField + Apple Music 候选下拉 + 已识别头像 + × 删除。
/// 每行自带 debounce Task,互不干扰。
