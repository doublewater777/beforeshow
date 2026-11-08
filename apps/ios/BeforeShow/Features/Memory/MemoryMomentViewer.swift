import SwiftData
import SwiftUI

/// 记忆碎片大图/全屏查看器：
/// 左右滑下一格，下滑关闭；底部原位修改说明；「…」里删除，删后回胶卷给撤销 toast，不弹 alert。
struct MemoryMomentViewer: View {
    let show: Show
    let startID: UUID
    var onDelete: ((MemoryMoment) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [MemoryFragment]

    @State private var selection: UUID?
    @State private var isChromeVisible = true
    @State private var captionDraft = ""
    @State private var toast: BSToastPayload?

    init(show: Show, startID: UUID, onDelete: ((MemoryMoment) -> Void)? = nil) {
        self.show = show
        self.startID = startID
        self.onDelete = onDelete
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
                    page(moment)
                        .tag(Optional(moment.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if isChromeVisible, let current {
                chrome(current)
                    .transition(.opacity)
            }
        }
        .bsToastOverlay(toast, bottomPadding: 120)
        .animation(.easeOut(duration: 0.2), value: isChromeVisible)
        .preferredColorScheme(.dark)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height > 80 && abs(value.translation.width) < 60 {
                        commitCaption()
                        dismiss()
                    }
                }
        )
        .onAppear {
            if selection == nil { selection = startID }
            loadCaptionForSelection()
        }
        .onChange(of: selection) { _, _ in
            commitCaption()
            loadCaptionForSelection()
        }
        .onChange(of: moments.map(\.id)) { old, ids in
            guard !ids.isEmpty else { return dismiss() }
            guard let selection, !ids.contains(selection) else { return }
            let index = old.firstIndex(of: selection) ?? 0
            self.selection = ids[min(index, ids.count - 1)]
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
            topBar(moment)

            Spacer()

            bottomControls(moment)
        }
    }

    private func topBar(_ moment: MemoryMoment) -> some View {
        HStack {
            circleButton("xmark", label: BSLocalization.text("关闭")) {
                commitCaption()
                dismiss()
            }

            Spacer()

            Text(stamp(moment))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            moreMenu(moment)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func moreMenu(_ moment: MemoryMoment) -> some View {
        Menu {
            if let item = moment.item, item.kind == .video {
                Button {
                    save(item)
                } label: {
                    Label(BSLocalization.text("保存到相册"), systemImage: "square.and.arrow.down")
                }
            }

            Button(role: .destructive) {
                commitCaption()
                onDelete?(moment)
                dismiss()
            } label: {
                Label(BSLocalization.text("删除这条记忆"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(BSLocalization.text("更多选项"))
    }

    private func bottomControls(_ moment: MemoryMoment) -> some View {
        VStack(spacing: 8) {
            HStack {
                TextField(BSLocalization.text("写一句说明…"), text: $captionDraft)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .submitLabel(.done)
                    .onSubmit(commitCaption)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 0.5))
            .padding(.horizontal, 16)

            Text(BSLocalization.text("左右滑看下一格 · 下滑关闭"))
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.bottom, 8)
        }
        .padding(.bottom, 12)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
                .ignoresSafeArea()
                .allowsHitTesting(false)
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
        return "\(phase.rollTitle) · \(BSDateFormat.clock(moment.date, timeZone: .current))"
    }

    private func loadCaptionForSelection() {
        guard let current else { return }
        captionDraft = current.caption ?? (current.isText ? (current.fragment.text ?? "") : "")
    }

    private func commitCaption() {
        guard let current else { return }
        let text = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isText {
            guard !text.isEmpty else { return }
        }
        try? MemoryMomentEditing.setCaption(text, on: current, in: modelContext)
    }

    private func save(_ item: MemoryMediaItem) {
        Task { @MainActor in
            do {
                try await BSPhotoLibrarySaver.saveFile(MemoryMediaLocation.applicationSupport().url(for: item.relativePath), as: .video)
                show(toast: .success, BSLocalization.text("已保存到相册"))
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
