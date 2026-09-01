import AVKit
import SwiftUI
import UIKit

// MARK: - Timeline row

struct MemoryTimelineSection: View {
    let phase: MemoryFragmentPhase
    let fragments: [MemoryFragment]
    let onEdit: (MemoryFragment) -> Void
    let onDelete: (MemoryFragment) -> Void
    let onOpenMedia: (MemoryFragment, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(phase.title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(phaseTitleColor)
                Text(BSLocalization.format("%lld 条", fragments.count))
                    .font(.system(size: 9.5))
                    .foregroundColor(BSColor.Stage.dim)
                Rectangle()
                    .fill(BSColor.Stage.border)
                    .frame(height: 1)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            VStack(spacing: 17) {
                ForEach(fragments) { fragment in
                    MemoryTimelinePost(
                        fragment: fragment,
                        onEdit: { onEdit(fragment) },
                        onDelete: { onDelete(fragment) },
                        onOpenMedia: { onOpenMedia(fragment, $0) }
                    )
                    .id(fragment.id)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)
        }
    }

    private var phaseTitleColor: Color {
        switch phase {
        case .after: BSColor.Stage.accent
        case .live: Color(red: 1, green: 0.82, blue: 0.83)
        case .before: BSColor.Stage.muted
        }
    }
}

private struct MemoryTimelinePost: View {
    let fragment: MemoryFragment
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onOpenMedia: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Circle()
                    .fill(BSColor.Stage.surfaceRaised)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(BSColor.Stage.accent, lineWidth: 2))
                    .overlay(Circle().stroke(BSColor.Stage.background, lineWidth: 5).padding(-5))
                    .padding(.top, 5)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [BSColor.Stage.border, Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 31)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(MemoryFragmentRelativeTime.format(fragment.createdAt, now: context.date))
                    }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    Menu {
                        Button("编辑记忆", action: onEdit)
                        Button("删除这条记忆", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BSColor.Stage.dim)
                            .frame(width: 32, height: 28)
                    }
                    .accessibilityLabel("管理这条记忆")
                }

                if fragment.mediaItems.isEmpty {
                    textCard
                } else {
                    mediaCard
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(fragment.text ?? "")
                .font(.system(size: 14, design: .serif))
                .foregroundColor(Color(red: 0.90, green: 0.91, blue: 0.93))
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MemoryMediaCarousel(items: fragment.orderedMediaItems) { index, _ in
                onOpenMedia(index)
            }
            if let text = fragment.text, !text.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.90, green: 0.91, blue: 0.93))
                        .lineSpacing(5)
                }
                .padding(13)
            }
        }
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 17))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(BSColor.Stage.border, lineWidth: 1))
    }
}

private struct MemoryMediaCarousel: View {
    let items: [MemoryMediaItem]
    let onTap: (Int, MemoryMediaItem) -> Void
    @State private var selection = 0

    var body: some View {
        VStack(spacing: BSSpacing.sm) {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button { onTap(index, item) } label: {
                        ZStack {
                            MemoryThumbnail(relativePath: item.thumbnailRelativePath ?? item.relativePath)
                            if item.kind == .video {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 46))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 330)
            .onChange(of: items.map(\.id)) { _, _ in
                selection = min(selection, max(0, items.count - 1))
            }

            if items.count > 1 {
                HStack(spacing: 5) {
                    ForEach(items.indices, id: \.self) { index in
                        Circle()
                            .fill(index == selection ? BSColor.Stage.accent : Color.white.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct MemoryThumbnail: View {
    let relativePath: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ZStack {
                    BSColor.Stage.surface
                    Image(systemName: "photo")
                        .foregroundColor(BSColor.Stage.muted)
                }
            }
        }
        .task(id: relativePath) {
            let path = MemoryMediaLocation.applicationSupport().url(for: relativePath).path
            let loaded = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)
            }.value
            image = loaded
        }
    }
}
