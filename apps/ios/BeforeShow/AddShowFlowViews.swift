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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        onDismiss()
                    } label: {
                        Text(dismissTitle)
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.textSecondary)
                            .frame(minHeight: BSLayout.minTouchTarget, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dismissTitle)
                    .padding(.bottom, BSSpacing.sm)

                    Text("添加现场")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)

                    Text("把你要去的音乐现场放进来，\n慢慢靠近那一场。")
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textTertiary)
                        .lineSpacing(3)
                        .padding(.top, BSSpacing.sm)

                    VStack(spacing: BSSpacing.md) {
                        AddShowMethodCard(
                            title: "链接解析",
                            subtitle: "粘贴大麦或秀动的链接，自动提取现场信息。",
                            iconName: "link",
                            tint: BSColor.Accent.info
                        ) {
                            onSelect(.link)
                        }

                        AddShowMethodCard(
                            title: "截图识别",
                            subtitle: "选择票务截图，设备端识别名称、时间、场馆，不上传。",
                            iconName: "camera.fill",
                            tint: BSColor.Accent.violet
                        ) {
                            onSelect(.screenshot)
                        }

                        AddShowMethodCard(
                            title: "手动填写",
                            subtitle: "没有链接或截图时，自己填写现场的基本信息。",
                            iconName: "square.and.pencil",
                            tint: BSColor.Accent.prepare
                        ) {
                            onSelect(.manual)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.top, BSSpacing.xl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
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

            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    AddShowFlowHeader(
                        title: sheet.navigationTitle,
                        subtitle: sheet.introText,
                        backTitle: onBack == nil ? "取消" : "返回",
                        onBack: closeOrBack
                    )

                    methodContent

                    if shouldShowDraftFields {
                        ShowDraftFormFields(
                            draft: $draft,
                            onCoverImported: registerImportedCover
                        )

                        VStack(spacing: BSSpacing.sm) {
                            Button {
                                Task {
                                    await save()
                                }
                            } label: {
                                Text(sheet.saveButtonTitle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AddShowPrimaryButtonStyle())
                            .disabled(!draft.isReadyToSave || isSaving)

                            if sheet == .manual {
                                Text("可添加后再补充封面图和更多信息")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(BSColor.textTertiary.opacity(0.65))
                                    .frame(maxWidth: .infinity)
                            } else if hasImportedDraft {
                                Button {
                                    showsManualFallback = true
                                } label: {
                                    Text("手动修改")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(AddShowSecondaryButtonStyle())
                            }
                        }
                    }

                    if let message {
                        AddShowNoteCard(text: message, iconName: "info.circle")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
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
            AddShowMultilineInput(
                placeholder: "https://...",
                text: $linkText,
                minHeight: 112,
                keyboardType: .URL
            )

            Button {
                dismissKeyboard()
                Task {
                    await parseLink()
                }
            } label: {
                HStack {
                    if isParsingLink {
                        ProgressView()
                            .tint(.black)
                    }
                    Text("开始解析")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AddShowPrimaryButtonStyle())
            .disabled(isParsingLink || linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let linkFailure {
                BSEmptyPanel(
                    iconName: "exclamationmark.triangle",
                    title: linkFailure.title,
                    message: linkFailure.message,
                    buttonTitle: "手动填写",
                    buttonIconName: "square.and.pencil"
                ) {
                    showsManualFallback = true
                }
            }

            AddShowNoteCard(
                text: "目前支持：大麦、秀动。不支持的链接会提示你转手动填写。",
                iconName: "link"
            )
        }
    }

    private var screenshotContent: some View {
        let isRecognizing = isRecognizingScreenshot

        return VStack(alignment: .leading, spacing: BSSpacing.md) {
            PhotosPicker(selection: $selectedScreenshotItem, matching: .images) {
                VStack(spacing: BSSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .fill(Color.white.opacity(0.055))
                            .frame(width: 64, height: 64)
                        Image(systemName: isRecognizing ? "text.viewfinder" : "camera.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(BSColor.Accent.violet)
                    }

                    if isRecognizing {
                        HStack(spacing: BSSpacing.sm) {
                            ProgressView()
                                .tint(BSColor.textSecondary)
                            Text("正在设备端识别")
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textSecondary)
                        }
                    } else {
                        Text("点击选择截图")
                            .font(BSFont.body)
                            .foregroundColor(BSColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 318)
                .padding(.vertical, BSSpacing.xl)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            BSColor.borderProminent,
                            style: StrokeStyle(lineWidth: 2, dash: [7, 7])
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isRecognizing)
            .simultaneousGesture(TapGesture().onEnded {
                dismissKeyboard()
            })

            if isRecognizing {
                BSLoadingStatePanel(
                    title: "截图识别中",
                    message: "正在设备端识别文字，只提取现场基础信息。"
                )
            }

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
                text: "建议上传包含现场名称、日期、场馆的截图。不会提取座位、价格等敏感信息。",
                iconName: "lock.shield"
            )

        }
    }

    private var shouldShowDraftFields: Bool {
        sheet == .manual || showsManualFallback || hasImportedDraft
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
        defer {
            isRecognizingScreenshot = false
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

struct ShowDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
    let saveTitle: String
    let onSave: @MainActor (ShowDraft) async throws -> Void
    private let initialDraft: ShowDraft
    private let originalCoverURL: String

    @State private var draft: ShowDraft
    @State private var message: String?
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false
    @State private var temporaryCoverURLs: Set<String> = []
    @State private var didSave = false

    init(
        title: String,
        subtitle: String = "修改后会立即更新这个现场。",
        draft: ShowDraft,
        saveTitle: String,
        onSave: @escaping @MainActor (ShowDraft) async throws -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        _draft = State(initialValue: draft)
        self.saveTitle = saveTitle
        self.onSave = onSave
        initialDraft = draft
        originalCoverURL = draft.coverImageURL
    }

    private var hasUnsavedChanges: Bool {
        draft != initialDraft
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    AddShowFlowHeader(
                        title: title,
                        subtitle: subtitle,
                        backTitle: "取消",
                        onBack: {
                            requestDismiss()
                        }
                    )

                    ShowDraftFormFields(
                        draft: $draft,
                        includesSeatSection: true,
                        onCoverImported: registerImportedCover
                    )

                    Button {
                        Task { @MainActor in
                            await save()
                        }
                    } label: {
                        HStack(spacing: BSSpacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text(isSaving ? "正在保存" : saveTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AddShowPrimaryButtonStyle())
                    .disabled(!draft.isReadyToSave || isSaving)

                    if let message {
                        Text(message)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Accent.danger)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .interactiveDismissDisabled(hasUnsavedChanges || isSaving)
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
    let onCoverImported: (String, String) -> Void
    @State private var startTime: Date
    @State private var hasEndTime: Bool
    @State private var endDate: Date
    @State private var endTime: Date
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isImportingCover = false
    @State private var coverImportMessage: String?
    @State private var showsCoverLinkField = false

    init(
        draft: Binding<ShowDraft>,
        includesSeatSection: Bool = false,
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
        self.onCoverImported = onCoverImported
        _startTime = State(initialValue: initialDraft.startTime ?? fallbackStart)
        _hasEndTime = State(initialValue: initialDraft.endTime != nil)
        _endDate = State(initialValue: initialEndDate)
        _endTime = State(initialValue: initialDraft.endTime ?? fallbackEnd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            if !draft.coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AddShowFieldGroup(title: "当前封面") {
                    ShowCoverImageView(
                        urlString: draft.coverImageURL,
                        aspectRatio: 16.0 / 10.0,
                        contentMode: .fill,
                        enforcesAspectRatio: false
                    )
                    .frame(height: includesSeatSection ? 160 : 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .clipped()
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

                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    AddShowFieldLabel(title: "类型", isRequired: false)
                    AddShowTypePicker(selection: $draft.type)
                }

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
        .onChange(of: hasEndTime) { _, newValue in
            syncEndTimeToDraft(isEnabled: newValue)
        }
        .onChange(of: startTime) { _, _ in
            draft.startTime = mergedStartTime()
            if draft.type == .musicFestival {
                syncEndTimeToDraft(isEnabled: hasEndTime)
            } else if !hasEndTime {
                syncEndTimeToDraft(isEnabled: false)
            }
        }
        .onChange(of: endTime) { _, _ in
            if hasEndTime {
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: endDate) { _, _ in
            if draft.type == .musicFestival {
                syncEndTimeToDraft(isEnabled: hasEndTime)
            } else if hasEndTime {
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: draft.date) { _, _ in
            if draft.startTime != nil {
                draft.startTime = mergedStartTime()
            }
            if draft.type == .musicFestival,
               endDate < draft.date {
                endDate = draft.date
            }
            if draft.type == .musicFestival {
                syncEndTimeToDraft(isEnabled: hasEndTime)
            } else if hasEndTime {
                syncEndTimeToDraft(isEnabled: true)
            }
        }
        .onChange(of: draft.type) { _, _ in
            if draft.type == .musicFestival {
                endDate = draft.endDate ?? max(endDate, draft.date)
                draft.endDate = endDate
                draft.endTime = hasEndTime ? mergedTime(on: endDate, time: endTime) : nil
            } else if !hasEndTime {
                draft.endDate = nil
                draft.endTime = nil
            }
        }
        .onChange(of: selectedCoverItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importCover(from: newItem)
            }
        }
    }

    private func mergedStartTime() -> Date {
        mergedTime(on: draft.date, time: startTime)
    }

    private func syncEndTimeToDraft(isEnabled: Bool) {
        if draft.type == .musicFestival {
            draft.endDate = max(endDate, draft.date)
            draft.endTime = isEnabled ? mergedTime(on: draft.endDate ?? endDate, time: endTime) : nil
            return
        }

        draft.endDate = isEnabled ? endDate : nil
        draft.endTime = isEnabled ? mergedTime(on: endDate, time: endTime) : nil
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

private struct AddShowFlowHeader: View {
    let title: String
    let subtitle: String
    let backTitle: String
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                Text(backTitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 72, minHeight: BSLayout.minTouchTarget)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .padding(.bottom, BSSpacing.sm)

            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(BSColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(BSFont.body)
                .foregroundColor(BSColor.textTertiary)
                .lineSpacing(3)
                .padding(.top, BSSpacing.sm)
                .fixedSize(horizontal: false, vertical: true)
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
                    RoundedRectangle(cornerRadius: 18)
                        .fill(tint.opacity(0.15))
                    Image(systemName: iconName)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textTertiary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(title: title, isRequired: isRequired)
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .textContentType(keyboardType == .URL ? .URL : nil)
                .keyboardType(keyboardType)
                .addShowInputChrome()
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

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: BSSpacing.md) {
                AddShowDatePickerField(
                    title: draft.type == .musicFestival ? "开始日期" : "开场日期",
                    selection: $draft.date,
                    displayedComponents: .date
                )

                if draft.type == .musicFestival {
                    AddShowDatePickerField(
                        title: "结束日期",
                        selection: $endDate,
                        displayedComponents: .date
                    )
                } else {
                    AddShowStartTimeField(
                        title: "开场时间",
                        startTime: $startTime,
                        isConfirmed: isStartTimeConfirmed,
                        onConfirm: onConfirmStartTime
                    )
                }
            }

            AddShowStartTimeField(
                title: "每日开场时间",
                startTime: $startTime,
                isConfirmed: isStartTimeConfirmed,
                onConfirm: onConfirmStartTime
            )
            .opacity(draft.type == .musicFestival ? 1 : 0)
            .frame(height: draft.type == .musicFestival ? nil : 0)
            .accessibilityHidden(draft.type != .musicFestival)

            AddShowEndTimeField(
                hasEndTime: $hasEndTime,
                endDate: $endDate,
                endTime: $endTime
            )
        }
        .frame(maxWidth: .infinity, minHeight: 258, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: draft.type)
    }
}

private struct AddShowDatePickerField: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    var isRequired = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(title: title, isRequired: isRequired)
            DatePicker("", selection: $selection, displayedComponents: displayedComponents)
                .labelsHidden()
                .tint(BSColor.Accent.violet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .addShowInputChrome()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AddShowStartTimeField: View {
    let title: String
    @Binding var startTime: Date
    let isConfirmed: Bool
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(title: title, isRequired: true)
            DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(BSColor.Accent.violet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .addShowInputChrome()
            Text("用于开场前提醒；可先填大概时间。")
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
                        AddShowFieldLabel(title: "结束", isRequired: false)
                        DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(BSColor.Accent.violet)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .addShowInputChrome()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text("未填写时，状态判断会按开场当天晚间兜底")
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

private struct AddShowTypePicker: View {
    @Binding var selection: ShowType

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            ForEach(ShowType.allCases, id: \.self) { type in
                Button {
                    selection = type
                } label: {
                    Text(type.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selection == type ? BSColor.textPrimary : BSColor.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: BSLayout.minTouchTarget)
                        .background(selection == type ? Color.white.opacity(0.11) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selection == type ? Color.white.opacity(0.20) : BSColor.borderProminent, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == type ? .isSelected : [])
            }
        }
    }
}

private struct AddShowFieldLabel: View {
    let title: String
    let isRequired: Bool

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

private struct AddShowPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.black)
            .padding(.vertical, 15)
            .background(Color.white.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.88 : 1)
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

    var introText: String {
        switch self {
        case .manual:
            return "填写现场的基本信息。"
        case .screenshot:
            return "上传票务截图，OCR 提取现场信息。"
        case .link:
            return "粘贴受支持来源的链接，我们会提取出现场草稿。"
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
