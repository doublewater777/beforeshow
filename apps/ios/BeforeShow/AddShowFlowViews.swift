import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

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
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSheet: AddShowSheet?

    var body: some View {
        Group {
            if let selectedSheet {
                AddShowFlowView(
                    sheet: selectedSheet,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            self.selectedSheet = nil
                        }
                    }
                )
            } else {
                AddShowEntryView(
                    onCancel: {
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
    let onCancel: () -> Void
    let onSelect: (AddShowSheet) -> Void

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        onCancel()
                    } label: {
                        Text("取消")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, BSSpacing.md)

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
                            tint: BSColor.Accent.travel
                        ) {
                            onSelect(.link)
                        }

                        AddShowMethodCard(
                            title: "截图识别",
                            subtitle: "上传票务截图，识别出现场名称、时间、场馆等信息。",
                            iconName: "camera.fill",
                            tint: BSColor.Accent.video
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
                    .padding(.top, 68)
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
    private let onBack: (() -> Void)?

    @State private var draft: ShowDraft
    @State private var selectedScreenshotItem: PhotosPickerItem?
    @State private var screenshotText = ""
    @State private var linkText = ""
    @State private var message: String?
    @State private var isRecognizingScreenshot = false
    @State private var isParsingLink = false
    @State private var showsManualFallback = false
    @State private var showsProMembership = false
    @State private var showsProSaveLimit = false
    @State private var toast: BSToastPayload?

    init(
        sheet: AddShowSheet,
        linkParser: ShowLinkDraftParser = AddShowFlowView.defaultLinkParser(),
        onBack: (() -> Void)? = nil
    ) {
        self.sheet = sheet
        self.linkParser = linkParser
        self.onBack = onBack
        _draft = State(initialValue: ShowDraft(source: sheet.draftSource))
    }

    static func defaultLinkParser() -> ShowLinkDraftParser {
        let baseURL = URL(string: "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/parseShowLink")!
        let service = RemoteShowLinkParsingService(
            baseURL: baseURL,
            appInstanceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            appSignature: "beforeshow-app-signature-v1"
        )
        return ShowLinkDraftParser(service: service)
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
                        ShowDraftFormFields(draft: $draft)

                        VStack(spacing: BSSpacing.sm) {
                            Button {
                                save()
                            } label: {
                                Text(sheet.saveButtonTitle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AddShowPrimaryButtonStyle())
                            .disabled(!draft.isReadyToSave)

                            if sheet == .manual {
                                Text("可添加后再补充封面图和更多信息")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(BSColor.textTertiary.opacity(0.65))
                                    .frame(maxWidth: .infinity)
                            } else if hasRecognizedDraft {
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

            if showsManualFallback && sheet == .link && !hasRecognizedDraft {
                BSEmptyPanel(
                    iconName: "exclamationmark.triangle",
                    title: "链接解析失败",
                    message: "这个链接暂不支持。可以继续在下方手动填写现场信息。",
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
                            .foregroundColor(BSColor.Accent.video)
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

            if showsManualFallback && sheet == .screenshot && !hasRecognizedDraft {
                BSEmptyPanel(
                    iconName: "text.viewfinder",
                    title: "截图识别失败",
                    message: "没有识别到可用的现场日期。可以粘贴截图文字，或直接手动填写。",
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
        sheet == .manual || showsManualFallback || hasRecognizedDraft
    }

    private var hasRecognizedDraft: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func closeOrBack() {
        dismissKeyboard()
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private func recognizeScreenshot() {
        if let recognizedDraft = ShowScreenshotRecognitionService().draft(fromRecognizedText: screenshotText) {
            draft = recognizedDraft
            showsManualFallback = false
            message = nil
            presentToast(.success, message: "识别完成")
        } else {
            draft.source = .manual
            showsManualFallback = true
            message = "没有识别到可用的现场日期，请改用手动填写。"
            presentToast(.failure, message: "识别失败")
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
            showsManualFallback = false
            message = nil
            presentToast(.success, message: "识别完成")
        } catch {
            draft.source = .manual
            showsManualFallback = true
            message = "没有识别到可用的现场日期，请改用手动填写。"
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
            showsManualFallback = false
            message = nil
            presentToast(.success, message: "解析完成")
        } catch {
            draft.source = .manual
            showsManualFallback = true
            message = "这个链接暂不支持，请改用手动填写。"
            presentToast(.failure, message: "解析失败")
        }
    }

    private func save() {
        dismissKeyboard()
        do {
            let entitlement = ProEntitlementStorage.decode(entitlementRawValue)
            guard ProFeatureGate().canAddShow(savedShowCount: shows.count, entitlement: entitlement) else {
                message = "免费版可以保存 1 场现场。开通 Pro 后可以继续添加。"
                showsProSaveLimit = true
                presentToast(.neutral, message: "保存上限")
                return
            }

            let show = try draft.makeShow()
            modelContext.insert(show)

            if selections.isEmpty {
                let selection = CurrentShowSelection(selectedShowID: show.id)
                modelContext.insert(selection)
            }

            if notificationStates.isEmpty {
                modelContext.insert(NotificationSchedulingState(focusedShowID: show.id))
            }

            try modelContext.save()
            dismiss()
        } catch ShowValidationError.invalidEndTime {
            message = "结束时间需要晚于开始时间。"
            presentToast(.failure, message: "时间范围无效")
        } catch ShowValidationError.emptyName {
            message = "请填写现场名称。"
            presentToast(.failure, message: "保存失败")
        } catch {
            message = "请填写必填信息。"
            presentToast(.failure, message: "保存失败")
        }
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

private enum ShowCoverLocalImageStore {
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
}

struct ShowDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var draft: ShowDraft
    let saveTitle: String
    let onSave: (ShowDraft) -> Void
    @State private var message: String?

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    AddShowFlowHeader(
                        title: title,
                        subtitle: "修改后会立即更新这个现场。",
                        backTitle: "取消",
                        onBack: {
                            dismiss()
                        }
                    )

                    ShowDraftFormFields(draft: $draft, includesSeatSection: true)

                    Button {
                        guard draft.hasValidEndTime() else {
                            message = "结束时间需要晚于开始时间。"
                            return
                        }
                        dismissKeyboard()
                        onSave(draft)
                        dismiss()
                    } label: {
                        Text(saveTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AddShowPrimaryButtonStyle())
                    .disabled(!draft.isReadyToSave)

                    if let message {
                        Text(message)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Accent.fragment)
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
    }
}

private struct ShowDraftFormFields: View {
    @Binding var draft: ShowDraft
    let includesSeatSection: Bool
    @State private var startTime = Date()
    @State private var hasEndTime = false
    @State private var endDate = Date()
    @State private var endTime = Date()
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isImportingCover = false
    @State private var coverImportMessage: String?

    init(draft: Binding<ShowDraft>, includesSeatSection: Bool = false) {
        self._draft = draft
        self.includesSeatSection = includesSeatSection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            if !draft.coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AddShowFieldGroup(title: "封面") {
                    ShowCoverImageView(urlString: draft.coverImageURL, aspectRatio: 16.0 / 10.0, contentMode: .fill)
                }
            }

            if !draft.artistAvatarURLs.isEmpty {
                AddShowFieldGroup(title: "艺人头像") {
                    ArtistAvatarStackView(urls: draft.artistAvatarURLs, size: 42)
                }
            }

            AddShowFieldGroup(title: "确认现场") {
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

                AddShowScheduleFields(
                    draft: $draft,
                    startTime: $startTime,
                    hasEndTime: $hasEndTime,
                    endDate: $endDate,
                    endTime: $endTime
                )

                AddShowLabeledTextField(
                    title: "场馆",
                    placeholder: "上海体育场",
                    text: $draft.venueName
                )

                BSAddressSuggestionField(
                    label: "场馆地址",
                    placeholder: "街道门牌，查路线时会用到",
                    text: $draft.venueAddress,
                    city: draft.city,
                    seedKeyword: draft.venueName,
                    helperText: "下面有小地图，点一下就能选准地址。"
                )

                AddShowLabeledTextField(
                    title: "城市",
                    placeholder: "上海",
                    text: $draft.city
                )

                AddShowLabeledTextField(
                    title: "艺人 / 阵容",
                    placeholder: "五月天",
                    text: $draft.artist
                )

                AddShowLabeledTextField(
                    title: "封面图链接",
                    placeholder: "https://...",
                    text: $draft.coverImageURL,
                    keyboardType: .URL
                )

                AddShowCoverImportField(
                    selectedItem: $selectedCoverItem,
                    isImporting: isImportingCover,
                    message: coverImportMessage
                )

                if includesSeatSection {
                    AddShowLabeledTextField(
                        title: "座位或区域",
                        placeholder: "看台 / 内场 / 排号",
                        text: $draft.seatSection
                    )
                }
            }
        }
        .onAppear(perform: syncFromDraft)
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
            draft.startTime = mergedStartTime()
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

    private func syncFromDraft() {
        startTime = draft.startTime
        draft.startTime = mergedStartTime()
        if let draftEndDate = draft.endDate {
            endDate = draftEndDate
        } else {
            endDate = draft.date
        }
        if let draftEndTime = draft.endTime {
            hasEndTime = true
            endTime = draftEndTime
        } else {
            endTime = fallbackEndTimePickerValue()
            draft.endTime = nil
        }
        if draft.type == .musicFestival {
            draft.endDate = endDate
            draft.endTime = hasEndTime ? mergedTime(on: endDate, time: endTime) : nil
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

    private func defaultStartTime() -> Date {
        Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: draft.date) ?? draft.date
    }

    private func fallbackEndTimePickerValue() -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 55, second: 0, of: draft.date) ?? draft.date
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
            draft.coverImageURL = fileURL.absoluteString
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
            Button {
                onBack()
            } label: {
                Text(backTitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, BSSpacing.md)

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
                        startTime: $startTime
                    )
                }
            }

            AddShowStartTimeField(
                title: "每日开场时间",
                startTime: $startTime
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
                .tint(BSColor.Accent.video)
                .frame(maxWidth: .infinity, alignment: .leading)
                .addShowInputChrome()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AddShowStartTimeField: View {
    let title: String
    @Binding var startTime: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddShowFieldLabel(title: title, isRequired: true)
            DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(BSColor.Accent.video)
                .frame(maxWidth: .infinity, alignment: .leading)
                .addShowInputChrome()
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
                Toggle("", isOn: $hasEndTime)
                    .labelsHidden()
                    .tint(BSColor.Accent.video)
                    .scaleEffect(0.76)
                    .frame(width: 40)
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
                            .tint(BSColor.Accent.video)
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
                            .fill(BSColor.Accent.video.opacity(0.16))
                        if isImporting {
                            ProgressView()
                                .tint(BSColor.Accent.video)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(BSColor.Accent.video)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selection == type ? BSColor.textPrimary : BSColor.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(selection == type ? Color.white.opacity(0.11) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selection == type ? Color.white.opacity(0.20) : BSColor.borderProminent, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
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
