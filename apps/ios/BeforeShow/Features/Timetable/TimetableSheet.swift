import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct TimetableSheet: View {
    let showID: UUID
    let showName: String
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Query private var shows: [Show]
    @Query private var timetableAssets: [ShowAsset]

    private enum PhotoPickerIntent {
        case smartRecognition
        case saveOriginalOnly
        case addOrReplaceOriginal
    }

    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var coordinator = TimetableManagementCoordinator()
    @State private var quota = TimetableRecognitionQuota()
    @State private var isProPaywallPresented = false
    @State private var isChromeVisible = true
    @State private var photoPickerIntent: PhotoPickerIntent = .saveOriginalOnly

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingImagesData: [Data] = []
    @State private var isPhotosPickerPresented = false
    @State private var isAIImporting = false
    @State private var isConfirmingDelete = false
    @State private var isManagingDays = false
    @State private var isOriginalVisible = false
    @State private var isFullScreenImagePresented = false
    @State private var originalImagePage = 0
    @State private var addPerformanceTrigger = 0
    @State private var loadedAssetImages: [UIImage] = []
    @State private var isLoadingSavedImages = true
    @State private var isProcessingPhotos = false
    @State private var recognitionTask: Task<Void, Never>?
    @State private var photoImportError: String?
    @State private var pendingImages: [UIImage] = []
    @State private var selectedDayID: UUID?
    @State private var avatars: TimetableArtistAvatarStore
    @State private var artistLinker: TimetableArtistLinker
    @State private var orientation = TimetableOrientationController()

    init(
        showID: UUID,
        showName: String,
        onDetailVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.showID = showID
        self.showName = showName
        self.onDetailVisibilityChange = onDetailVisibilityChange
        let artistSearch = AppleMusicArtistSearchService()
        _avatars = State(initialValue: TimetableArtistAvatarStore(search: artistSearch))
        _artistLinker = State(initialValue: TimetableArtistLinker(search: artistSearch))
        _shows = Query(filter: #Predicate<Show> { $0.id == showID })
        let kindRaw = ShowAssetKind.timetable.rawValue
        _timetableAssets = Query(filter: #Predicate<ShowAsset> {
            $0.showID == showID && $0.kindRawValue == kindRaw
        })
    }

    private var isPro: Bool {
        ProEntitlementStorage.decode(entitlementRawValue).isProActive
    }

    private var currentShow: Show? { shows.first }
    private var hasStructuredTimetable: Bool { currentShow?.timetable != nil }
    private var hasSavedImages: Bool { !timetableAssets.isEmpty }
    /// Freshly picked images take precedence while they are being reviewed.
    private var originalImages: [UIImage] { pendingImages.isEmpty ? loadedAssetImages : pendingImages }

    private var avatarArtistNames: [String] {
        let timetable = coordinator.importSession?.timetable ?? currentShow?.timetable
        return timetable?.orderedDays.flatMap(\.performances).filter { $0.appleMusicArtistID == nil }.map(\.artistName) ?? []
    }

    private var isReviewing: Bool { coordinator.importSession != nil }

    private var showsTimetable: Bool {
        !coordinator.isRecognizing && (hasStructuredTimetable || hasSavedImages || isReviewing)
    }

    private var navigationTitle: String {
        if isAIImporting { return BSLocalization.text("导入时刻表") }
        if coordinator.isRecognizing { return BSLocalization.text("正在智能识别…") }
        if let session = coordinator.importSession {
            return session.timetable.days.count > 1 ? "" : BSLocalization.text("核对时刻表")
        }
        return showsTimetable && (currentShow?.timetable?.days.count ?? 0) > 1 ? "" : BSLocalization.text("时刻表")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TimetableStyle.background.ignoresSafeArea()

                if coordinator.isRecognizing {
                    TimetableRecognizingView(
                        image: pendingImages.first ?? loadedAssetImages.first,
                        imageCount: max(1, pendingImages.count > 0 ? pendingImages.count : loadedAssetImages.count),
                        onCancel: cancelRecognition
                    )
                } else if isAIImporting {
                    TimetableAIImportView(onImport: importText)
                } else if let session = coordinator.importSession {
                    TimetableImportReviewView(
                        session: session,
                        coordinator: coordinator,
                        linker: artistLinker,
                        avatarURL: avatarURL(for:),
                        onOpenOriginal: originalImages.isEmpty ? nil : { openOriginalImageViewer() },
                        hasExistingTimetable: currentShow?.timetable != nil,
                        onCancel: cancelReview,
                        onSave: saveReview
                    )
                } else if let timetable = currentShow?.timetable {
                    TimetableExperienceView(
                        timetable: timetable,
                        show: currentShow,
                        selectedDayID: dayBinding(for: timetable),
                        linker: artistLinker,
                        addPerformanceRequest: addPerformanceTrigger,
                        avatarURL: avatarURL(for:),
                        onManage: openManagement
                    )
                } else if hasSavedImages {
                    TimetableSavedImagesView(
                        images: loadedAssetImages,
                        currentIndex: $originalImagePage,
                        isLoading: isLoadingSavedImages,
                        onRetry: { Task { await loadSavedImages() } },
                        onRecognizePoster: triggerSmartRecognitionFromSaved,
                        onAddPhotos: {
                            photoPickerIntent = .addOrReplaceOriginal
                            isPhotosPickerPresented = true
                        },
                        isChromeVisible: $isChromeVisible
                    )
                } else {
                    TimetableEmptyStateView(
                        errorMessage: coordinator.recognitionError ?? photoImportError,
                        quotaBadge: quota.badgeText(isPro: isPro),
                        hasPendingImages: !pendingImagesData.isEmpty,
                        onSmartRecognition: {
                            guard quota.canRecognize(isPro: isPro) else {
                                isProPaywallPresented = true
                                return
                            }
                            photoPickerIntent = .smartRecognition
                            isPhotosPickerPresented = true
                        },
                        onManualImport: openAIImport,
                        onSaveOriginalPhotos: {
                            photoPickerIntent = .saveOriginalOnly
                            isPhotosPickerPresented = true
                        },
                        onSavePendingAsOriginal: {
                            Task {
                                guard let show = currentShow, !pendingImagesData.isEmpty else { return }
                                _ = await coordinator.saveOriginalImages(imagesData: pendingImagesData, show: show, modelContext: modelContext)
                                pendingImagesData = []
                                pendingImages = []
                                coordinator.recognitionError = nil
                                photoImportError = nil
                                await loadSavedImages()
                            }
                        },
                        onDismissError: {
                            coordinator.recognitionError = nil
                            photoImportError = nil
                        }
                    )
                }

                if isOriginalVisible && !originalImages.isEmpty {
                    TimetableOriginalImagePiP(
                        images: originalImages,
                        page: $originalImagePage,
                        onExpandFullScreen: {
                            openOriginalImageViewer(page: originalImagePage)
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isOriginalVisible = false }
                        }
                    )
                }

                if isProcessingPhotos && !coordinator.isRecognizing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(TimetableStyle.foreground)
                        Text(BSLocalization.text(coordinator.isSaving ? "保存中…" : "正在读取图片…"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TimetableStyle.foreground)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(isChromeVisible ? .visible : .hidden, for: .navigationBar)
            .bsClearNavigationContainer()
            .toolbar {
                if isAIImporting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isAIImporting = false
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(BSColor.textSecondary)
                        }
                        .accessibilityLabel(BSLocalization.text("返回"))
                    }
                } else if !isReviewing {
                    BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("关闭")) {
                        dismiss()
                    }
                    if showsTimetable, let timetable = currentShow?.timetable, timetable.days.count > 1 {
                        ToolbarItem(placement: .principal) {
                            TimetableDaySwitcher(
                                items: TimetableDayItems.make(timetable.orderedDays, timeZone: timeZone(of: timetable)),
                                selection: dayBinding(for: timetable)
                            )
                        }
                    }
                    if hasStructuredTimetable || hasSavedImages {
                        ToolbarItem(placement: .topBarTrailing) {
                            managementMenu
                        }
                    }
                }
            }
            .disabled(isProcessingPhotos || coordinator.isSaving)
            .navigationDestination(isPresented: $isManagingDays) {
                if let timetable = currentShow?.timetable {
                    TimetableManageView(timetable: timetable, selectedDayID: dayBinding(for: timetable), coordinator: coordinator)
                }
            }
        }
        .background {
            TimetableOrientationHost(controller: orientation, isEnabled: showsTimetable && !isPhotosPickerPresented && !isManagingDays && !isAIImporting)
        }
        .bsToastOverlay(coordinator.toast, bottomPadding: 36)
        .safeAreaInset(edge: .bottom) {
            if let photoImportError {
                HStack(spacing: BSSpacing.md) {
                    Label(photoImportError, systemImage: "exclamationmark.triangle")
                        .font(BSFont.caption)
                        .foregroundStyle(TimetableStyle.attention)
                    Spacer(minLength: 0)
                    Button {
                        isPhotosPickerPresented = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                    }
                    .accessibilityLabel(BSLocalization.text("更换图片"))
                    Button {
                        self.photoImportError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(BSLocalization.text("关闭"))
                }
                .foregroundStyle(TimetableStyle.foreground)
                .frame(minHeight: BSLayout.minTouchTarget)
                .padding(.horizontal, BSSpacing.lg)
                .padding(.vertical, BSSpacing.sm)
                .background(TimetableStyle.lane)
                .disabled(isProcessingPhotos)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(isProcessingPhotos || coordinator.isSaving || showsTimetable)
        .fullScreenCover(isPresented: $isFullScreenImagePresented) {
            TimetableOriginalImageViewer(
                images: originalImages,
                currentIndex: $originalImagePage,
                onDismiss: { isFullScreenImagePresented = false }
            )
        }
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .sheet(isPresented: $isProPaywallPresented) {
            ProPaywallView()
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                switch photoPickerIntent {
                case .smartRecognition:
                    await processPickedPhotosForRecognition(items)
                case .saveOriginalOnly, .addOrReplaceOriginal:
                    await processPickedPhotos(items)
                }
            }
        }
        .task {
            try? artistLinker.loadKnownArtists(in: modelContext)
            await loadSavedImages()
            if let timetable = currentShow?.timetable {
                await artistLinker.autoMatchPersistedPerformances(in: timetable, context: modelContext)
            }
        }
        .onAppear { orientation.setViewingEnabled(showsTimetable && !isPhotosPickerPresented && !isManagingDays) }
        .onDisappear {
            orientation.setViewingEnabled(false)
            TimetablePreviewPlayer.shared.stop()
        }
        .task(id: avatarArtistNames + artistLinker.avatarLineup.map { $0.name + ($0.avatarURL ?? "") }) {
            await avatars.load(artistNames: avatarArtistNames, lineup: artistLinker.avatarLineup + (currentShow?.artists ?? []))
        }
        .alert(
            BSLocalization.text("删除时刻表"),
            isPresented: $isConfirmingDelete
        ) {
            Button(BSLocalization.text("删除"), role: .destructive) {
                Task {
                    guard let show = currentShow else { return }
                    isOriginalVisible = false
                    isFullScreenImagePresented = false
                    await coordinator.deleteTimetable(show: show, modelContext: modelContext)
                    loadedAssetImages = []
                }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(BSLocalization.text("确认删除这场现场的时刻表数据与原图吗？"))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private func openManagement() {
        TimetablePreviewPlayer.shared.stop()
        isManagingDays = true
    }

    private func openOriginalImageViewer(page: Int = 0) {
        guard !originalImages.isEmpty else { return }
        originalImagePage = min(max(0, page), originalImages.count - 1)
        isFullScreenImagePresented = true
    }

    private var managementMenu: some View {
        Menu {
            if hasStructuredTimetable {
                if !originalImages.isEmpty {
                    Section {
                        Button {
                            openOriginalImageViewer()
                        } label: {
                            Label(BSLocalization.text("查看时刻表原图"), systemImage: "photo")
                        }
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isOriginalVisible.toggle()
                            }
                        } label: {
                            Label(
                                BSLocalization.text(isOriginalVisible ? "隐藏原图对照" : "画中画对照原图"),
                                systemImage: isOriginalVisible ? "pip.exit" : "pip"
                            )
                        }
                    }
                }

                Section {
                    Button {
                        addPerformanceTrigger += 1
                    } label: {
                        Label(BSLocalization.text("添加单场演出"), systemImage: "plus")
                    }
                    Button(action: openManagement) {
                        Label(BSLocalization.text("管理天数与舞台"), systemImage: "slider.horizontal.3")
                    }
                }

                Section {
                    if !originalImages.isEmpty {
                        Button(action: triggerSmartRecognitionFromSaved) {
                            Label(BSLocalization.text("重新智能识别此图"), systemImage: "sparkles")
                        }
                    }
                    Button(action: openAIImport) {
                        Label(BSLocalization.text("自行导入排期 (文本/JSON)"), systemImage: "doc.text")
                    }
                    Button {
                        photoPickerIntent = .addOrReplaceOriginal
                        isPhotosPickerPresented = true
                    } label: {
                        Label(BSLocalization.text(hasSavedImages ? "更换时刻表图片" : "添加时刻表图片"), systemImage: "photo.badge.plus")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label(BSLocalization.text("删除时刻表排期"), systemImage: "trash")
                    }
                }
            } else if hasSavedImages {
                Section {
                    Button {
                        openOriginalImageViewer()
                    } label: {
                        Label(BSLocalization.text("全屏查看图片"), systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }

                Section {
                    Button(action: triggerSmartRecognitionFromSaved) {
                        Label(BSLocalization.text("智能识别为排期"), systemImage: "sparkles")
                    }
                    Button(action: openAIImport) {
                        Label(BSLocalization.text("自行导入排期 (文本/JSON)"), systemImage: "doc.text")
                    }
                }

                Section {
                    Button {
                        photoPickerIntent = .addOrReplaceOriginal
                        isPhotosPickerPresented = true
                    } label: {
                        Label(BSLocalization.text("更换时刻表图片"), systemImage: "photo.badge.plus")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label(BSLocalization.text("删除已存图片"), systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(BSColor.textSecondary)
                .frame(minWidth: 32, minHeight: 32)
        }
        .accessibilityLabel(BSLocalization.text("更多"))
    }

    private func timeZone(of timetable: Timetable) -> TimeZone {
        TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
    }

    /// Defaults to the day that is playing now, then the next one, then the first.
    private func dayBinding(for timetable: Timetable) -> Binding<UUID> {
        Binding(
            get: {
                let days = timetable.orderedDays
                if let selectedDayID, days.contains(where: { $0.id == selectedDayID }) { return selectedDayID }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--timetable-day-2"), days.count > 1 { return days[1].id }
                #endif
                let now = Date()
                let current = days.first { day in
                    let end = day.performances.map(\.endsAt).max() ?? day.date
                    return now < end
                }
                return (current ?? days.first)?.id ?? UUID()
            },
            set: { selectedDayID = $0 }
        )
    }

    // MARK: - Import review

    private func openAIImport() {
        TimetablePreviewPlayer.shared.stop()
        isOriginalVisible = false
        isAIImporting = true
    }

    private func importText(_ text: String) throws {
        guard let show = currentShow else { return }
        let session = try coordinator.reviewImportedText(text, show: show, linker: artistLinker)
        isOriginalVisible = false
        isAIImporting = false
        matchArtists(in: session)
    }

    private func matchArtists(in session: TimetableImportSession) {
        Task {
            await artistLinker.autoMatchPersistedPerformances(in: session.timetable, context: session.context)
        }
    }

    private func cancelReview() {
        TimetablePreviewPlayer.shared.stop()
        coordinator.cancelReview()
        pendingImagesData = []
        pendingImages = []
        isOriginalVisible = false
    }

    private func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        coordinator.isRecognizing = false
        coordinator.recognitionError = nil
        pendingImages = []
        pendingImagesData = []
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func saveReview() {
        guard let show = currentShow else { return }
        TimetablePreviewPlayer.shared.stop()
        Task {
            guard await coordinator.saveReview(show: show, modelContext: modelContext) else { return }
            pendingImagesData = []
            pendingImages = []
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await loadSavedImages()
        }
    }

    private func avatarURL(for performance: TimetablePerformance) -> URL? {
        if performance.appleMusicArtistID != nil {
            return ArtistAvatarResolver.shared.displayURL(for: performance)
        }
        return avatars.url(for: performance.artistName)
    }

    private func processPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !isProcessingPhotos else { return }
        isProcessingPhotos = true
        photoImportError = nil
        defer { isProcessingPhotos = false }
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               UIImage(data: data) != nil {
                datas.append(data)
            }
        }
        selectedPhotoItems = []
        guard datas.count == items.count else {
            photoImportError = BSLocalization.text("图片读取失败，请重试")
            return
        }
        guard let show = currentShow else { return }
        let saved = await coordinator.saveOriginalImages(imagesData: datas, show: show, modelContext: modelContext)
        if saved {
            originalImagePage = 0
            await loadSavedImages()
        } else {
            photoImportError = BSLocalization.text("图片保存失败，请重试")
        }
    }

    private func loadSavedImages() async {
        isLoadingSavedImages = true
        defer { isLoadingSavedImages = false }
        guard let show = currentShow else { return }
        var loaded: [UIImage] = []
        for asset in timetableAssets.sorted(by: { $0.createdAt < $1.createdAt }) {
            if let url = try? await ShowAssetMediaStore.shared.absoluteURL(
                for: asset.relativePath,
                showID: show.id,
                kind: .timetable
            ), let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        loadedAssetImages = loaded
        originalImagePage = min(originalImagePage, max(0, loaded.count - 1))
    }

    private func triggerSmartRecognitionFromSaved() {
        guard !loadedAssetImages.isEmpty else { return }
        guard quota.canRecognize(isPro: isPro) else {
            isProPaywallPresented = true
            return
        }
        Task {
            var datas: [Data] = []
            for asset in timetableAssets.sorted(by: { $0.createdAt < $1.createdAt }) {
                if let show = currentShow,
                   let url = try? await ShowAssetMediaStore.shared.absoluteURL(
                    for: asset.relativePath,
                    showID: show.id,
                    kind: .timetable
                ), let data = try? Data(contentsOf: url) {
                    datas.append(data)
                }
            }
            if datas.isEmpty {
                for img in loadedAssetImages {
                    if let d = img.jpegData(compressionQuality: 0.8) {
                        datas.append(d)
                    }
                }
            }
            await performSmartRecognition(images: loadedAssetImages, datas: datas)
        }
    }

    private func processPickedPhotosForRecognition(_ items: [PhotosPickerItem]) async {
        guard !isProcessingPhotos else { return }
        isProcessingPhotos = true
        photoImportError = nil
        defer { isProcessingPhotos = false }

        var images: [UIImage] = []
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
                datas.append(data)
            }
        }
        selectedPhotoItems = []
        guard !images.isEmpty else {
            photoImportError = BSLocalization.text("图片读取失败，请重试")
            return
        }
        await performSmartRecognition(images: images, datas: datas)
    }

    private func performSmartRecognition(images: [UIImage], datas: [Data]) async {
        guard let show = currentShow else { return }
        recognitionTask?.cancel()
        coordinator.isRecognizing = true
        coordinator.recognitionError = nil
        pendingImages = images
        pendingImagesData = datas

        recognitionTask = Task {
            do {
                let service = RemoteTimetableRecognitionService.production()
                let document = try await service.recognize(images: images)
                try Task.checkCancellation()
                let result = try TimetableImportMapper.result(
                    from: document,
                    defaultTimeZoneIdentifier: timeZoneIdentifier(for: show),
                    fallbackDate: show.date,
                    unnamedStage: { BSLocalization.format("舞台 %d", $0) }
                )
                try Task.checkCancellation()
                quota.consumeQuotaIfFree(isPro: isPro)
                coordinator.isRecognizing = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let session = coordinator.beginReview(
                    result,
                    imagesData: datas,
                    show: show,
                    linker: artistLinker
                )
                if let session {
                    matchArtists(in: session)
                }
            } catch is CancellationError {
                coordinator.isRecognizing = false
                coordinator.recognitionError = nil
            } catch let err as RemoteTimetableRecognitionError {
                guard !Task.isCancelled else { return }
                coordinator.isRecognizing = false
                coordinator.recognitionError = err.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } catch {
                guard !Task.isCancelled else { return }
                coordinator.isRecognizing = false
                coordinator.recognitionError = BSLocalization.text("识别时刻表失败，请稍后重试")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func timeZoneIdentifier(for show: Show) -> String {
        if let identifier = show.timeZoneIdentifier, TimeZone(identifier: identifier) != nil {
            return identifier
        }
        return "Asia/Shanghai"
    }
}
