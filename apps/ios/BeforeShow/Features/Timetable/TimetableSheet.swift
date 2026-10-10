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

    @StateObject private var coordinator = TimetableManagementCoordinator()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingImagesData: [Data] = []
    @State private var isPhotosPickerPresented = false
    @State private var isConfirmingDelete = false
    @State private var isOriginalVisible = false
    @State private var isFullScreenImagePresented = false
    @State private var originalImagePage = 0
    @State private var addPerformanceTrigger = 0
    @State private var loadedAssetImages: [UIImage] = []
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

    private var currentShow: Show? { shows.first }
    private var hasStructuredTimetable: Bool { currentShow?.timetable != nil }
    private var hasSavedImages: Bool { !timetableAssets.isEmpty }
    /// Freshly picked images take precedence while they are being reviewed.
    private var originalImages: [UIImage] { pendingImages.isEmpty ? loadedAssetImages : pendingImages }

    private var avatarArtistNames: [String] {
        currentShow?.timetable?.orderedDays.flatMap(\.performances).filter { $0.appleMusicArtistID == nil }.map(\.artistName) ?? []
    }

    private var showsTimetable: Bool {
        !coordinator.isRecognizing && hasStructuredTimetable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TimetableStyle.background.ignoresSafeArea()

                if coordinator.isRecognizing {
                    TimetableRecognizingView(image: originalImages.first, imageCount: originalImages.count)
                } else if let timetable = currentShow?.timetable {
                    TimetableExperienceView(
                        timetable: timetable,
                        show: currentShow,
                        selectedDayID: dayBinding(for: timetable),
                        linker: artistLinker,
                        addPerformanceRequest: addPerformanceTrigger,
                        avatarURL: avatarURL(for:)
                    )
                } else if hasSavedImages {
                    legacyImagesContent
                } else {
                    TimetableEmptyStateView(errorMessage: coordinator.recognitionError) {
                        isPhotosPickerPresented = true
                    }
                }

                if isOriginalVisible && !originalImages.isEmpty && !coordinator.isRecognizing {
                    TimetableOriginalImagePiP(
                        images: originalImages,
                        page: $originalImagePage,
                        onExpandFullScreen: {
                            isFullScreenImagePresented = true
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isOriginalVisible = false }
                        }
                    )
                }

                if isFullScreenImagePresented && !originalImages.isEmpty {
                    TimetableOriginalImageViewer(
                        images: originalImages,
                        currentIndex: $originalImagePage,
                        onDismiss: { isFullScreenImagePresented = false }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(100)
                }
            }
            .navigationTitle(showsTimetable && (currentShow?.timetable?.days.count ?? 0) > 1 ? "" : BSLocalization.text("时刻表"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .bsClearNavigationContainer()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(BSColor.textSecondary)
                    }
                    .accessibilityLabel(BSLocalization.text("关闭"))
                }
                if showsTimetable, let timetable = currentShow?.timetable, timetable.days.count > 1 {
                    ToolbarItem(placement: .principal) {
                        TimetableDaySwitcher(
                            items: TimetableDayItems.make(timetable.orderedDays, timeZone: timeZone(of: timetable)),
                            selection: dayBinding(for: timetable)
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !coordinator.isRecognizing && (hasStructuredTimetable || hasSavedImages) {
                        managementMenu
                    }
                }
            }
        }
        .background {
            TimetableOrientationHost(controller: orientation, isEnabled: showsTimetable && !isPhotosPickerPresented)
        }
        .bsToastOverlay(coordinator.toast, bottomPadding: 36)
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await processPickedPhotos(items)
            }
        }
        .task {
            try? artistLinker.loadKnownArtists(in: modelContext)
            await loadSavedImages()
            if let timetable = currentShow?.timetable {
                await artistLinker.autoMatchPersistedPerformances(in: timetable, context: modelContext)
            }
        }
        .onAppear { orientation.setViewingEnabled(showsTimetable && !isPhotosPickerPresented) }
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
                }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(BSLocalization.text("确认删除这场现场的时刻表数据与原图吗？"))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var managementMenu: some View {
        Menu {
            Button {
                addPerformanceTrigger += 1
            } label: {
                Label(BSLocalization.text("添加演出"), systemImage: "plus")
            }
            if !loadedAssetImages.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isOriginalVisible.toggle()
                    }
                } label: {
                    Label(
                        BSLocalization.text(isOriginalVisible ? "隐藏原图对照" : "查看原图对照"),
                        systemImage: "pip"
                    )
                }
            }
            Button {
                isPhotosPickerPresented = true
            } label: {
                Label(BSLocalization.text("重新导入"), systemImage: "arrow.clockwise")
            }
            Divider()
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label(BSLocalization.text("删除时刻表"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(BSColor.textSecondary)
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

    private func importingDraft(_ draft: TimetableDraft) -> TimetableDraft {
        var draft = draft
        artistLinker.reuseKnownArtists(in: &draft)
        return draft
    }

    private func avatarURL(for performance: TimetablePerformance) -> URL? {
        if performance.appleMusicArtistID != nil {
            return performance.artistAvatarURL.flatMap(URL.init(string:))
        }
        return avatars.url(for: performance.artistName)
    }

    private var legacyImagesContent: some View {
        VStack(spacing: BSSpacing.lg) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(loadedAssetImages, id: \.self) { img in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 300)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
                .padding(.horizontal, BSSpacing.lg)
            }

            if let error = coordinator.recognitionError {
                errorNotice(message: error)
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        guard let show = currentShow else { return }
                        await coordinator.recognizeFromExistingAssets(assets: timetableAssets, show: show)
                        if let d = coordinator.draft {
                            var imported = importingDraft(d)
                            await artistLinker.autoMatchArtists(in: &imported)
                            let success = await coordinator.commit(
                                draft: imported,
                                newImagesData: [],
                                show: show,
                                modelContext: modelContext
                            )
                            if success {
                                await loadSavedImages()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    isOriginalVisible = true
                                }
                            }
                        }
                    }
                } label: {
                    Label(BSLocalization.text("从图片识别时刻表"), systemImage: "sparkles")
                }
                .buttonStyle(BSPrimaryButtonStyle())

                HStack(spacing: 12) {
                    Button(BSLocalization.text("原图对照")) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isOriginalVisible = true }
                    }
                    .buttonStyle(BSSecondaryButtonStyle())

                    Button(BSLocalization.text("重新上传")) {
                        isPhotosPickerPresented = true
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, BSSpacing.lg)
        }
        .padding(.vertical, BSSpacing.lg)
    }

    private func errorNotice(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color.orange)
            Text(message)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, BSSpacing.lg)
    }

    private func processPickedPhotos(_ items: [PhotosPickerItem]) async {
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
        guard !images.isEmpty, let show = currentShow else { return }
        pendingImagesData = datas
        pendingImages = images
        await coordinator.recognize(images: images, show: show)
        if let d = coordinator.draft {
            var imported = importingDraft(d)
            await artistLinker.autoMatchArtists(in: &imported)
            let success = await coordinator.commit(
                draft: imported,
                newImagesData: datas,
                show: show,
                modelContext: modelContext
            )
            if success {
                pendingImagesData = []
                pendingImages = []
                await loadSavedImages()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isOriginalVisible = true
                }
            }
        } else {
            pendingImagesData = []
            pendingImages = []
        }
    }

    private func loadSavedImages() async {
        guard let show = currentShow else { return }
        var loaded: [UIImage] = []
        for asset in timetableAssets {
            if let url = try? await ShowAssetMediaStore.shared.absoluteURL(
                for: asset.relativePath,
                showID: show.id,
                kind: .timetable
            ), let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        loadedAssetImages = loaded
    }
}
