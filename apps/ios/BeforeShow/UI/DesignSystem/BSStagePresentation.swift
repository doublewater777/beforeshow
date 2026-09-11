import SafariServices
import UIKit
import SwiftUI

struct BSStageSheetHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = BSColor.Stage.accent

    var body: some View {
        VStack(spacing: BSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)

            Text(subtitle)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
        }
    }
}

struct CurrentShowStageBackground: View {
    var body: some View {
        ZStack {
            Color.black

            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.02),
                    Color(red: 0.04, green: 0.04, blue: 0.06),
                    Color(red: 0.02, green: 0.02, blue: 0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geometry in
                ZStack {
                    StageBackgroundGlow(color: Color(red: 0.69, green: 0.36, blue: 1.0).opacity(0.18))
                        .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.58)
                        .position(x: geometry.size.width * 0.50, y: geometry.size.height * 1.02)

                    StageBackgroundGlow(color: Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.12))
                        .frame(width: geometry.size.width * 0.58, height: geometry.size.height * 0.40)
                        .position(x: geometry.size.width * 0.18, y: geometry.size.height * 0.92)

                    StageBackgroundGlow(color: Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.10))
                        .frame(width: geometry.size.width * 0.48, height: geometry.size.height * 0.34)
                        .position(x: geometry.size.width * 0.82, y: geometry.size.height * 0.92)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }
}

private struct StageBackgroundGlow: View {
    let color: Color

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        color,
                        color.opacity(0.55),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 230
                )
            )
            .blur(radius: 22)
    }
}

struct BSStageScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var bottomPadding: CGFloat = 32
    var topBarBackAction: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let topBarBackAction {
                    HStack(spacing: 12) {
                        BSChromeIconButton(
                            systemName: "chevron.left",
                            accessibilityLabel: "返回",
                            action: topBarBackAction
                        )

                        Text(title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(BSColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, BSSpacing.md)
                    .padding(.vertical, 4)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        if topBarBackAction == nil {
                            if !title.isEmpty || subtitle != nil {
                                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                                    if !title.isEmpty {
                                        Text(title)
                                            .font(.system(size: 30, weight: .bold))
                                            .foregroundColor(BSColor.textPrimary)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.82)
                                    }

                                    if let subtitle {
                                        subtitleText(subtitle)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if let subtitle {
                            subtitleText(subtitle)
                        }

                        content
                    }
                    .padding(.horizontal, BSSpacing.md)
                    .padding(.top, topBarBackAction == nil ? BSSpacing.lg : 12)
                    .padding(.bottom, bottomPadding)
                }
                .scrollIndicators(.hidden)
                .bsNavigationScrollEdge()
            }
        }
    }

    private func subtitleText(_ subtitle: String) -> some View {
        Text(subtitle)
            .font(BSFont.caption)
            .foregroundColor(BSColor.textTertiary)
            .lineLimit(2)
    }
}

struct CurrentShowAmbientBackground: View {
    let coverImageURL: String?

    /// 封面主色（CIAreaAverage 提取后提饱和压亮度）；换封面经 .task(id:) 自动重取。
    @State private var ambientColor: Color?

    var body: some View {
        ZStack {
            // ① stage-void base
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.018, blue: 0.025),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // ② 封面主色环境光（Apple Music 式）：放大模糊垫在顶部与卡片背后
            GeometryReader { geometry in
                if let ambientColor {
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [
                                ambientColor.opacity(0.85),
                                ambientColor.opacity(0.38),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.68
                        ))
                        .frame(width: geometry.size.width * 1.35, height: geometry.size.height * 0.62)
                        .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.10)
                        .blur(radius: 50)
                        .blendMode(.screen)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.7), value: ambientColor)

            // ③ 只保留从封面提取的抽象漫光。完整封面回声会在卡片边缘形成
            // 第二套图像轮廓，让内缩的主海报看起来像横向错位。

            // ④ vertical contrast scrim (top stop lightened so the bloom reads through)
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.24), location: 0.00),
                    .init(color: Color.black.opacity(0.16), location: 0.42),
                    .init(color: Color.black.opacity(0.34), location: 0.76),
                    .init(color: Color.black.opacity(0.58), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: coverImageURL) {
            ambientColor = await Self.loadAmbientColor(for: coverImageURL)
        }
    }

    private static func loadAmbientColor(for urlString: String?) async -> Color? {
        guard let urlString,
              let url = URL(string: urlString),
              let image = await ShowCoverImageCache.shared.image(from: url),
              let stageColor = CoverAmbientColor.uiColor(from: image) else {
            return nil
        }
        return Color(stageColor)
    }
}

struct BSSurfacePanel<Content: View>: View {
    var padding: CGFloat = BSSpacing.md
    @ViewBuilder var content: Content

    var body: some View {
        // Intentionally a flat tonal panel — backdrop blur is reserved for
        // overlays and the countdown bridge. If a future surface needs a real
        // translucent material, reach for `.ultraThinMaterial` directly rather
        // than reintroducing a "glass" surface here.
        content
            .padding(padding)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.lg)
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            )
    }
}

struct BSSettingsSurface<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(BSColor.Stage.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.lg)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
    }
}

/// In-app Safari page, presented with `.sheet(item:)`. Keeps users inside the
/// app instead of jumping to the separate Safari app.
