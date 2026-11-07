import SwiftUI

/// Top bar of the current tab: "当前", the weather, and the live chip while a festival timetable runs.
struct CurrentShowHomeHeader: View {
    let show: Show
    let live: LiveModeState?
    let onOpenSettings: () -> Void
    let onAddShow: () -> Void
    var weather: ShowWeatherDTO? = nil
    var onOpenWeather: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Text(BSLocalization.text("当前"))
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(BSColor.Stage.foreground)

            if let weather {
                CurrentShowWeatherCapsule(weather: weather, action: onOpenWeather)
                    .transition(.opacity)
            }
            if let live {
                statusChip(live)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                headerButton(icon: "gearshape", label: BSLocalization.text("设置"), action: onOpenSettings)
                headerButton(icon: "plus", label: BSLocalization.text("添加现场"), action: onAddShow)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statusChip(_ live: LiveModeState) -> some View {
        let (text, color): (String, Color) = {
            switch live.phase {
            case .upcoming: return (BSLocalization.text("今日首场"), BSColor.Stage.accent)
            case .dayEnded: return (BSLocalization.text("今天结束"), HomeLiveStyle.night)
            case .fullyEnded: return (BSLocalization.text("全部结束"), BSColor.Stage.accent)
            default:
                let index = show.timetable?.orderedDays.firstIndex { $0.id == live.activeDayID }
                return (index.map { BSLocalization.format("第%d天", $0 + 1) } ?? BSLocalization.text("现场"), BSColor.Stage.live)
            }
        }()
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 3)
            Text(text).lineLimit(1).fixedSize()
        }
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(color == BSColor.Stage.live ? BSColor.Stage.liveTitle : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func headerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
