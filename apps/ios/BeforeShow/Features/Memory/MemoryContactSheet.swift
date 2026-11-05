import SwiftUI

/// Memory fragments as a strip of film, cut into chapters by when they were taken.
struct MemoryContactSheet: View {
    let fragments: [MemoryFragment]
    /// The part of the night we are in now; its empty frame is the one lit up.
    let currentPhase: MemoryFragmentPhase
    var fragmentLabel: (MemoryFragment, Int) -> String = { fragment, _ in
        BSLocalization.format("打开记忆碎片，%@", BSDateFormat.clock(fragment.createdAt, timeZone: .current))
    }
    let onOpen: (MemoryFragment) -> Void
    let onOpenList: () -> Void
    let onCreate: (MemoryCreateSourceOption) -> Void

    private static let frameSize = CGSize(width: 132, height: 168)

    /// Chapters in the order the night happened; each phase is marked once.
    private var chapters: [(phase: MemoryFragmentPhase, fragments: [MemoryFragment])] {
        [MemoryFragmentPhase.before, .live, .after].compactMap { phase in
            let items = fragments.filter { $0.phase == phase }
            return items.isEmpty ? nil : (phase, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(BSLocalization.text("记忆碎片"))
                    .font(BSFont.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                if !fragments.isEmpty {
                    Button(action: onOpenList) {
                        HStack(spacing: 3) {
                            Text(BSLocalization.format("%lld 条", fragments.count))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        }
                        .font(BSFont.V3.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .frame(minHeight: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.text("查看全部记忆碎片"))
                }
                createMenu {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.06), in: Circle())
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                }
                .accessibilityLabel(BSLocalization.text("添加记忆碎片"))
            }
            VStack(spacing: 8) {
                sprockets
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        if fragments.isEmpty {
                            ForEach([MemoryFragmentPhase.before, .live, .after], id: \.self, content: emptyFrame)
                        }
                        ForEach(chapters, id: \.phase) { chapter in
                            chapterMark(chapter.phase)
                            ForEach(chapter.fragments) { fragment in
                                Button { onOpen(fragment) } label: { frame(for: fragment) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(fragmentLabel(fragment, (fragments.firstIndex { $0.id == fragment.id } ?? 0) + 1))
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, BSSpacing.roomy)
                }
                .scrollTargetBehavior(.viewAligned)
                sprockets
            }
            .padding(.vertical, 10)
            .background(Color(white: 0.043))
            .padding(.horizontal, -BSSpacing.roomy)
        }
    }

    private func createMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            ForEach(MemoryCreateSourceOption.allCases, id: \.self) { option in
                Button(option.title, systemImage: option.iconName) { onCreate(option) }
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    /// A chapter label printed sideways on the film edge, like a frame number.
    private func chapterMark(_ phase: MemoryFragmentPhase) -> some View {
        Text(phase.title)
            .font(.system(size: 11, weight: .semibold).width(.condensed))
            .tracking(3)
            .foregroundStyle(phase == .live ? BSColor.Stage.accent : BSColor.Stage.muted)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: 18, height: Self.frameSize.height)
            .accessibilityHidden(true)
    }

    private func frame(for fragment: MemoryFragment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let media = fragment.orderedMediaItems.first {
                    Color.clear
                        .overlay { MemoryThumbnail(relativePath: media.thumbnailRelativePath ?? media.relativePath) }
                        .overlay {
                            if media.kind == .video {
                                Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(.white)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if let text = fragment.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                                Text(text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .bsMaskUserContent()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .padding(.top, 14)
                                    .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                            }
                        }
                } else {
                    Text("“\(fragment.text ?? "")”")
                        .font(.system(size: 14, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(BSColor.Stage.heroIvory.opacity(0.9))
                        .bsMaskUserContent()
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(12)
                        .background(Color(white: 0.09))
                }
            }
            .frame(width: Self.frameSize.width, height: Self.frameSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(Self.time(fragment.createdAt))
                .font(.system(size: 10, weight: .medium).width(.condensed).monospacedDigit())
                .foregroundStyle(BSColor.Stage.dim)
                .frame(width: Self.frameSize.width, alignment: .leading)
        }
    }

    /// One blank frame per part of the night; the one we are in now invites the first entry.
    private func emptyFrame(_ phase: MemoryFragmentPhase) -> some View {
        let isCurrent = phase == currentPhase
        return createMenu {
            VStack(spacing: 8) {
                Text(phase.title)
                    .font(.system(size: 11, weight: .semibold).width(.condensed))
                    .tracking(2)
                    .foregroundStyle(isCurrent ? BSColor.Stage.accent : BSColor.Stage.dim)
                if isCurrent {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
            .padding(12)
            .frame(width: Self.frameSize.width, height: Self.frameSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(isCurrent ? 0.22 : 0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .accessibilityLabel(BSLocalization.text("添加记忆碎片"))
    }

    /// Film sprocket holes.
    private var sprockets: some View {
        Canvas { canvas, size in
            var x: CGFloat = 0
            while x < size.width {
                canvas.fill(Path(roundedRect: CGRect(x: x, y: 0, width: 9, height: size.height), cornerRadius: 1.5),
                            with: .color(BSColor.Stage.heroIvory.opacity(0.16)))
                x += 16
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }

    private static func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(format: "%02d.%02d %02d:%02d", parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}
