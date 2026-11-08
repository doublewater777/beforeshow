import SwiftUI
import UIKit

/// The evening at a glance: what was kept, and when it piled up.
struct MemoryEveningStrip: View {
    let moments: [MemoryMoment]

    private var summary: String {
        let photos = moments.filter { $0.item?.kind == .photo }.count
        let videos = moments.filter { $0.item?.kind == .video }.count
        let lines = moments.filter(\.isText).count
        return [
            photos > 0 ? BSLocalization.format("%lld 张照片", photos) : nil,
            videos > 0 ? BSLocalization.format("%lld 段视频", videos) : nil,
            lines > 0 ? BSLocalization.format("%lld 句", lines) : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let counts = MemoryMomentTimeline.density(moments, buckets: 28)
        let peak = max(1, counts.max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            Text(summary)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                    Capsule()
                        .fill(count > 0 ? BSColor.Stage.accent : Color.white.opacity(0.1))
                        .frame(height: count > 0 ? 6 + 26 * CGFloat(count) / CGFloat(peak) : 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 32, alignment: .bottom)
            if let first = moments.first?.date, let last = moments.last?.date {
                HStack {
                    Text(BSDateFormat.clock(first, timeZone: .current))
                    Spacer()
                    Text(BSDateFormat.clock(last, timeZone: .current))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BSColor.Stage.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct MemoryMomentSectionView: View {
    let section: MemoryMomentSection
    let onOpen: (MemoryMoment) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(section.phase.title)
                    .font(BSFont.Editorial.caps(13))
                    .tracking(1.5)
                    .foregroundStyle(BSColor.Stage.foreground)
                Text("\(section.moments.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(BSColor.Stage.muted)
            }
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(section.moments) { moment in
                    Button { onOpen(moment) } label: { MemoryMomentCell(moment: moment) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct MemoryMomentCell: View {
    let moment: MemoryMoment

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let item = moment.item {
                    MemoryThumbnail(relativePath: item.thumbnailRelativePath ?? item.relativePath)
                } else {
                    Text(moment.fragment.text ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(5)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.white.opacity(0.07))
                }
            }
            .overlay(alignment: .bottom) { footer }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BSLocalization.format("打开记忆碎片，%@", BSDateFormat.clock(moment.date, timeZone: .current)))
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(BSDateFormat.clock(moment.date, timeZone: .current))
            Spacer(minLength: 0)
            if moment.item != nil, moment.caption != nil {
                Image(systemName: "text.bubble.fill")
            }
            if let item = moment.item, item.kind == .video {
                Image(systemName: "play.fill")
                if let duration = item.videoDuration { Text(Self.duration(duration)) }
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
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
                    Image(systemName: "photo").foregroundStyle(BSColor.Stage.muted)
                }
            }
        }
        .task(id: relativePath) {
            let path = MemoryMediaLocation.applicationSupport().url(for: relativePath).path
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: path) }.value
        }
        // 用户照片：session replay 已关掉全图遮罩，用户自己的照片 / 视频帧必须显式遮回来。
        .bsMaskUserContent()
    }
}
