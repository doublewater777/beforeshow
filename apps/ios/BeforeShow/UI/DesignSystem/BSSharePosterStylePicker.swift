import SwiftUI

/// A share poster's look; the free one is always first.
protocol BSSharePosterStyle: CaseIterable, Identifiable, Hashable where AllCases: RandomAccessCollection {
    var title: String { get }
    var isPro: Bool { get }
}

/// The looks a share poster comes in, one row of choices above the save and share buttons.
/// A Pro look shows a lock until Pro is active; tapping it asks the caller to open the paywall.
struct BSSharePosterStylePicker<Style: BSSharePosterStyle>: View {
    @Binding var selection: Style
    let isProActive: Bool
    let onLocked: () -> Void

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            ForEach(Style.allCases) { style in
                let locked = style.isPro && !isProActive
                let isSelected = style == selection
                Button {
                    if locked {
                        onLocked()
                    } else {
                        selection = style
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(style.title)
                        if locked {
                            Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(locked ? 0.55 : 0.9))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        Capsule().fill(isSelected ? BSColor.Stage.foreground : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
