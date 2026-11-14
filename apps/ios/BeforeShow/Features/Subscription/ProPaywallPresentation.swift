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
    /// Off on short screens: the beams and the sparkle give way so everything still fits.
    var showsBeams = true

    @State private var beamsSwaying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if showsBeams {
                ZStack(alignment: .bottom) {
                    heroBeams

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [BSColor.Stage.accent.opacity(0.18), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 40
                                )
                            )
                            .frame(width: 80, height: 80)
                            .blur(radius: 4)
                        Image(systemName: "sparkle")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(BSColor.Stage.accent)
                    }
                    .frame(width: 52, height: 52)
            }
            .frame(height: 84, alignment: .bottom)
            .padding(.bottom, 8)
            }

            Text("BEFORESHOW PRO")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(BSColor.Stage.accent)
                .padding(.bottom, 7)

            Text(BSLocalization.text("把下一场，\n也留下来"))
                .font(.system(size: 24, weight: .bold))
                .kerning(-0.7)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(BSColor.Stage.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text(ProPaywallCopy.summary)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(BSColor.Stage.muted)
                .frame(maxWidth: 310)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, showsCloseButton ? 12 : 0)
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
            .frame(width: topWidth, height: 150)
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

/// Everything Pro unlocks in one card: the headline benefit on top, the rest as a quiet two-column list.
struct ProPaywallBenefitCard: View {
    struct Benefit {
        let icon: String
        let title: String
        let detail: String
    }

    static let headline = Benefit(
        icon: "infinity",
        title: BSLocalization.text("无限添加现场"),
        detail: BSLocalization.text("不再受免费版 15 场限制，每一场都留进足迹")
    )

    static let others = [
        Benefit(icon: "sparkles", title: BSLocalization.text("时刻表智能识别"), detail: BSLocalization.text("截图识别排期，不限次数")),
        Benefit(icon: "opticaldisc", title: BSLocalization.text("「挑一张」全部样式"), detail: BSLocalization.text("3D 唱片柜、旋转木马等")),
        Benefit(icon: "music.note", title: BSLocalization.text("星空音阶与星图"), detail: BSLocalization.text("4 种音阶，4 个星座")),
        Benefit(icon: "photo.on.rectangle", title: BSLocalization.text("全部海报与回忆册"), detail: BSLocalization.text("海报样式、整本 PDF")),
        Benefit(icon: "music.note.list", title: BSLocalization.text("歌单导入音乐 App"), detail: BSLocalization.text("网易云、QQ 音乐、汽水")),
        Benefit(icon: "app.badge", title: BSLocalization.text("更换 App 图标"), detail: BSLocalization.text("黑白、鎏金")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: Self.headline.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BSColor.Stage.accent)
                    .frame(width: 34, height: 34)
                    .background(BSColor.Stage.accent.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.bottom, 14)

            Rectangle()
                .fill(BSColor.Stage.border)
                .frame(height: 1)
                .padding(.bottom, 14)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                ForEach(0..<(Self.others.count + 1) / 2, id: \.self) { row in
                    GridRow {
                        ForEach(Self.others[row * 2..<min(row * 2 + 2, Self.others.count)], id: \.title) { benefit in
                            item(benefit)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(BSColor.Stage.surface.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(BSColor.Stage.accent.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func item(_ benefit: Benefit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: benefit.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BSColor.Stage.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(benefit.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 22) {
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
