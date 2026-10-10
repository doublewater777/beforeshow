import SwiftUI

/// Top bar of the current tab. In live mode the large "当前" title gives way to
/// the show's identity: the cover, collapsed to a 3:4 thumbnail, plus its status.
struct CurrentShowHomeHeader: View {
    let show: Show
    let live: LiveModeState?
    let coverNamespace: Namespace.ID
    let onToggleCover: () -> Void
    let onOpenSettings: () -> Void
    let onAddShow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let live {
                Button(action: onToggleCover) {
                    HStack(spacing: 12) {
                        ShowCoverImageView(
                            urlString: show.coverImageURL,
                            aspectRatio: 3.0 / 4.0,
                            contentMode: .fill,
                            enforcesAspectRatio: false,
                            cornerRadius: 10,
                            restoresPersistedImageOnFirstFrame: true
                        )
                        .frame(width: 42, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .matchedGeometryEffect(id: "home-cover", in: coverNamespace)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(show.name)
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(BSColor.Stage.foreground)
                                .lineLimit(1)
                            statusChip(live)
                        }
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                Text(BSLocalization.text("当前"))
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(BSColor.Stage.foreground)
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
            case .dayEnded: return (BSLocalization.text("现场模式"), HomeLiveStyle.night)
            case .fullyEnded: return (BSLocalization.text("全部结束"), BSColor.Stage.accent)
            default:
                let index = show.timetable?.orderedDays.firstIndex { $0.id == live.activeDayID }
                return (index.map { BSLocalization.format("现场模式 · 第%d天", $0 + 1) } ?? BSLocalization.text("现场模式"), BSColor.Stage.live)
            }
        }()
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 3)
            Text(text)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.6)
        .foregroundColor(color == BSColor.Stage.live ? BSColor.Stage.liveTitle : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func headerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
