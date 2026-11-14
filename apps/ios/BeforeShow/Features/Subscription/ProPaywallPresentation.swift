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
                        .foregroundStyle(BSColor.Stage.accent)
                }
                .frame(width: 67, height: 67)
            }
            .frame(height: 104, alignment: .bottom)
            .padding(.bottom, 12)

            Text("BEFORESHOW PRO")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(BSColor.Stage.accent)
                .padding(.bottom, 9)

            Text(BSLocalization.text("把下一场，\n也留下来"))
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.7)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(BSColor.Stage.foreground)

            Text(ProPaywallCopy.summary)
                .font(.system(size: 13))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(BSColor.Stage.muted)
                .frame(maxWidth: 310)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, showsCloseButton ? 20 : BSSpacing.md)
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

/// Everything Pro unlocks at a glance: the headline benefit across the top, the rest as a grid of tiles.
struct ProPaywallBenefitCard: View {
    struct Benefit {
        let icon: String
        let title: String
        let detail: String
    }

    static let headline = Benefit(
        icon: "infinity",
        title: BSLocalization.text("无限添加现场"),
        detail: BSLocalization.text("突破免费版 15 场上限，每一场都能进「当前」、留进「足迹」。")
    )

    static let others = [
        Benefit(icon: "sparkles", title: BSLocalization.text("时刻表智能识别"), detail: BSLocalization.text("截图识别排期，不限次数")),
        Benefit(icon: "opticaldisc", title: BSLocalization.text("「挑一张」全部样式"), detail: BSLocalization.text("3D 唱片柜、旋转木马等")),
        Benefit(icon: "music.note", title: BSLocalization.text("星空音阶与星图"), detail: BSLocalization.text("4 种音阶，4 个星座")),
        Benefit(icon: "photo.on.rectangle", title: BSLocalization.text("全部海报样式"), detail: BSLocalization.text("现场与年度海报")),
        Benefit(icon: "book.closed", title: BSLocalization.text("回忆册 PDF"), detail: BSLocalization.text("整本导出，可打印")),
        Benefit(icon: "app.badge", title: BSLocalization.text("更换 App 图标"), detail: BSLocalization.text("黑白、鎏金")),
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                icon(Self.headline.icon, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.headline.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(Self.headline.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(BSColor.Stage.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(tileBackground(highlighted: true))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.others, id: \.title) { benefit in
                    VStack(alignment: .leading, spacing: 8) {
                        icon(benefit.icon, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(BSColor.Stage.foreground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(benefit.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(BSColor.Stage.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tileBackground(highlighted: false))
                }
            }
        }
    }

    private func icon(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(BSColor.Stage.accent)
            .frame(width: size, height: size)
            .background(BSColor.Stage.accent.opacity(0.12))
            .clipShape(Circle())
    }

    private func tileBackground(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(highlighted ? BSColor.Stage.accent.opacity(0.07) : BSColor.Stage.surface.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(highlighted ? BSColor.Stage.accent.opacity(0.25) : BSColor.Stage.border, lineWidth: 1)
            )
    }
}

struct ProPaywallActiveCard: View {
    var body: some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(BSColor.brandGradient)
            Text(BSLocalization.text("Pro 已启用，全部功能已解锁。"))
                .font(BSFont.body)
                .foregroundStyle(BSColor.Stage.foreground)
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
            .foregroundStyle(BSColor.Stage.dim)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ProPaywallLinksRow: View {
    let isDisabled: Bool
    let onRestore: () -> Void
    let onRedeemCode: () -> Void
    let onPrivacy: () -> Void
    let onTerms: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            linkButton(BSLocalization.text("恢复购买"), action: onRestore)
            linkButton(BSLocalization.text("兑换码"), action: onRedeemCode)
            linkButton(BSLocalization.text("隐私政策"), action: onPrivacy)
            linkButton(BSLocalization.text("用户协议"), action: onTerms)
            Spacer(minLength: 0)
        }
        .disabled(isDisabled)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11))
            .foregroundStyle(BSColor.Stage.muted)
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
