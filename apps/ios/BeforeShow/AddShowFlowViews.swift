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
                    message: "目前支持大麦、秀动。你可以继续在下方手动填写。"
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
                message: "目前支持大麦、秀动。你可以继续在下方手动填写。"
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

enum AddShowSheet: Identifiable {
    case manual
    case screenshot
    case link

    var id: String {
        switch self {
        case .manual: return "manual"
        case .screenshot: return "screenshot"
        case .link: return "link"
        }
    }
}

struct AddShowCoordinatorSheet: View {
    /// When true (first-show onboarding), dismiss control reads as「先逛逛」instead of「取消」.
    var allowsBrowseSkip: Bool = false
    var onShowAdded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSheet: AddShowSheet?

    var body: some View {
        Group {
            if let selectedSheet {
                AddShowFlowView(
                    sheet: selectedSheet,
                    onSaved: {
                        dismiss()
                        onShowAdded()
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            self.selectedSheet = nil
                        }
                    }
                )
            } else {
                AddShowEntryView(
                    dismissTitle: allowsBrowseSkip ? "先逛逛" : "取消",
                    onDismiss: {
                        dismiss()
                    },
                    onSelect: { sheet in
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedSheet = sheet
                        }
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--open-add-show-manual") else {
                return
            }
            selectedSheet = .manual
        }
        #endif
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
            addSheet = .link
        } label: {
            Label("链接解析", systemImage: "link")
        }

        Button {
            addSheet = .screenshot
        } label: {
            Label("截图识别", systemImage: "text.viewfinder")
        }

        Button {
            addSheet = .manual
        } label: {
            Label("手动添加", systemImage: "square.and.pencil")
        }
    }
}

private struct AddShowEntryView: View {
    var dismissTitle: String = "取消"
    let onDismiss: () -> Void
    let onSelect: (AddShowSheet) -> Void

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // sheet 导航：与编辑现场同一语言（左侧取消 + 居中标题）
                ZStack {
                    Text("添加现场")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)

                    HStack {
                        Button {
                            onDismiss()
                        } label: {
                            Text(dismissTitle)
                                .font(BSFont.body)
                                .foregroundColor(BSColor.textSecondary)
                                .frame(minWidth: 44, minHeight: BSLayout.minTouchTarget, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(dismissTitle)

                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        VStack(alignment: .leading, spacing: BSSpacing.sm) {
                            Text("把下一场现场\n放进来")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(BSColor.textPrimary)

                            Text("三种方式都可以，识别出的内容保存前都能改。")
                                .font(BSFont.body)
                                .foregroundColor(BSColor.textTertiary)
                                .lineSpacing(3)
                        }

                        VStack(spacing: BSSpacing.md) {
                            AddShowMethodCard(
                                title: "链接解析",
                                subtitle: "粘贴大麦或秀动的链接，自动提取名称、时间、场馆。",
                                iconName: "link",
                                tint: BSColor.Stage.accent,
                                isRecommended: true,
                                metaItems: ["约 5 秒", "支持大麦 · 秀动"]
                            ) {
                                onSelect(.link)
                            }

                            AddShowMethodCard(
                                title: "截图识别",
                                subtitle: "选择票务截图，设备端识别名称、时间、场馆，不上传。",
                                iconName: "camera.fill",
                                tint: BSColor.Accent.violet,
                                metaItems: ["设备端识别", "截图不离开手机"]
                            ) {
                                onSelect(.screenshot)
                            }

                            AddShowMethodCard(
                                title: "手动填写",
                                subtitle: "没有链接或截图时，自己填写现场的基本信息。",
                                iconName: "square.and.pencil",
                                tint: BSColor.Accent.prepare,
                                metaItems: ["约 1 分钟", "只填名称和时间也行"]
                            ) {
                                onSelect(.manual)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(BSColor.Accent.prepare)
                            Text("所有信息只存在这台设备上")
                        }
                        .font(.system(size: 11.5))
                        .foregroundColor(BSColor.Stage.dim)
                        .frame(maxWidth: .infinity)
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
    @Environment(\.modelContext) private var modelContext
    @Query private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""

    let sheet: AddShowSheet
    let linkParser: ShowLinkDraftParser
    private let onSaved: (() -> Void)?
    private let onBack: (() -> Void)?

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
    @State private var showsProMembership = false
    @State private var showsProSaveLimit = false
    @State private var toast: BSToastPayload?
    @State private var temporaryCoverURLs: Set<String> = []
    @State private var didSave = false
    @State private var ocrActiveStep = 0

    init(
        sheet: AddShowSheet,
        linkParser: ShowLinkDraftParser = AddShowFlowView.defaultLinkParser(),
        onSaved: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.sheet = sheet
        self.linkParser = linkParser
        self.onSaved = onSaved
        self.onBack = onBack
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
                flowNavBar

                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        methodContent

                        if hasImportedDraft {
                            AddShowImportedBanner(
                                source: sheet,
                                infoCount: importedInfoCount
                            )
                        }

                        if shouldShowDraftFields {
                            ShowDraftFormFields(
                                draft: $draft,
                                usesCardLayout: true,
                                recognizedHighlight: hasImportedDraft,
                                coverEmptyPlaceholder: true,
                                onCoverImported: registerImportedCover
                            )
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
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .onChange(of: selectedScreenshotItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await recognizeScreenshot(from: newItem)
            }
        }
        .onDisappear {
            guard !didSave else { return }
            cleanupTemporaryCovers()
        }
        .sheet(isPresented: $showsProMembership) {
            ProMembershipSheetView()
        }
        .sheet(isPresented: $showsProSaveLimit) {
            BSProLimitSheet(
                title: ProLimitReason.saveLimit.title,
                message: ProLimitReason.saveLimit.message
            ) {
                showsProSaveLimit = false
                showsProMembership = true
            } onSecondary: {
                showsProSaveLimit = false
            }
        }
        .bsToastOverlay(toast, bottomPadding: 28)
    }

    // MARK: - 顶部导航（与编辑现场同一 sheet 语言）

    /// 识别完成后进入「确认现场信息」语义，呼应确认页必达（链接/OCR 不静默保存）。
    private var flowNavTitle: String {
        hasImportedDraft ? "确认现场信息" : sheet.navigationTitle
    }

    private var flowNavBar: some View {
        ZStack {
            Text(flowNavTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.textPrimary)

            HStack {
                Button {
                    closeOrBack()
                } label: {
                    Text(onBack == nil ? "取消" : "‹ 返回")
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textSecondary)
                        .frame(minWidth: 44, minHeight: BSLayout.minTouchTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(onBack == nil ? "取消" : "返回")

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    /// 粘贴即识别链接来源，不用等一次失败往返。
    private var detectedLinkSource: String? {
        let text = linkText.lowercased()
        if text.contains("damai") { return "大麦" }
        if text.contains("showstart") { return "秀动" }
        return nil
    }

    /// 识别成功横幅里的信息项计数：名称 / 艺人 / 城市 / 场馆 / 开场日期（必有）/ 开场时间。
    private var importedInfoCount: Int {
        var count = 1
        if !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !draft.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !draft.venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if draft.startTime != nil { count += 1 }
        return count
    }

    @ViewBuilder
    private var methodContent: some View {
        switch sheet {
        case .manual:
            EmptyView()
        case .link:
            linkContent
        case .screenshot:
            screenshotContent
        }
    }

    private var linkContent: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            EditShowFormCard(
                title: "票务链接",
                icon: "link",
                tint: BSColor.Stage.accent,
                hint: "粘贴后自动识别来源"
            ) {
                AddShowMultilineInput(
                    placeholder: "https://...",
                    text: $linkText,
                    minHeight: 96,
                    keyboardType: .URL
                )

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
                    Task {
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

                AddShowNoteCard(
                    text: "解析通常 5 秒内完成，失败也能转手动填写，已填内容会保留。",
                    iconName: "info.circle"
                )
            }

            if let linkFailure {
                AddShowLinkFailureCard(
                    failure: linkFailure,
                    onRetry: {
                        self.linkFailure = nil
                        linkText = ""
                    },
                    onManual: {
                        showsManualFallback = true
                    }
                )
            }

            AddShowNoteCard(
                text: "目前支持：大麦、秀动。其他来源的链接会提示你转手动填写。",
                iconName: "link"
            )
        }
    }

    private var screenshotContent: some View {
        let isRecognizing = isRecognizingScreenshot

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

            if showsManualFallback && sheet == .screenshot && !hasImportedDraft {
                BSEmptyPanel(
                    iconName: "text.viewfinder",
                    title: "截图识别失败",
                    message: "没有识别到可用的现场信息。可以继续在下方手动填写。",
                    buttonTitle: "手动填写",
                    buttonIconName: "square.and.pencil"
                ) {
                    showsManualFallback = true
                }
            }

            AddShowNoteCard(
                text: "识别只提取名称、时间、场馆，不读取座位、价格、订单号；截图不离开这台设备。",
                iconName: "lock.shield"
            )

        }
    }

    private var shouldShowDraftFields: Bool {
        sheet == .manual || showsManualFallback || hasImportedDraft
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
            .disabled(!draft.isReadyToSave || isSaving)
            .accessibilityLabel(isSaving ? "正在保存" : sheet.saveButtonTitle)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.black.opacity(0.28)))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BSColor.Stage.border)
                .frame(height: 1)
        }
    }

    private func saveProgressSegment(filled: Bool) -> some View {
        let ready = draft.isReadyToSave
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

    /// 按优先级说明距离可保存还差什么（名称 → 开场时间 → 时间范围）。
    private var saveBarStatus: SaveBarStatus {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SaveBarStatus(text: "还差现场名称", tint: BSColor.Stage.muted)
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
        if sheet == .manual {
            return SaveBarStatus(
                text: "可以保存了 · 封面和更多信息可添加后再补充",
                tint: BSColor.Stage.dim
            )
        }
        return SaveBarStatus(
            text: "请核对识别出的信息，确认后保存",
            tint: BSColor.Stage.dim
        )
    }

    private func closeOrBack() {
        dismissKeyboard()
        cleanupTemporaryCovers()
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    @MainActor
    private func recognizeScreenshot(from item: PhotosPickerItem) async {
        isRecognizingScreenshot = true
        ocrActiveStep = 1

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
            isRecognizingScreenshot = false
            ocrActiveStep = 0
            selectedScreenshotItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                draft.source = .manual
                showsManualFallback = true
                message = "没有读到这张截图，请改用手动填写。"
                presentToast(.failure, message: "读取失败")
                return
            }

            draft = try await OnDeviceShowScreenshotRecognizer().draft(from: image)
            hasImportedDraft = true
            showsManualFallback = false
            message = draft.startTime == nil
                ? "已识别部分信息，请确认日期并补充开场时间。"
                : nil
            presentToast(.success, message: "识别完成")
        } catch {
            draft.source = .manual
            hasImportedDraft = false
            showsManualFallback = true
            message = "没有识别到可用的现场信息，请改用手动填写。"
            presentToast(.failure, message: "识别失败")
        }
    }

    @MainActor
    private func parseLink() async {
        dismissKeyboard()
        isParsingLink = true
        defer {
            isParsingLink = false
        }

        do {
            draft = try await linkParser.draft(from: linkText)
            hasImportedDraft = true
            showsManualFallback = false
            linkFailure = nil
            message = draft.startTime == nil
                ? "链接里没有明确开场时间，请确认后再添加。"
                : nil
            presentToast(.success, message: "解析完成")
        } catch {
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
        isSaving = true
        dismissKeyboard()

        do {
            let entitlement = ProEntitlementStorage.decode(entitlementRawValue)
            guard ProFeatureGate().canAddShow(savedShowCount: shows.count, entitlement: entitlement) else {
                message = "免费版可以保存 1 场现场。开通 Pro 后可以继续添加。"
                showsProSaveLimit = true
                presentToast(.neutral, message: "保存上限")
                isSaving = false
                return
            }

            let show = try draft.makeShow()
            modelContext.insert(show)

            // Always become current (not only the first show).
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

            await activateNotifications(for: show, state: notificationState)
            didSave = true
            finalizeTemporaryCovers(keeping: draft.coverImageURL)

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

    private func registerImportedCover(previous: String, new: String) {
        if temporaryCoverURLs.contains(previous) {
            ShowCoverLocalImageStore.removeManagedLocalImage(at: previous)
            temporaryCoverURLs.remove(previous)
        }
        temporaryCoverURLs.insert(new)
    }

    private func cleanupTemporaryCovers() {
        for urlString in temporaryCoverURLs {
            ShowCoverLocalImageStore.removeManagedLocalImage(at: urlString)
        }
        temporaryCoverURLs.removeAll()
    }

    private func finalizeTemporaryCovers(keeping keptURL: String) {
        for urlString in temporaryCoverURLs where urlString != keptURL {
            ShowCoverLocalImageStore.removeManagedLocalImage(at: urlString)
        }
        temporaryCoverURLs.removeAll()
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

/// 编辑现场 sheet 内的现场状态管理上下文：状态展示 + 立即生效的状态操作。
/// 由详情页注入；为 nil 时编辑器不渲染现场状态卡（例如仅编辑草稿的场景）。
/// 状态操作不走「保存」按钮，沿用详情页语义立即生效，闭包返回用于 toast 的文案。
struct ShowStatusEditingContext {
    let changeStatus: ShowChangeStatus
    let postponedDate: Date?
    let title: String
    let description: String
    let restoreTitle: String
    let onRestore: @MainActor () async -> String
    let onPostpone: @MainActor (Date?) async -> String
    let onCancel: @MainActor () async -> String
    let onDelete: @MainActor () async -> Void
}

struct ShowDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
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
    @State private var temporaryCoverURLs: Set<String> = []
    @State private var didSave = false
    @State private var postponeDate = Date()
    @State private var showsPostponeSheet = false
    @State private var showsCancelConfirm = false
    @State private var showsDeleteConfirm = false
    @State private var isApplyingStatus = false
    @State private var statusToast: BSToastPayload?

    init(
        title: String,
        subtitle: String = "修改后会立即更新这个现场。",
        draft: ShowDraft,
        saveTitle: String,
        statusPillText: String? = nil,
        isPostponed: Bool = false,
        statusEditing: ShowStatusEditingContext? = nil,
        onSave: @escaping @MainActor (ShowDraft) async throws -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
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
        draft != initialDraft
    }

    private var isEndTimeRangeValid: Bool {
        draft.startTime == nil || draft.hasValidEndTime()
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                editorNavBar

                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.md) {
                        editorSummaryCard
                        if isPostponed {
                            postponedBanner
                        }

                        ShowDraftFormFields(
                            draft: $draft,
                            includesSeatSection: true,
                            usesCardLayout: true,
                            onCoverImported: registerImportedCover
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
                onUndated: {
                    showsPostponeSheet = false
                    Task { @MainActor in
                        await applyStatusAction { await statusEditing?.onPostpone(nil) }
                    }
                },
                onDated: {
                    showsPostponeSheet = false
                    let newDate = postponeDate
                    Task { @MainActor in
                        await applyStatusAction { await statusEditing?.onPostpone(newDate) }
                    }
                },
                onCancel: {
                    showsPostponeSheet = false
                }
            )
        }
        .sheet(isPresented: $showsCancelConfirm) {
            BSDangerConfirmationSheet(
                title: "记录取消",
                message: "记录为取消后，这场现场仍会保留在“我的现场”中，但不会出现在当前现场。",
                destructiveTitle: "确认取消",
                onConfirm: {
                    showsCancelConfirm = false
                    Task { @MainActor in
                        await applyStatusAction { await statusEditing?.onCancel() }
                    }
                },
                onCancel: {
                    showsCancelConfirm = false
                }
            )
        }
        .sheet(isPresented: $showsDeleteConfirm) {
            BSDangerConfirmationSheet(
                title: "删除现场",
                message: "删除后，这场现场将无法恢复。",
                destructiveTitle: "删除",
                onConfirm: {
                    showsDeleteConfirm = false
                    Task { @MainActor in
                        await statusEditing?.onDelete()
                    }
                },
                onCancel: {
                    showsDeleteConfirm = false
                }
            )
        }
        .bsToastOverlay(statusToast, bottomPadding: 96)
        .alert("放弃修改？", isPresented: $showsDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) {
                cleanupTemporaryCovers()
                dismiss()
            }
        } message: {
            Text("尚未保存的现场信息会丢失。")
        }
        .onDisappear {
            guard !didSave else { return }
            cleanupTemporaryCovers()
        }
    }

    // MARK: - 顶部导航

    private var editorNavBar: some View {
        ZStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.textPrimary)

            HStack {
                Button {
                    requestDismiss()
                } label: {
                    Text("取消")
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textSecondary)
                        .frame(minWidth: 44, minHeight: BSLayout.minTouchTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消编辑")

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
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
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_Hans_CN")
        dateFormatter.dateFormat = "M月d日"
        var text = (isPostponed ? "原定 " : "") + dateFormatter.string(from: draft.date)
        if let startTime = draft.startTime {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "zh_Hans_CN")
            timeFormatter.dateFormat = "HH:mm"
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
        _ action: @MainActor () async -> String?
    ) async {
        guard !isApplyingStatus else { return }
        isApplyingStatus = true
        let message = await action()
        isApplyingStatus = false
        if let message {
            presentStatusToast(.success, message: message)
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
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.black.opacity(0.28)))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BSColor.Stage.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var saveBarStatus: some View {
        if let message {
            Text(message)
                .foregroundColor(BSColor.Accent.danger)
        } else if !isEndTimeRangeValid {
            Text("时间范围无效，修正后才能保存")
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

    private func requestDismiss() {
        dismissKeyboard()
        if hasUnsavedChanges {
            showsDiscardConfirmation = true
        } else {
            cleanupTemporaryCovers()
            dismiss()
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard draft.hasValidEndTime() else {
            message = "结束时间需要晚于开始时间，请检查下方时间范围。"
            return
        }

        isSaving = true
        message = nil
        dismissKeyboard()

        do {
            try await onSave(draft)
            finalizeCoverEdit()
            didSave = true
            dismiss()
        } catch {
            message = "没有保存成功，请重试。你的修改仍保留在这里。"
            isSaving = false
        }
    }

    private func registerImportedCover(previous: String, new: String) {
        if temporaryCoverURLs.contains(previous) {
            ShowCoverLocalImageStore.removeManagedLocalImage(at: previous)
            temporaryCoverURLs.remove(previous)
        }
        temporaryCoverURLs.insert(new)
    }

    private func cleanupTemporaryCovers() {
        for urlString in temporaryCoverURLs {
            ShowCoverLocalImageStore.removeManagedLocalImage(at: urlString)
        }
        temporaryCoverURLs.removeAll()
    }

    private func finalizeCoverEdit() {
        for urlString in temporaryCoverURLs where urlString != draft.coverImageURL {
            ShowCoverLocalImageStore.removeManagedLocalImage(at: urlString)
        }
        if originalCoverURL != draft.coverImageURL {
            ShowCoverLocalImageStore.removeManagedLocalImage(at: originalCoverURL)
        }
        temporaryCoverURLs.removeAll()
    }
}

private struct ShowDraftFormFields: View {
    @Binding var draft: ShowDraft
    let includesSeatSection: Bool
    /// true 时按编辑现场的卡片布局渲染（基本信息 / 日期时间 / 地点 / 封面四张卡）；
    /// false 保持添加现场流程的平铺分组不变。
    let usesCardLayout: Bool
    /// 添加现场·识别导入（链接 / 截图）：进入表单时已有值的字段标「✓ 已识别」薄荷绿描边，
    /// 缺失的开场时间金色标出。标记以进入表单时的草稿为准，用户后续改动不撤销标记。
    let recognizedHighlight: Bool
    /// 添加现场：无封面时显示虚线引导占位，封面卡标注「可选 · 保存后也能加」。
    let coverEmptyPlaceholder: Bool
    let onCoverImported: (String, String) -> Void
    @State private var startTime: Date
    @State private var hasEndTime: Bool
    @State private var endDate: Date
    @State private var endTime: Date
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isImportingCover = false
    @State private var coverImportMessage: String?
    @State private var showsCoverLinkField = false
    private let nameRecognized: Bool
    private let artistRecognized: Bool
    private let cityRecognized: Bool
    private let venueRecognized: Bool
    private let startTimeRecognized: Bool

    init(
        draft: Binding<ShowDraft>,
        includesSeatSection: Bool = false,
        usesCardLayout: Bool = false,
        recognizedHighlight: Bool = false,
        coverEmptyPlaceholder: Bool = false,
        onCoverImported: @escaping (String, String) -> Void = { _, _ in }
    ) {
        let initialDraft = draft.wrappedValue
        let fallbackStart = Calendar.current.date(
            bySettingHour: 19,
            minute: 30,
            second: 0,
            of: initialDraft.date
        ) ?? initialDraft.date
        let initialEndDate = initialDraft.endDate ?? initialDraft.date
        let fallbackEnd = Calendar.current.date(
            bySettingHour: 23,
            minute: 55,
            second: 0,
            of: initialEndDate
        ) ?? initialEndDate

        self._draft = draft
        self.includesSeatSection = includesSeatSection
        self.usesCardLayout = usesCardLayout
        self.recognizedHighlight = recognizedHighlight
        self.coverEmptyPlaceholder = coverEmptyPlaceholder
        self.onCoverImported = onCoverImported
        _startTime = State(initialValue: initialDraft.startTime ?? fallbackStart)
        // End section covers both end clock and multi-day end date.
        _hasEndTime = State(initialValue: initialDraft.endTime != nil || initialDraft.endDate != nil)
        _endDate = State(initialValue: initialEndDate)
        _endTime = State(initialValue: initialDraft.endTime ?? fallbackEnd)
        nameRecognized = recognizedHighlight
            && !initialDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        artistRecognized = recognizedHighlight
            && !initialDraft.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        cityRecognized = recognizedHighlight
            && !initialDraft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        venueRecognized = recognizedHighlight
            && !initialDraft.venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        startTimeRecognized = recognizedHighlight && initialDraft.startTime != nil
    }

    var body: some View {
        Group {
            if usesCardLayout {
                cardLayout
            } else {
                legacyLayout
            }
        }
        .onChange(of: hasEndTime) { _, newValue in
            syncEndTimeToDraft(isEnabled: newValue)
        }
        .onChange(of: startTime) { _, _ in
            draft.startTime = mergedStartTime()
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
                if endDate < draft.date {
                    endDate = draft.date
                }
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: draft.date) { _, _ in
            if draft.startTime != nil {
                draft.startTime = mergedStartTime()
            }
            if hasEndTime {
                if endDate < draft.date {
                    endDate = draft.date
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

    /// 编辑现场：四张卡片布局（Stage 色板，与首页 V4 / 现场状态卡同一语言）。
    private var cardLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditShowFormCard(title: "基本信息", icon: "square.and.pencil", tint: BSColor.Stage.accent) {
                AddShowLabeledTextField(
                    title: "现场名称",
                    placeholder: "例：五月天上海演唱会",
                    text: $draft.name,
                    isRequired: true,
                    isRecognized: nameRecognized
                )

                AddShowLabeledTextField(
                    title: "艺人 / 阵容",
                    placeholder: "五月天",
                    text: $draft.artist,
                    isRecognized: artistRecognized
                )

                if includesSeatSection {
                    AddShowLabeledTextField(
                        title: "座位或区域",
                        placeholder: "看台 / 内场 / 排号",
                        text: $draft.seatSection
                    )
                }

                if !draft.artistAvatarURLs.isEmpty {
                    ArtistAvatarStackView(urls: draft.artistAvatarURLs, size: 42)
                }
            }

            EditShowFormCard(
                title: "日期与时间",
                icon: "clock",
                tint: BSColor.Accent.violet,
                hint: "开场必填 · 散场可选"
            ) {
                AddShowScheduleFields(
                    draft: $draft,
                    startTime: $startTime,
                    isStartTimeConfirmed: draft.startTime != nil,
                    onConfirmStartTime: {
                        draft.startTime = mergedStartTime()
                    },
                    hasEndTime: $hasEndTime,
                    endDate: $endDate,
                    endTime: $endTime,
                    dateRecognized: recognizedHighlight,
                    startTimeRecognized: startTimeRecognized
                )

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

                AddShowLabeledTextField(
                    title: "场馆",
                    placeholder: "上海体育场",
                    text: $draft.venueName,
                    isRecognized: venueRecognized
                )

                BSAddressSuggestionField(
                    label: "场馆地址",
                    placeholder: "街道门牌，方便到场",
                    text: $draft.venueAddress,
                    city: draft.city,
                    seedKeyword: draft.venueName,
                    helperText: "下面有小地图，点一下就能选准地址。"
                )
            }

            EditShowFormCard(
                title: "封面",
                icon: "photo",
                tint: BSColor.Stage.accent,
                hint: coverEmptyPlaceholder ? "可选 · 保存后也能加" : nil
            ) {
                if !draft.coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ShowDraftCoverPreview(urlString: draft.coverImageURL)
                } else if coverEmptyPlaceholder {
                    HStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(BSColor.Accent.violet)
                        Text("暂无封面 · 保存后也能补充")
                            .font(.system(size: 12.5))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
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

                AddShowCoverImportField(
                    selectedItem: $selectedCoverItem,
                    isImporting: isImportingCover,
                    message: coverImportMessage
                )

                DisclosureGroup(isExpanded: $showsCoverLinkField) {
                    AddShowLabeledTextField(
                        title: "图片链接",
                        placeholder: "https://...",
                        text: $draft.coverImageURL,
                        keyboardType: .URL
                    )
                    .padding(.top, BSSpacing.sm)
                } label: {
                    Label(
                        showsCoverLinkField ? "收起图片链接" : "使用图片链接",
                        systemImage: "link"
                    )
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                }
                .tint(BSColor.textTertiary)
            }
        }
    }

    /// 添加现场流程：保持原有平铺分组，仅把封面预览换成不裁切的 3:4 海报预览。
    private var legacyLayout: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            if !draft.coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AddShowFieldGroup(title: "当前封面") {
                    ShowDraftCoverPreview(urlString: draft.coverImageURL)
                }
            }

            if !draft.artistAvatarURLs.isEmpty {
                AddShowFieldGroup(title: "艺人头像") {
                    ArtistAvatarStackView(urls: draft.artistAvatarURLs, size: 42)
                }
            }

            AddShowFieldGroup(title: "基本信息") {
                AddShowLabeledTextField(
                    title: "现场名称",
                    placeholder: "例：五月天上海演唱会",
                    text: $draft.name,
                    isRequired: true
                )

                AddShowLabeledTextField(
                    title: "艺人 / 阵容",
                    placeholder: "五月天",
                    text: $draft.artist
                )

                if includesSeatSection {
                    AddShowLabeledTextField(
                        title: "座位或区域",
                        placeholder: "看台 / 内场 / 排号",
                        text: $draft.seatSection
                    )
                }
            }

            AddShowFieldGroup(title: "日期与时间") {
                AddShowScheduleFields(
                    draft: $draft,
                    startTime: $startTime,
                    isStartTimeConfirmed: draft.startTime != nil,
                    onConfirmStartTime: {
                        draft.startTime = mergedStartTime()
                    },
                    hasEndTime: $hasEndTime,
                    endDate: $endDate,
                    endTime: $endTime
                )

                if draft.startTime != nil && !draft.hasValidEndTime() {
                    Label("结束时间需要晚于开始时间", systemImage: "exclamationmark.circle.fill")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Accent.danger)
                        .accessibilityLabel("时间范围无效，结束时间需要晚于开始时间")
                }
            }

            AddShowFieldGroup(title: "地点") {
                AddShowLabeledTextField(
                    title: "城市",
                    placeholder: "上海",
                    text: $draft.city
                )

                AddShowLabeledTextField(
                    title: "场馆",
                    placeholder: "上海体育场",
                    text: $draft.venueName
                )

                BSAddressSuggestionField(
                    label: "场馆地址",
                    placeholder: "街道门牌，方便到场",
                    text: $draft.venueAddress,
                    city: draft.city,
                    seedKeyword: draft.venueName,
                    helperText: "下面有小地图，点一下就能选准地址。"
                )
            }

            AddShowFieldGroup(title: "更换封面") {
                AddShowCoverImportField(
                    selectedItem: $selectedCoverItem,
                    isImporting: isImportingCover,
                    message: coverImportMessage
                )

                DisclosureGroup(isExpanded: $showsCoverLinkField) {
                    AddShowLabeledTextField(
                        title: "图片链接",
                        placeholder: "https://...",
                        text: $draft.coverImageURL,
                        keyboardType: .URL
                    )
                    .padding(.top, BSSpacing.sm)
                } label: {
                    Label(
                        showsCoverLinkField ? "收起图片链接" : "使用图片链接",
                        systemImage: "link"
                    )
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                }
                .tint(BSColor.textTertiary)
            }
        }
    }

    private func mergedStartTime() -> Date {
        mergedTime(on: draft.date, time: startTime)
    }

    private func syncEndTimeToDraft(isEnabled: Bool) {
        guard isEnabled else {
            draft.endDate = nil
            draft.endTime = nil
            return
        }

        let resolvedEndDay = max(endDate, draft.date)
        endDate = resolvedEndDay
        draft.endDate = resolvedEndDay
        draft.endTime = mergedTime(on: resolvedEndDay, time: endTime)
    }

    private func mergedTime(on date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
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
            coverImportMessage = "已使用本地封面图"
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
    var isRecommended: Bool = false
    var metaItems: [String] = []
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
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(BSColor.textPrimary)
                            .lineLimit(1)

                        if isRecommended {
                            Text("推荐")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.15, green: 0.11, blue: 0.04))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.82, green: 0.67, blue: 0.42),
                                            BSColor.Stage.accent
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundColor(BSColor.textTertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !metaItems.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(metaItems, id: \.self) { item in
                                Text(item)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(BSColor.Stage.dim)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.dim)
                    .frame(maxHeight: .infinity)
            }
            .padding(18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(BSColor.Stage.surface)
                    if isRecommended {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        BSColor.Stage.accent.opacity(0.07),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        isRecommended ? BSColor.Stage.accent.opacity(0.38) : BSColor.Stage.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecommended ? "\(title)，推荐" : title)
    }
}

private struct AddShowFieldGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            BSSectionHeader(title: title)
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                content
            }
        }
    }
}

private struct AddShowLabeledTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isRequired = false
    var isRecognized = false
    var keyboardType: UIKeyboardType = .default

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
    /// 识别导入且开场时间已确认：标「已识别」；未确认时金色「待确认」。
    var startTimeRecognized: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: BSSpacing.md) {
                AddShowDatePickerField(
                    title: "开场日期",
                    selection: $draft.date,
                    displayedComponents: .date,
                    isRecognized: dateRecognized
                )

                AddShowStartTimeField(
                    title: "开场时间",
                    startTime: $startTime,
                    isConfirmed: isStartTimeConfirmed,
                    onConfirm: onConfirmStartTime,
                    isRecognized: startTimeRecognized
                )
            }

            AddShowEndTimeField(
                hasEndTime: $hasEndTime,
                endDate: $endDate,
                endTime: $endTime
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: hasEndTime)
    }
}

private struct AddShowDatePickerField: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    var isRequired = true
    var isRecognized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(
                title: title,
                isRequired: isRequired,
                mark: isRecognized ? .recognized : nil
            )
            DatePicker("", selection: $selection, displayedComponents: displayedComponents)
                .labelsHidden()
                .tint(BSColor.Accent.violet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .addShowInputChrome()
                .overlay {
                    if isRecognized {
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.Accent.prepare.opacity(0.30), lineWidth: 1)
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AddShowStartTimeField: View {
    let title: String
    @Binding var startTime: Date
    let isConfirmed: Bool
    let onConfirm: () -> Void
    var isRecognized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(
                title: title,
                isRequired: true,
                mark: isConfirmed ? (isRecognized ? .recognized : nil) : .needed
            )
            DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(BSColor.Accent.violet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .addShowInputChrome()
                .overlay {
                    if !isConfirmed {
                        // 关键信息缺失：金色描边 + 光晕，引导先补这一项
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.Stage.accent.opacity(0.50), lineWidth: 1)
                            .shadow(color: BSColor.Stage.accent.opacity(0.10), radius: 6)
                    } else if isRecognized {
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.Accent.prepare.opacity(0.30), lineWidth: 1)
                    }
                }
            Text(isConfirmed ? "用于开场前提醒；之后随时能改。" : "用于开场前提醒；可先填大概时间。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if !isConfirmed {
                Button("确认使用这个时间", action: onConfirm)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Accent.violet)
                    .frame(minHeight: BSLayout.minTouchTarget)
                    .accessibilityHint("确认后才可以保存现场")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AddShowEndTimeField: View {
    @Binding var hasEndTime: Bool
    @Binding var endDate: Date
    @Binding var endTime: Date

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.xs) {
                AddShowFieldLabel(title: "结束时间", isRequired: false)
                Spacer(minLength: 0)
                Toggle("结束时间", isOn: $hasEndTime)
                    .labelsHidden()
                    .tint(BSColor.Accent.violet)
                    .frame(minWidth: BSLayout.minTouchTarget, minHeight: BSLayout.minTouchTarget)
            }

            if hasEndTime {
                HStack(alignment: .top, spacing: 12) {
                    AddShowDatePickerField(
                        title: "结束日期",
                        selection: $endDate,
                        displayedComponents: .date
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        AddShowFieldLabel(title: "结束时间", isRequired: false)
                        DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(BSColor.Accent.violet)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .addShowInputChrome()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text("可选。跨天或跨午夜时打开，结束日期可以和开场日不同。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.border, lineWidth: 1)
                    )
            }
        }
    }
}

private struct AddShowCoverImportField: View {
    @Binding var selectedItem: PhotosPickerItem?
    let isImporting: Bool
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(title: "本地封面图", isRequired: false)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack(spacing: BSSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BSColor.Accent.violet.opacity(0.16))
                        if isImporting {
                            ProgressView()
                                .tint(BSColor.Accent.violet)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(BSColor.Accent.violet)
                        }
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isImporting ? "正在导入封面图" : "从相册选择封面图")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(BSColor.textSecondary)
                        Text(message ?? "选择后会覆盖上方封面图链接")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.md)
                        .stroke(BSColor.borderProminent, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
        }
    }
}

private struct AddShowFieldLabel: View {
    enum Mark {
        /// 识别导入成功：薄荷绿「✓ 已识别」
        case recognized
        /// 关键信息缺失：金色「待确认」
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

            if let mark {
                switch mark {
                case .recognized:
                    Label("已识别", systemImage: "checkmark")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(BSColor.Accent.prepare)
                case .needed:
                    Text("待确认")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(BSColor.Stage.accent)
                }
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

/// 识别导入成功横幅：说清「绿色 = 识别结果待核对，金色 = 还差的关键信息」。
private struct AddShowImportedBanner: View {
    let source: AddShowSheet
    let infoCount: Int

    private var sourceName: String {
        source == .link ? "链接" : "截图"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Accent.prepare)

            Text("已从\(sourceName)识别 \(infoCount) 项信息。绿色描边的是识别结果，请核对；金色的是还差的关键信息，补上就能保存。")
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
        switch self {
        case .manual:
            return "保存草稿"
        case .screenshot, .link:
            return "确认并添加"
        }
    }
}
