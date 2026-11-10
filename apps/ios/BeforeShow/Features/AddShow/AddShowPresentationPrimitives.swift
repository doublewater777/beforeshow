import SwiftUI

// MARK: - Add Show Presentation Primitives

struct EditShowFormCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var hint: String? = nil
    var pillText: String? = nil
    var pillTint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.13))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.textPrimary)

                Spacer(minLength: 0)

                if let pillText {
                    let tint = pillTint ?? BSColor.Stage.accent
                    Text(pillText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(tint.opacity(0.30), lineWidth: 1)
                        )
                } else if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.Stage.dim)
                }
            }

            VStack(alignment: .leading, spacing: BSSpacing.md) {
                content
            }
        }
        .padding(16)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }
}

private struct AddShowInputChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(BSFont.body)
            .foregroundStyle(BSColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            )
    }
}

extension View {
    func addShowInputChrome() -> some View {
        modifier(AddShowInputChrome())
    }
}

/// 添加 / 编辑现场的主按钮：与全 App 主动作一致的白底深字。
struct EditShowSaveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isEnabled ? BSColor.Stage.background : BSColor.Stage.dim)
            .frame(minHeight: 52)
            .background(
                isEnabled ? BSColor.Stage.foreground : BSColor.Stage.surfaceRaised,
                in: RoundedRectangle(cornerRadius: BSRadius.md)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .strokeBorder(BSColor.Stage.border, lineWidth: 1)
            }
            .opacity(isEnabled && configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
