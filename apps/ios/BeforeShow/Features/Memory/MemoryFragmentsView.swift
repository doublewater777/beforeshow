import SwiftData
import SwiftUI

/// The show's memories as one sheet: a contact sheet of the night plus the three ways to add.
struct MemoryFragmentsSheet: View {
    let show: Show
    var pendingCreate: MemoryCreateSourceOption? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MemoryFragmentsView(show: show, pendingCreate: pendingCreate)
                .toolbar {
                    BSChromeToolbarCloseButton(accessibilityLabel: "关闭") { dismiss() }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

private struct MemoryViewerStart: Identifiable {
    let id: UUID
}

/// Every photo, video and line of the night as small frames in the order they happened,
/// grouped 开场前 / 进行中 / 散场后, so the shape of the evening shows at a glance.
struct MemoryFragmentsView: View {
    let show: Show
    var pendingCreate: MemoryCreateSourceOption? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [MemoryFragment]
    @State private var captureSource: MemoryCreateSourceOption?
    @State private var didStartPendingCreate = false
    @State private var viewerStart: MemoryViewerStart?
    @State private var toast: BSToastPayload?

    init(show: Show, pendingCreate: MemoryCreateSourceOption? = nil) {
        self.show = show
        self.pendingCreate = pendingCreate
        let showID = show.id
        _fragments = Query(filter: #Predicate<MemoryFragment> { $0.showID == showID })
    }

    private var moments: [MemoryMoment] { MemoryMomentTimeline.moments(from: fragments) }

    var body: some View {
        let moments = moments
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if moments.isEmpty {
                        emptyState
                    } else {
                        MemoryEveningStrip(moments: moments)
                        ForEach(MemoryMomentTimeline.sections(moments, timing: show.timingFields)) { section in
                            MemoryMomentSectionView(section: section) { viewerStart = MemoryViewerStart(id: $0.id) }
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .onChange(of: moments.count) { old, new in
                if new > old { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .background(BSColor.Stage.background.ignoresSafeArea())
        .navigationTitle(BSLocalization.text("记忆碎片"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            MemoryCaptureBar { captureSource = $0 }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .bsToastOverlay(toast, bottomPadding: 90)
        .memoryCapture($captureSource, show: show) { saved in
            presentToast(saved ? .success : .failure, BSLocalization.text(saved ? "已收进这场" : "没有保存，请重试"))
        }
        .fullScreenCover(item: $viewerStart) { start in
            MemoryMomentViewer(show: show, startID: start.id)
        }
        .task {
            guard let pendingCreate, !didStartPendingCreate else { return }
            didStartPendingCreate = true
            captureSource = pendingCreate
        }
        .task(id: fragments.map(\.id)) { await reconcileFiles() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BSLocalization.text("还没有记忆"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(BSColor.Stage.foreground)
            Text(BSLocalization.text("拍一张、选几张，或者写一句。每一样都会按时间收进这场。"))
                .font(.system(size: 13))
                .foregroundStyle(BSColor.Stage.muted)
        }
        .padding(.top, 40)
    }

    private func presentToast(_ tone: BSToastTone, _ message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }

    /// Drops files no memory points at any more, e.g. after an interrupted save.
    private func reconcileFiles() async {
        await MemoryFragmentMediaStore.shared.acquireCommitGate()
        let showID = show.id
        let descriptor = FetchDescriptor<MemoryFragment>(predicate: #Predicate<MemoryFragment> { $0.showID == showID })
        if let current = try? modelContext.fetch(descriptor) {
            var valid: [UUID: Set<String>] = [:]
            for fragment in current {
                valid[fragment.id] = Set(fragment.mediaItems.flatMap { [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 } })
            }
            try? await MemoryFragmentMediaStore.shared.reconcileFragmentFiles(showID: showID, validFilesByFragmentID: valid)
        }
        await MemoryFragmentMediaStore.shared.releaseCommitGate()
    }
}
