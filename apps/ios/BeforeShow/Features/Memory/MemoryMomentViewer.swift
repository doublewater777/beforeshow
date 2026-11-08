import SwiftData
import SwiftUI

/// Every moment of the show, oldest first, one per page. Each page carries its time,
/// its line and the two things you can do to it: write the line, or delete it.
struct MemoryMomentViewer: View {
    let show: Show
    let startID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [MemoryFragment]
    @State private var selection: UUID?
    @State private var isChromeVisible = true
    @State private var editing: MemoryMoment?
    @State private var deleting: MemoryMoment?
    @State private var toast: BSToastPayload?

    init(show: Show, startID: UUID) {
        self.show = show
        self.startID = startID
        let showID = show.id
        _fragments = Query(filter: #Predicate<MemoryFragment> { $0.showID == showID })
    }

    private var moments: [MemoryMoment] { MemoryMomentTimeline.moments(from: fragments) }
    private var current: MemoryMoment? { moments.first { $0.id == selection } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(moments) { moment in
                    page(moment).tag(Optional(moment.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            if isChromeVisible, let current {
                chrome(current).transition(.opacity)
            }
        }
        .bsToastOverlay(toast, bottomPadding: 120)
        .animation(.easeOut(duration: 0.2), value: isChromeVisible)
        .preferredColorScheme(.dark)
        .onAppear { if selection == nil { selection = startID } }
        .onChange(of: moments.map(\.id)) { old, ids in
            guard !ids.isEmpty else { return dismiss() }
            guard let selection, !ids.contains(selection) else { return }
            let index = old.firstIndex(of: selection) ?? 0
            self.selection = ids[min(index, ids.count - 1)]
        }
        .sheet(item: $editing) { moment in
            MemoryLineSheet(
                title: moment.caption == nil ? BSLocalization.text("加一句") : BSLocalization.text("改一句"),
                initialText: moment.caption ?? "",
                allowsEmpty: !moment.isText
            ) { text in
                try MemoryMomentEditing.setCaption(text, on: moment, in: modelContext)
            }
        }
        .alert(DangerConfirmation.deleteMemory.title, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { moment in
            Button(DangerConfirmation.deleteMemory.confirmTitle, role: .destructive) { delete(moment) }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: { _ in
            Text(DangerConfirmation.deleteMemory.message)
        }
    }

    @ViewBuilder
    private func page(_ moment: MemoryMoment) -> some View {
        let location = MemoryMediaLocation.applicationSupport()
        if let item = moment.item, item.kind == .video {
            MemoryViewerVideoPage(url: location.url(for: item.relativePath), isActive: selection == moment.id)
        } else if let item = moment.item {
            BSZoomableImagePage(source: .file(location.url(for: item.relativePath)), onSingleTap: { isChromeVisible.toggle() })
                .bsMaskUserContent()
        } else {
            Text(moment.fragment.text ?? "")
                .font(BSFont.Editorial.serif(26))
                .foregroundStyle(BSColor.Stage.foreground)
                .multilineTextAlignment(.leading)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { isChromeVisible.toggle() }
        }
    }

    private func chrome(_ moment: MemoryMoment) -> some View {
        VStack(spacing: 0) {
            HStack {
                circleButton("xmark", label: BSLocalization.text("关闭")) { dismiss() }
                Spacer()
                Text(stamp(moment))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                if !moment.isText, let caption = moment.caption {
                    Text(caption)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                }
                HStack(spacing: 10) {
                    Button { editing = moment } label: {
                        Label(moment.caption == nil ? BSLocalization.text("加一句") : BSLocalization.text("改一句"), systemImage: "text.bubble")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if let item = moment.item, item.kind == .video {
                        circleButton("square.and.arrow.down", label: BSLocalization.text("保存到相册")) { save(item) }
                    }
                    circleButton("trash", label: BSLocalization.text("删除这条记忆")) { deleting = moment }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func stamp(_ moment: MemoryMoment) -> String {
        let phase = MemoryFragmentPhase.resolved(at: moment.date, timing: show.timingFields)
        return "\(BSDateFormat.clock(moment.date, timeZone: .current)) · \(phase.title)"
    }

    private func delete(_ moment: MemoryMoment) {
        deleting = nil
        Task { @MainActor in
            do {
                try await MemoryMomentEditing.delete(moment, in: modelContext)
            } catch {
                show(toast: .failure, BSLocalization.text("删除失败，请重试"))
            }
        }
    }

    private func save(_ item: MemoryMediaItem) {
        Task { @MainActor in
            do {
                try await BSPhotoLibrarySaver.saveFile(MemoryMediaLocation.applicationSupport().url(for: item.relativePath), as: .video)
                show(toast: .success, BSLocalization.text("已保存"))
            } catch {
                show(toast: .failure, BSLocalization.text("保存失败，请重试"))
            }
        }
    }

    private func show(toast tone: BSToastTone, _ message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }
}
