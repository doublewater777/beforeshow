import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - Add Show Flow

struct AddShowFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""

    @State private var sheet: AddShowSheet
    let linkParser: ShowLinkDraftParser
    private let onSaved: ((UUID) -> Void)?

    @State private var draft: ShowDraft
    @State private var selectedScreenshotItem: PhotosPickerItem?
    @State private var linkText = ""
    /// 截图读取 / 识别失败时留在入口页的说明。
    @State private var importNote: String?
    @State private var linkFailure: AddShowLinkFailurePresentation?
    @State private var isRecognizingScreenshot = false
    @State private var isParsingLink = false
    @State private var isSaving = false
    @State private var hasImportedDraft = false
    @State private var showsPaywall = false
    @State private var isAtFreeCapacity = false
    @State private var coverLifecycle = ShowCoverLifecycle()
    @State private var didSave = false
    /// 保存成功后按钮内的轻反馈文案；显示片刻后关闭页面。
    @State private var savedTitle: String?
    @State private var saveFailure: String?
    @State private var ocrActiveStep = 0
    /// 每次成功导入（链接 / 截图）+1，驱动表单重建以重置内部时间影子状态。
    @State private var importRevision = 0
    /// 每次发起解析 / 识别 +1；返回时若 revision 已过期则丢弃结果，避免旧请求覆盖新请求。
    @State private var importRequestRevision = 0
    /// 用户自上次 import 后手改过的字段;下次 import 时跳过这些字段,
    /// 防止 OCR / link 解析偷偷覆盖用户输入。import 完成后清空。
    @State private var userEditedFields: Set<ShowDraftField> = []
    /// Apple Music 艺人搜索;可注入 Stub 跑测试。
    @State private var artistSearch: any ArtistSearchServicing = AppleMusicArtistSearchService()
    /// 当前进行中的解析 / OCR 任务；关闭页面时取消，避免后台继续写回。
    @State private var importTask: Task<Void, Never>?
    /// OCR 未识别日期（回退为今天）时，用户需显式确认后才可保存。
    @State private var fallbackDateConfirmed = false
    @State private var lifecycleQuestion: AddShowLifecycleQuestion?
    @State private var lifecycleChoice: AddShowLifecycleChoice?
    @State private var lifecycleEndTime = Date()

    init(
        sheet: AddShowSheet,
        linkParser: ShowLinkDraftParser = AddShowFlowView.defaultLinkParser(),
        prefilledDraft: ShowDraft? = nil,
        onSaved: ((UUID) -> Void)? = nil
    ) {
        _sheet = State(initialValue: sheet)
        self.linkParser = linkParser
        self.onSaved = onSaved
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

                            if let lifecycleQuestion {
                                AddShowLifecycleChoiceCard(
                                    question: lifecycleQuestion,
                                    choice: $lifecycleChoice,
                                    endTime: $lifecycleEndTime
                                )
                                .transition(.opacity)
                            }
                        }

                        if let importNote, !shouldShowDraftFields {
                            AddShowNoteCard(text: importNote, iconName: "info.circle")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .animation(.easeInOut(duration: BSMotion.interface), value: lifecycleQuestion)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                if shouldShowDraftFields {
                    AddShowSaveBar(
                        status: saveBarStatus,
                        isSaving: isSaving,
                        savedTitle: savedTitle,
                        action: { Task { await save() } }
                    )
                }
            }
        }
        .navigationTitle(AddShowConfiguration.navigationTitle)
        .toolbar {
            if shouldShowDraftFields {
                ToolbarItem(placement: .topBarLeading) {
                    Button(BSLocalization.text("返回"), systemImage: "chevron.left") {
                        dismissKeyboard()
                        sheet = .link
                        hasImportedDraft = false
                        importNote = nil
                    }
                    .disabled(isSaving || isImportingDraft || savedTitle != nil)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // 已经填了内容就不能被一滑关掉；明确放弃走右上角关闭。
        .interactiveDismissDisabled(isSaving || savedTitle != nil || hasUnsavedInput)
        .preferredColorScheme(.dark)
        .onChange(of: selectedScreenshotItem) { _, newItem in
            guard let newItem else { return }
            sheet = .screenshot
            linkFailure = nil
            importNote = nil
            beginImportTask {
                await recognizeScreenshot(from: newItem)
            }
        }
        .onChange(of: linkText) { oldValue, newValue in
            guard !isParsingLink,
                  AddShowLinkPasteDetection.shouldAutoParse(previous: oldValue, current: newValue) else { return }
            startParsingLink()
        }
        .onChange(of: draft) { _, _ in
            saveFailure = nil
        }
        .onChange(of: [draft.date, draft.startTime, draft.endDate, draft.endTime]) { _, _ in
            refreshLifecycleQuestion()
        }
        .onAppear {
            refreshFreeCapacity()
            refreshLifecycleQuestion()
        }
        .onDisappear {
            // 页面离开时作废进行中的导入，避免任务在 dismiss 后继续写状态
            abandonInFlightImport()
            guard !didSave else { return }
            if hasUnsavedInput {
                ProductAnalytics.capture(.addShowAbandoned(
                    method: sheet.rawValue,
                    blocker: saveBarStatus?.analyticsValue ?? (shouldShowDraftFields ? "none" : "link_entry")
                ))
            }
            coverLifecycle.cancel()
        }
        .sheet(isPresented: $showsPaywall, onDismiss: refreshFreeCapacity) {
            ProPaywallSheetView()
        }
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

    private var hasUnsavedInput: Bool {
        hasImportedDraft
            || !userEditedFields.isEmpty
            || !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var saveBarStatus: AddShowSaveBarStatus? {
        AddShowSaveBarStatus.resolve(.init(
            isParsingLink: isParsingLink,
            isRecognizingScreenshot: isRecognizingScreenshot,
            nameIsEmpty: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            needsDateConfirmation: needsDateConfirmation,
            hasStartTime: draft.startTime != nil,
            hasValidEndTime: draft.startTime == nil || draft.hasValidEndTime(),
            needsLifecycleChoice: lifecycleQuestion != nil && lifecycleChoice == nil,
            isAtFreeCapacity: isAtFreeCapacity,
            failure: saveFailure
        ))
    }

    @ViewBuilder
    private var methodContent: some View {
        if !shouldShowDraftFields {
            if isRecognizingScreenshot {
                screenshotContent
            } else {
                if !hasImportedDraft {
                    AddShowLinkEntryView(
                        linkText: $linkText,
                        isParsingLink: isParsingLink,
                        failure: linkFailure,
                        onParse: startParsingLink,
                        onRetry: {
                            guard !isParsingLink else { return }
                            linkFailure = nil
                        },
                        onManual: switchToManual
                    )
                }
                HStack(spacing: BSSpacing.compact) {
                    PhotosPicker(selection: $selectedScreenshotItem, matching: .images) {
                        Label(BSLocalization.text("截图识别"), systemImage: "photo")
                    }
                    .buttonStyle(BSSecondaryButtonStyle())

                    Button {
                        switchToManual()
                    } label: {
                        Label(BSLocalization.text("手动填写"), systemImage: "square.and.pencil")
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
                .disabled(isImportingDraft)
            }
        }
    }

    private var screenshotContent: some View {
        EditShowFormCard(
            title: BSLocalization.text("识别进度"),
            icon: "text.viewfinder",
            tint: BSColor.Stage.foreground,
            pillText: "设备端 · 不上传",
            pillTint: BSColor.Stage.muted
        ) {
            AddShowOCRStepsView(activeStep: ocrActiveStep)
        }
    }

    private func switchToManual() {
        dismissKeyboard()
        draft.source = .manual
        if draft.startTime == nil {
            let calendar = draft.timingCalendar()
            draft.startTime = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: draft.date)
        }
        sheet = .manual
        importNote = nil
        linkFailure = nil
    }

    private var shouldShowDraftFields: Bool {
        sheet == .manual || hasImportedDraft
    }

    private func refreshLifecycleQuestion() {
        let question = AddShowLifecycleQuestion.resolve(for: draft)
        guard question != lifecycleQuestion else { return }
        lifecycleQuestion = question
        lifecycleChoice = nil
        if let question {
            lifecycleEndTime = question.defaultEnd()
        }
    }

    private func refreshFreeCapacity() {
        guard draft.creationOrigin == .user else {
            isAtFreeCapacity = false
            return
        }
        isAtFreeCapacity = !FreeShowCapacityCoordinator().canAddShow(
            from: shows,
            entitlement: ProEntitlementStorage.decode(entitlementRawValue)
        )
    }

    private func startParsingLink() {
        dismissKeyboard()
        beginImportTask {
            await parseLink()
        }
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
                try? await Task.sleep(for: .milliseconds(700))
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
                reportFailure(stage: "screenshot", reason: "image_unreadable")
                failScreenshotImport(BSLocalization.text("没有读到这张截图，请改用手动填写。"))
                return
            }

            let recognized = try await OnDeviceShowScreenshotRecognizer().draft(from: image)
            guard isActiveImportRequest(requestRevision) else { return }
            stepTask.cancel()
            // 第四步「生成可编辑草稿」短暂停留，完成状态可见后再切到确认表单
            ocrActiveStep = 4
            try? await Task.sleep(for: .milliseconds(450))
            guard isActiveImportRequest(requestRevision) else { return }

            // 用 merge 而非整段替换:用户已手改的字段（userEditedFields）保留原值,
            // 避免 OCR 偷偷冲掉用户输入。import 完成后清空,下一轮 import 重新开始。
            draft.mergeRespectingUserEdits(from: recognized, userEdited: userEditedFields)
            userEditedFields = []
            hasImportedDraft = true
            importRevision += 1
            fallbackDateConfirmed = false
            importNote = nil
            ProductAnalytics.capture(.screenshotRecognized)
        } catch is CancellationError {
            // 页面关闭或新请求取消：不写失败态
            return
        } catch {
            guard isActiveImportRequest(requestRevision) else { return }
            reportFailure(stage: "screenshot", error: error)
            failScreenshotImport(BSLocalization.text("没有识别到可用的现场信息，请改用手动填写。"))
        }
    }

    private func failScreenshotImport(_ note: String) {
        draft.source = .manual
        hasImportedDraft = false
        sheet = .link
        importNote = note
    }

    @MainActor
    private func parseLink() async {
        guard !isParsingLink else { return }
        dismissKeyboard()
        sheet = .link
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
            linkFailure = nil
            importRevision += 1
            fallbackDateConfirmed = false
            importNote = nil
            ProductAnalytics.capture(.showLinkParsed)
        } catch is CancellationError {
            return
        } catch {
            guard isActiveImportRequest(requestRevision) else { return }
            draft.source = .manual
            hasImportedDraft = false
            linkFailure = AddShowLinkFailurePresentation.resolve(error)
            reportFailure(stage: "link_parse", error: error)
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving, savedTitle == nil, !isImportingDraft, !needsDateConfirmation else { return }
        dismissKeyboard()
        saveFailure = nil

        refreshFreeCapacity()
        if isAtFreeCapacity {
            ProductAnalytics.capture(.proLimitReached)
            showsPaywall = true
            return
        }

        isSaving = true
        do {
            let show = try draft.makeShow()
            if let duplicate = ShowDuplicateMatcher.firstDuplicate(of: show, in: shows) {
                ProductAnalytics.capture(.duplicateShowBlocked(method: sheet.rawValue, existingShowID: duplicate.id))
                failSave(BSLocalization.text("这场已经在 BeforeShow 里了"))
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }

            switch AddShowLifecyclePolicy.resolution(for: show) {
            case .future:
                await persistPreparedShow(show, lifecycle: .future)
            case .ended:
                await persistPreparedShow(show, lifecycle: .ended)
            case .needsEndConfirmation:
                refreshLifecycleQuestion()
                guard lifecycleQuestion != nil else {
                    // 还不可能已经结束：只能是正在进行。
                    await persistPreparedShow(show, lifecycle: .live)
                    return
                }
                switch lifecycleChoice {
                case .live:
                    await persistPreparedShow(show, lifecycle: .live)
                case .ended:
                    show.markEnded(at: lifecycleEndTime)
                    await persistPreparedShow(show, lifecycle: .ended)
                case nil:
                    // 选项就在表单里，保存栏已说明还差这一步。
                    isSaving = false
                }
            }
        } catch {
            modelContext.rollback()
            reportFailure(stage: "validation", error: error)
            switch error as? ShowValidationError {
            case .invalidEndTime: failSave(BSLocalization.text("结束时间需要晚于开始时间。"))
            case .missingStartTime: failSave(BSLocalization.text("请确认开场时间。"))
            case .emptyName: failSave(BSLocalization.text("请填写现场名称。"))
            default: failSave(BSLocalization.text("请填写必填信息。"))
            }
        }
    }

    private func reportFailure(stage: String, error: Error) {
        reportFailure(stage: stage, reason: AddShowFailureReason.code(for: error))
    }

    private func reportFailure(stage: String, reason: String) {
        ProductAnalytics.capture(.addShowFailed(method: sheet.rawValue, stage: stage, reason: reason))
    }

    /// 写库失败不是用户填错了：如实说保存没成功、可以重试，并留下错误码便于排查。
    private func failPersist(_ error: Error) {
        let nsError = error as NSError
        reportFailure(stage: "persist", error: error)
        failSave(BSLocalization.format("没有保存成功，请再试一次（%@ %ld）", nsError.domain, nsError.code))
    }

    private func failSave(_ message: String) {
        saveFailure = message
        isSaving = false
    }

    @MainActor
    private func persistPreparedShow(
        _ show: Show,
        lifecycle: AddShowFinalLifecycle
    ) async {
        isSaving = true
        do {
            _ = try await AddShowPersistenceCoordinator.persist(
                show,
                lifecycle: lifecycle,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext,
                beforePostCommit: { outcome in
                    synchronizeFreeShowCapacity(
                        in: modelContext,
                        entitlement: ProEntitlementStorage.decode(entitlementRawValue)
                    )
                    ProductAnalytics.capture(.showAdded(
                        showID: show.id, method: sheet.rawValue, lifecycle: outcome.rawValue,
                        isFirstShow: !shows.contains { $0.id != show.id }, isFestival: ShowFlavor.inferred(from: show) == .festival
                    ))
                    didSave = true
                    coverLifecycle.finalize(keeping: draft.coverImageURL)

                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isSaving = false

                    // 保存即结束添加事务：按钮内告诉用户这场去了哪里，片刻后关闭。
                    // 已有当前现场时静默保留，用户可稍后在当前页切换。
                    savedTitle = AddShowSavedFeedback.title(
                        for: outcome,
                        showDate: show.date,
                        calendar: show.timingCalendar()
                    )
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(900))
                        onSaved?(show.id)
                    }
                }
            )
        } catch AddShowPersistenceError.duplicateShow {
            modelContext.rollback()
            failSave(BSLocalization.text("这场已经在 BeforeShow 里了"))
        } catch {
            modelContext.rollback()
            failPersist(error)
        }
    }
}
