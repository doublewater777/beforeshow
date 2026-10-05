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

    @Query private var shows: [Show]
    @Query private var timetableAssets: [ShowAsset]

    @StateObject private var coordinator = TimetableManagementCoordinator()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingImagesData: [Data] = []
    @State private var isPhotosPickerPresented = false
    @State private var isReviewPresented = false
    @State private var activeReviewDraft: TimetableDraft?
    @State private var isConfirmingDelete = false
    @State private var isViewerPresented = false
    @State private var loadedAssetImages: [UIImage] = []

    init(
        showID: UUID,
        showName: String,
        onDetailVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.showID = showID
        self.showName = showName
        self.onDetailVisibilityChange = onDetailVisibilityChange
        _shows = Query(filter: #Predicate<Show> { $0.id == showID })
        let kindRaw = ShowAssetKind.timetable.rawValue
        _timetableAssets = Query(filter: #Predicate<ShowAsset> {
            $0.showID == showID && $0.kindRawValue == kindRaw
        })
    }

    private var currentShow: Show? { shows.first }
    private var hasStructuredTimetable: Bool { currentShow?.timetable != nil }
    private var hasSavedImages: Bool { !timetableAssets.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if coordinator.isRecognizing {
                    recognizingState
                } else if let draft = activeReviewDraft {
                    TimetableReviewView(
                        draft: Binding(
                            get: { draft },
                            set: { activeReviewDraft = $0 }
                        ),
                        onSave: {
                            Task {
                                guard let show = currentShow else { return }
                                let success = await coordinator.commit(
                                    draft: draft,
                                    newImagesData: pendingImagesData,
                                    show: show,
                                    modelContext: modelContext
                                )
                                if success {
                                    activeReviewDraft = nil
                                    pendingImagesData = []
                                }
                            }
                        },
                        onCancel: {
                            activeReviewDraft = nil
                            pendingImagesData = []
                        }
                    )
                } else if hasStructuredTimetable, let timetable = currentShow?.timetable {
                    structuredTimetableContent(timetable: timetable)
                } else if hasSavedImages {
                    legacyImagesContent
                } else {
                    emptyUploadContent
                }
            }
            .navigationTitle(BSLocalization.text("时刻表"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if activeReviewDraft == nil {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(BSColor.textSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if activeReviewDraft == nil && (hasStructuredTimetable || hasSavedImages) {
                        Menu {
                            Button(BSLocalization.text("重新上传图片")) {
                                isPhotosPickerPresented = true
                            }
                            Button(BSLocalization.text("删除时刻表"), role: .destructive) {
                                isConfirmingDelete = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(BSColor.textSecondary)
                        }
                    }
                }
            }
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
            await loadSavedImages()
        }
        .alert(
            BSLocalization.text("删除时刻表"),
            isPresented: $isConfirmingDelete
        ) {
            Button(BSLocalization.text("删除"), role: .destructive) {
                Task {
                    guard let show = currentShow else { return }
                    await coordinator.deleteTimetable(show: show, modelContext: modelContext)
                }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(BSLocalization.text("确认删除这场现场的时刻表数据与原图吗？"))
        }
        .navigationDestination(isPresented: $isViewerPresented) {
            timetableImagesViewer
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var recognizingState: some View {
        VStack(spacing: BSSpacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)
            Text(BSLocalization.text("正在解析演出时刻表..."))
                .font(BSFont.headline)
                .foregroundColor(BSColor.textPrimary)
            Text(BSLocalization.text("仅在本机识别，支持单日/多日及多舞台"))
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyUploadContent: some View {
        VStack(spacing: BSSpacing.xl) {
            Spacer()
            BSStageSheetHeader(
                icon: "list.bullet.rectangle",
                title: BSLocalization.text("添加时刻表"),
                subtitle: BSLocalization.text("支持选择一张或多张时刻表图片，将自动识别演出时间与阵容。")
            )

            if let error = coordinator.recognitionError {
                errorNotice(message: error)
            }

            Button {
                isPhotosPickerPresented = true
            } label: {
                Label(BSLocalization.text("从相册选择时刻表"), systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .padding(.horizontal, BSSpacing.xl)

            Spacer()
        }
    }

    private var legacyImagesContent: some View {
        VStack(spacing: BSSpacing.lg) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(loadedAssetImages, id: \.self) { img in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 220, height: 300)
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
                            activeReviewDraft = d
                        }
                    }
                } label: {
                    Label(BSLocalization.text("从图片识别时刻表"), systemImage: "sparkles")
                }
                .buttonStyle(BSPrimaryButtonStyle())

                HStack(spacing: 12) {
                    Button(BSLocalization.text("查看原图")) {
                        isViewerPresented = true
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

    private func structuredTimetableContent(timetable: Timetable) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: BSSpacing.lg) {
                // Summary bar
                let draft = TimetableDraft(from: timetable)
                HStack(spacing: BSSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.summary.dateRangeDescription)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(BSColor.textPrimary)
                        Text(BSLocalization.format("%d 个舞台 • 共 %d 场演出", draft.summary.stageCount, draft.summary.performanceCount))
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }
                    Spacer()
                    Button {
                        activeReviewDraft = draft
                    } label: {
                        Label(BSLocalization.text("检查/修改"), systemImage: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(BSColor.Accent.warm)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(BSColor.Accent.warm.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(BSSpacing.md)
                .background(BSColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                if !loadedAssetImages.isEmpty {
                    HStack {
                        Button {
                            isViewerPresented = true
                        } label: {
                            Label(BSLocalization.format("查看原图 (%d 张)", loadedAssetImages.count), systemImage: "photo")
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textSecondary)
                        }
                        Spacer()
                    }
                }

                // Days & Stages preview
                ForEach(timetable.orderedDays, id: \.id) { day in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(formatDay(day.date))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(BSColor.Accent.prepare)

                        ForEach(day.orderedStages, id: \.id) { stage in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(stage.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(BSColor.Accent.warm)

                                ForEach(stage.orderedPerformances, id: \.id) { perf in
                                    HStack {
                                        Text(formatTimeRange(start: perf.startsAt, end: perf.endsAt))
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                            .foregroundColor(BSColor.textTertiary)
                                        Text(perf.artistName)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(BSColor.textPrimary)
                                        Spacer()
                                        if perf.isInterested {
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(Color.red)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    Divider().overlay(Color.white.opacity(0.06))
                                }
                            }
                            .padding(12)
                            .background(BSColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
            .padding(.horizontal, BSSpacing.lg)
            .padding(.vertical, BSSpacing.md)
        }
    }

    private var timetableImagesViewer: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {
                ForEach(loadedAssetImages, id: \.self) { img in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(BSLocalization.text("时刻表原图"))
        .navigationBarTitleDisplayMode(.inline)
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
        await coordinator.recognize(images: images, show: show)
        if let d = coordinator.draft {
            activeReviewDraft = d
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

    private func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}
