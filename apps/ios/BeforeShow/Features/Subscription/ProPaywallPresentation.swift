import SwiftUI

struct ProPaywallBackground: View {
    var body: some View {
        ZStack {
            CurrentShowStageBackground()
            RadialGradient(
                colors: [BSColor.Stage.accent.opacity(0.13), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 280
            )
            RadialGradient(
                colors: [BSColor.Stage.glowBlue.opacity(0.09), .clear],
                center: UnitPoint(x: 0.02, y: 0.14),
                startRadius: 0,
                endRadius: 240
            )
        }
        .ignoresSafeArea()
    }
}

struct ProPaywallHero: View {
    let showsCloseButton: Bool

    @State private var beamsSwaying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                heroBeams

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [BSColor.Stage.accent.opacity(0.18), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 52
                            )
                        )
                        .frame(width: 104, height: 104)
                        .blur(radius: 4)
                    Image(systemName: "sparkle")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(BSColor.Stage.accent)
                }
                .frame(width: 67, height: 67)
            }
            .frame(height: 150)
            .padding(.bottom, 18)

            Text("BEFORESHOW PRO")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.7)
                .foregroundColor(BSColor.Stage.accent)
                .padding(.bottom, 9)

            Text(BSLocalization.text("把下一场，\n也留下来"))
                .font(.system(size: 29, weight: .bold))
                .kerning(-0.7)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundColor(BSColor.Stage.foreground)

            Text(ProPaywallCopy.summary)
                .font(.system(size: 13))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundColor(BSColor.Stage.muted)
                .frame(maxWidth: 310)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, showsCloseButton ? 34 : BSSpacing.md)
        .onAppear { beamsSwaying = true }
    }

    private var heroBeams: some View {
        ZStack(alignment: .bottom) {
            heroBeam(color: BSColor.Stage.glowBlue, topWidth: 150, rotation: 30, sway: 3.5, period: 6.5, opacity: 0.75)
            heroBeam(color: BSColor.Stage.accent, topWidth: 150, rotation: -30, sway: -3.0, period: 5.5, opacity: 0.70)
            heroBeam(color: BSColor.Accent.violet, topWidth: 110, rotation: 0, sway: 2.0, period: 7.0, opacity: 0.50)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func heroBeam(
        color: Color,
        topWidth: CGFloat,
        rotation: Double,
        sway: Double,
        period: Double,
        opacity: Double
    ) -> some View {
        PaywallBeamShape()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.85), color.opacity(0.28), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: topWidth, height: 190)
            .rotationEffect(
                .degrees(rotation + (beamsSwaying ? sway : 0)),
                anchor: .bottom
            )
            .blur(radius: 7)
            .opacity(opacity)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: period).repeatForever(autoreverses: true),
                value: beamsSwaying
            )
    }
}

struct ProPaywallBenefitCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 24, height: 24)
                .background(BSColor.Stage.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(BSLocalization.text("无限添加现场"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("未来的每一场，都可以继续进入「当前」并最终留进「足迹」。"))
                    .font(.system(size: 11.8))
                    .lineSpacing(2)
                    .foregroundColor(BSColor.Stage.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Stage.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(
            RoundedRectangle(cornerRadius: 19)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }
}

struct ProPaywallActiveCard: View {
    var body: some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(BSColor.brandGradient)
            Text(BSLocalization.text("Pro 已启用，可以继续添加现场。"))
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.foreground)
        }
        .padding(BSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(
            RoundedRectangle(cornerRadius: 19)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }
}

struct ProPaywallNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .multilineTextAlignment(.center)
            .foregroundColor(BSColor.Stage.dim)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ProPaywallLinksRow: View {
    let isDisabled: Bool
    let onRestore: () -> Void
    let onPrivacy: () -> Void
    let onTerms: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            linkButton(BSLocalization.text("恢复购买"), action: onRestore)
            linkButton(BSLocalization.text("隐私政策"), action: onPrivacy)
            linkButton(BSLocalization.text("用户协议"), action: onTerms)
            Spacer(minLength: 0)
        }
        .disabled(isDisabled)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11))
            .foregroundColor(BSColor.Stage.muted)
    }
}

private struct PaywallBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}
