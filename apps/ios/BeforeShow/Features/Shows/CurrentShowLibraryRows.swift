import SwiftUI

/// 「即将开始」行：日期与倒计时是主信息。
struct CurrentShowLibraryUpcomingRow: View {
    let show: Show
    let isCurrent: Bool
    let phase: CurrentShowTimeState
    let actions: [CurrentShowLibraryMenuAction]
    let onOpen: () -> Void
    let onAction: (CurrentShowLibraryMenuAction) -> Void
    var onSetCurrent: (() -> Void)?

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Button(action: onOpen) {
                HStack(spacing: BSSpacing.compact) {
                    ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, cornerRadius: 10)
                        .frame(width: 54, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(show.name)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(statusLine)
                            .font(BSFont.V3.small.weight(.medium))
                            .foregroundStyle(isChanged ? BSColor.Accent.warm : BSColor.Stage.foreground.opacity(0.82))
                            .lineLimit(1)
                        Text([shortDateText, show.venueName ?? show.city].compactMap { $0 }.joined(separator: " · "))
                            .font(BSFont.V3.caption)
                            .foregroundStyle(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isCurrent {
                        Text(BSLocalization.text("当前"))
                            .font(BSFont.V3.caption)
                            .foregroundStyle(BSColor.Stage.accent)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCurrent, let onSetCurrent {
                CurrentShowSetCurrentButton(action: onSetCurrent)
            }
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(isCurrent ? BSColor.Stage.accent.opacity(0.45) : BSColor.Stage.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 17))
        .contextMenu {
            CurrentShowLibraryMenuItems(actions: actions, onAction: onAction)
        }
    }

    private var isChanged: Bool { show.changeStatus != .scheduled }

    private var shortDateText: String {
        let calendar = show.timingCalendar()
        let start = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: start)
        let day = BSLocalization.format("%lld月%lld日", parts.month ?? 1, parts.day ?? 1)
        return day + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private var statusLine: String {
        isChanged ? phase.statusText : phase.countdownText
    }
}

/// 往期海报墙：海报上不叠控件，标题与日期放在海报下方。
struct CurrentShowLibraryArchiveTile: View {
    let show: Show
    let actions: [CurrentShowLibraryMenuAction]
    let onOpen: () -> Void
    let onAction: (CurrentShowLibraryMenuAction) -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        ShowCoverImageView(
                            urlString: show.coverImageURL,
                            aspectRatio: 3.0 / 4.0,
                            contentMode: .fill,
                            enforcesAspectRatio: false,
                            cornerRadius: BSRadius.md
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border, lineWidth: 1))
                    .opacity(isCanceled ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(show.name)
                        .font(BSFont.V3.caption)
                        .foregroundStyle(BSColor.Stage.foreground.opacity(isCanceled ? 0.5 : 0.9))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(BSColor.Stage.dim)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            CurrentShowLibraryMenuItems(actions: actions, onAction: onAction)
        }
    }

    private var isCanceled: Bool { show.changeStatus == .canceled }

    private var subtitle: String {
        if isCanceled { return BSLocalization.text("已取消") }
        let components = show.timingCalendar().dateComponents([.month, .day], from: show.effectiveDate)
        return BSLocalization.format("%lld月%lld日", components.month ?? 1, components.day ?? 1)
    }
}

private struct CurrentShowLibraryMenuItems: View {
    let actions: [CurrentShowLibraryMenuAction]
    let onAction: (CurrentShowLibraryMenuAction) -> Void

    var body: some View {
        ForEach(actions.filter { !$0.isStatusAction && $0 != .delete }, id: \.self) { action in
            Button {
                onAction(action)
            } label: {
                Label(action.title, systemImage: action.icon)
            }
        }

        if actions.contains(where: \.isStatusAction) {
            Menu {
                ForEach(actions.filter(\.isStatusAction), id: \.self) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        onAction(action)
                    } label: {
                        Label(action.title, systemImage: action.icon)
                    }
                }
            } label: {
                Label(BSLocalization.text("现场状态"), systemImage: "calendar.badge.clock")
            }
        }

        if actions.contains(.delete) {
            Divider()
            Button(role: .destructive) {
                onAction(.delete)
            } label: {
                Label(CurrentShowLibraryMenuAction.delete.title, systemImage: CurrentShowLibraryMenuAction.delete.icon)
            }
        }
    }
}

/// 行内可见的「设为当前」：左滑只是快捷方式，不能作为唯一入口。
struct CurrentShowSetCurrentButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(BSLocalization.text("设为当前"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(BSColor.Stage.surfaceRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(BSColor.Stage.border, lineWidth: 1))
                .frame(minHeight: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
