import SwiftUI
import UIKit

extension MemoryFragmentPhase {
    var rollTitle: String {
        switch self {
        case .before: return BSLocalization.text("开场前")
        case .live: return BSLocalization.text("现场")
        case .after: return BSLocalization.text("散场后")
        }
    }
}

enum MemoryRollTimeRange {
    static func rangeText(for phase: MemoryFragmentPhase, timing: ShowTimingFields, moments: [MemoryMoment]) -> String {
        let calendar = timing.eventCalendar(fallback: .current)
        let clock = { (date: Date) in BSDateFormat.clock(date, timeZone: calendar.timeZone) }
        switch phase {
        case .before:
            let start = timing.startTime
            if let first = moments.first?.date, first < start {
                return "\(clock(first)) – \(clock(start))"
            }
            let est = start.addingTimeInterval(-3600)
            return "\(clock(est)) – \(clock(start))"
        case .live:
            let start = timing.startTime
            let end = timing.endedAt ?? timing.endTime ?? start.addingTimeInterval(2 * 3600)
            return "\(clock(start)) – \(clock(end))"
        case .after:
            let ended = timing.endedAt ?? timing.endTime ?? timing.startTime.addingTimeInterval(2 * 3600)
            return "\(clock(ended)) –"
        }
    }
}

/// 齿孔胶片上下的齿孔点阵
struct FilmSprocketsCanvas: View {
    var body: some View {
        Canvas { context, size in
            let dotRadius: CGFloat = 1.6
            let step: CGFloat = 12.0
            let count = Int(size.width / step)
            for i in 0..<count {
                let x = CGFloat(i) * step + step / 2
                let topDot = CGRect(x: x - dotRadius, y: 3.5 - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                let bottomDot = CGRect(x: x - dotRadius, y: size.height - 3.5 - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Path(ellipseIn: topDot), with: .color(Color.white.opacity(0.14)))
                context.fill(Path(ellipseIn: bottomDot), with: .color(Color.white.opacity(0.14)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 齿孔胶片一段：开场前 / 现场 / 散场后
struct FilmStripSectionView: View {
    let section: MemoryMomentSection
    let timing: ShowTimingFields
    let currentPhase: MemoryFragmentPhase
    let newlyAddedIDs: Set<UUID>
    let onOpen: (MemoryMoment) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
    private var isCurrentPhase: Bool { section.phase == currentPhase }

    private var titleColor: Color {
        isCurrentPhase ? Color(red: 232/255, green: 199/255, blue: 142/255) : Color.white.opacity(0.6)
    }

    private var timeText: String {
        MemoryRollTimeRange.rangeText(for: section.phase, timing: timing, moments: section.moments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.phase.rollTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(titleColor)

                if !timeText.isEmpty {
                    Text(timeText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 2)

            filmStrip
        }
    }

    private var filmStrip: some View {
        ZStack {
            FilmSprocketsCanvas()

            if section.moments.isEmpty {
                Color.clear
                    .frame(height: 48)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(section.moments) { moment in
                        Button { onOpen(moment) } label: {
                            MemoryFrameCell(
                                moment: moment,
                                isNewlyAdded: newlyAddedIDs.contains(moment.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
        }
        .background(Color(red: 14/255, green: 15/255, blue: 18/255), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

typealias MemoryMomentCell = MemoryFrameCell

/// 胶卷上的一格：3:4 比例，照片/视频时长/一句话纸片
struct MemoryFrameCell: View {
    let moment: MemoryMoment
    var isNewlyAdded: Bool = false

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let item = moment.item {
                    MemoryThumbnail(relativePath: item.thumbnailRelativePath ?? item.relativePath)
                } else {
                    Text(moment.fragment.text ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .lineSpacing(2)
                        .foregroundStyle(Color(red: 27/255, green: 26/255, blue: 23/255))
                        .lineLimit(5)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color(red: 239/255, green: 231/255, blue: 214/255))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let item = moment.item, item.kind == .video {
                    if let dur = item.videoDuration {
                        Text(Self.formatDuration(dur))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
                            .padding(4)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                if isNewlyAdded {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color(red: 232/255, green: 199/255, blue: 142/255), lineWidth: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.65), value: isNewlyAdded)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if moment.isText {
            return "一句话：" + (moment.fragment.text ?? "")
        }
        return (moment.item?.kind == .video ? "视频" : "照片") + "，" + BSDateFormat.clock(moment.date, timeZone: .current)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 底部常驻玻璃输入栏：相册、写一句、大快门
struct MemoryRollInputBar: View {
    @Binding var draftText: String
    let onOpenLibrary: () -> Void
    let onSubmitText: () -> Void
    let onShoot: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenLibrary) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("从相册添加"))

            HStack {
                TextField(BSLocalization.text("写一句"), text: $draftText)
                    .font(.system(size: 15))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .submitLabel(.done)
                    .onSubmit(onSubmitText)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white.opacity(0.08), in: Capsule())

            Button(action: onShoot) {
                ZStack {
                    Circle()
                        .strokeBorder(BSColor.Stage.foreground, lineWidth: 3)
                        .frame(width: 58, height: 58)
                    Circle()
                        .fill(BSColor.Stage.foreground)
                        .frame(width: 46, height: 46)
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("拍照"))
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
    }
}

/// 记忆保存/删除后的轻量级撤销 Toast
struct MemoryUndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(BSColor.Stage.foreground)
            Button(action: onUndo) {
                Text(BSLocalization.text("撤销"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(Color(red: 40/255, green: 42/255, blue: 48/255).opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
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
                    Color.white.opacity(0.06)
                    Image(systemName: "photo").foregroundStyle(BSColor.Stage.muted)
                }
            }
        }
        .task(id: relativePath) {
            let path = MemoryMediaLocation.applicationSupport().url(for: relativePath).path
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: path) }.value
        }
        .bsMaskUserContent()
    }
}
