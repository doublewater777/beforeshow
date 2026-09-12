import SwiftUI

// MARK: - Current Show Quick Actions

enum CurrentShowQuickAction: Hashable {
    case route
    case companion
    case ticket
    case timetable
    case memoryFragments
    case endShow

    var title: String {
        switch self {
        case .route: return BSLocalization.text("路线")
        case .companion: return BSLocalization.text("同行")
        case .ticket: return BSLocalization.text("票根")
        case .timetable: return BSLocalization.text("时刻表")
        case .memoryFragments: return BSLocalization.text("记忆碎片")
        case .endShow: return BSLocalization.text("结束现场")
        }
    }

    var iconName: String {
        switch self {
        case .route: return "map"
        case .companion: return "person.2"
        case .ticket: return "ticket"
        case .timetable: return "list.bullet.rectangle"
        case .memoryFragments: return "photo.on.rectangle.angled"
        case .endShow: return "flag.checkered"
        }
    }

    /// 快捷入口按生命周期排序:主行动已在卡片上,这里保留其余入口,
    /// 但把当前阶段次相关的动作后置,避免 ended 后路线/票根抢占记忆。
    /// `embedsRouteInLocation` 为真时路线收进倒计时地点,不再占一格。
    static func actions(
        for phase: HomeShowPhase,
        inOpeningMemoryWindow: Bool = false,
        canRecordEnd: Bool = true,
        embedsRouteInLocation: Bool = false
    ) -> [Self] {
        let actions: [Self]
        switch phase {
        case .pre:
            actions = [.route, .ticket, .timetable, .companion, .memoryFragments]
        case .live:
            if inOpeningMemoryWindow {
                var live: [Self] = [.companion, .memoryFragments, .route, .ticket, .timetable]
                if canRecordEnd {
                    live.insert(.endShow, at: 0)
                }
                actions = live
            } else {
                actions = [.companion, .memoryFragments, .route, .ticket, .timetable]
            }
        case .ended:
            actions = [.memoryFragments, .companion, .route, .ticket, .timetable]
        case .inactive:
            actions = [.route, .companion, .ticket, .timetable, .memoryFragments]
        }
        return embedsRouteInLocation ? actions.filter { $0 != .route } : actions
    }
}

struct CurrentShowQuickActionTile: View {
    let action: CurrentShowQuickAction
    var companion: CompanionQuickActionPresentation?

    var body: some View {
        VStack(spacing: 7) {
            if let companion, companion.showsAvatars {
                CompanionAvatarStack(names: companion.companionNames)
            } else {
                Image(systemName: action.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
            }
            Text(companion?.title ?? action.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 72)
        .background(BSColor.Stage.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if companion?.showsPendingIndicator == true {
                Circle()
                    .fill(BSColor.Stage.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: BSColor.Stage.accent.opacity(0.5), radius: 5)
                    .padding(11)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(companion?.accessibilityLabel ?? action.title)
    }
}

private struct CompanionAvatarStack: View {
    let names: [String]

    private static let maxVisibleOthers = 3
    private static let palettes: [[Color]] = [
        [BSColor.Stage.accent, BSColor.Stage.glowBlue],
        [BSColor.Accent.violet, BSColor.Stage.accent],
        [BSColor.Accent.warm, BSColor.Accent.violet],
        [BSColor.Stage.glowBlue, BSColor.Accent.warm]
    ]

    var body: some View {
        let visible = Array(CompanionNameList.normalized(names).prefix(Self.maxVisibleOthers))
        let overflow = max(0, CompanionNameList.normalized(names).count - visible.count)
        return HStack(spacing: -8) {
            avatar(BSLocalization.text("我"), colors: Self.palettes[0])
            ForEach(Array(visible.enumerated()), id: \.offset) { index, name in
                avatar(initial(name), colors: Self.palettes[(index + 1) % Self.palettes.count])
            }
            if overflow > 0 {
                avatar("+\(overflow)", colors: [BSColor.Stage.muted, BSColor.Stage.dim])
            }
        }
        .accessibilityHidden(true)
    }

    private func initial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? BSLocalization.text("友") : String(trimmed.prefix(1))
    }

    private func avatar(_ text: String, colors: [Color]) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(BSColor.Stage.background)
            .frame(width: 25, height: 25)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Circle())
            .overlay(Circle().stroke(BSColor.Stage.surface, lineWidth: 2))
    }
}
