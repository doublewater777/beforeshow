import SwiftUI

struct CurrentShowLibraryCoverCard: View {
    let show: Show
    let isCurrent: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .topLeading) {
                ShowCoverImageView(
                    urlString: show.coverImageURL,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fill,
                    enforcesAspectRatio: false,
                    cornerRadius: BSRadius.md
                )

                if show.changeStatus != .scheduled {
                    tag(statusTag, color: statusColor)
                        .padding(BSSpacing.sm)
                }
            }
            // 外层固定 3:4 比例，让封面始终吃列宽；否则加载中的图会按内禀尺寸
            // 撑大 ZStack，溢出列边界——与 HomeHeroPresentation 的处理一致。
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                    .stroke(isCurrent ? BSColor.Stage.glowBlue.opacity(0.55) : BSColor.Stage.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(show.name)
        .accessibilityElement(children: .contain)
    }

    private var statusTag: String {
        show.changeStatus == .canceled ? BSLocalization.text("已取消") : BSLocalization.text("已延期")
    }

    private var statusColor: Color {
        show.changeStatus == .canceled ? BSColor.Accent.danger : BSColor.Accent.warm
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(BSFont.V3.caption)
            .foregroundColor(color)
            .padding(.horizontal, BSSpacing.sm)
            .padding(.vertical, BSSpacing.xs)
            .background(BSColor.Stage.background.opacity(0.82), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
    }
}

struct CurrentShowLibraryRow: View {
    let show: Show
    let isCurrent: Bool
    let formatter: ShowDisplayFormatter
    let actions: [CurrentShowLibraryMenuAction]
    let onOpen: () -> Void
    let onAction: (CurrentShowLibraryMenuAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 11) {
                    ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, cornerRadius: 10)
                        .frame(width: 47, height: 63)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            if isCurrent { tag(BSLocalization.text("当前展示"), color: BSColor.Stage.glowBlue) }
                            if show.changeStatus != .scheduled { tag(statusTag, color: BSColor.Accent.warm) }
                        }
                        Text(show.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(BSColor.Stage.foreground)
                            .lineLimit(1)
                        Text([formatter.dateText(for: show), show.venueName ?? show.city].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11.4))
                            .foregroundColor(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Menu {
                ForEach(actions, id: \.self) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        onAction(action)
                    } label: {
                        Label(BSLocalization.text(action.rawValue), systemImage: action.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.055), in: Circle())
            }
            .accessibilityLabel(BSLocalization.format("管理 %@", show.name))
            .padding(.trailing, 11)
        }
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var statusTag: String { show.changeStatus == .canceled ? BSLocalization.text("已取消") : BSLocalization.text("已延期") }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}

struct LibraryRowEntrance: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.34).delay(Double(min(index, 8)) * 0.04),
                value: appeared
            )
    }
}
