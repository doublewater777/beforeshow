import SafariServices
import UIKit
import SwiftUI

// MARK: - Colors
// Derived from the SplashView entry-page mood: dark, immersive, stage-lit.

enum BSColor {
    /// True black stage floor.
    static let background = Color.black
    /// Elevated cards and sheets, just above black.
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.11)
    /// Slightly lifted surfaces for hover/pressed states.
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.15)

    /// Primary text on dark backgrounds.
    static let textPrimary = Color.white
    /// Secondary text: dates, venues, subtitles.
    static let textSecondary = Color.white.opacity(0.72)
    /// Tertiary text: hints, footnotes.
    static let textTertiary = Color.white.opacity(0.48)

    /// Subtle divider and card strokes.
    static let border = Color.white.opacity(0.08)
    /// Slightly more visible divider when needed.
    static let borderProminent = Color.white.opacity(0.14)

    /// Brand gradient from the SplashView: cyan → purple → amber.
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.49, green: 0.81, blue: 1.0),
            Color(red: 0.70, green: 0.53, blue: 1.0),
            Color(red: 1.0, green: 0.70, blue: 0.28)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Soft gradient used for hero text and countdown numbers.
    static let brandGradientSoft = LinearGradient(
        colors: [
            Color(red: 0.49, green: 0.81, blue: 1.0).opacity(0.9),
            Color(red: 0.70, green: 0.53, blue: 1.0).opacity(0.9),
            Color(red: 1.0, green: 0.70, blue: 0.28).opacity(0.9)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Functional accent tints for feature icons.
    enum Accent {
        static let warm = Color(red: 1.0, green: 0.70, blue: 0.28)       // amber
        static let info = Color(red: 0.49, green: 0.81, blue: 1.0)       // cyan
        static let violet = Color(red: 0.70, green: 0.53, blue: 1.0)     // purple
        static let prepare = Color(red: 0.34, green: 0.84, blue: 0.56)   // mint
        static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)    // coral
    }

    /// Home V3 palette from the 2026-07 feature-cards design: warm tungsten gold
    /// on a blue-tinged stage. Scoped to the current-show home surface; other
    /// surfaces keep the tokens above. Mirrored in DESIGN.md «Home 功能卡色板».
    enum Stage {
        /// Root stage background (#05070D).
        static let background = Color(red: 0.020, green: 0.027, blue: 0.051)
        /// Feature card surface (#0D111B).
        static let surface = Color(red: 0.051, green: 0.067, blue: 0.106)
        /// Raised surface under the floating countdown card (#151A27).
        static let surfaceRaised = Color(red: 0.082, green: 0.102, blue: 0.153)
        /// Primary foreground (#F2F3F7).
        static let foreground = Color(red: 0.949, green: 0.953, blue: 0.969)
        /// Supporting copy (#9399AA).
        static let muted = Color(red: 0.576, green: 0.600, blue: 0.667)
        /// Tertiary copy (#646B7D).
        static let dim = Color(red: 0.392, green: 0.420, blue: 0.490)
        /// Hairline on dark (white 9%).
        static let border = Color.white.opacity(0.09)

        /// Warm tungsten gold — home primary accent (#E8C78E).
        static let accent = Color(red: 0.910, green: 0.780, blue: 0.557)
        /// Countdown hero 色温递进:远场奶白 (#F5EFE2) → 当天暖金 (#F0DCB6) → <1h 用 accent。
        static let heroIvory = Color(red: 0.961, green: 0.937, blue: 0.886)
        static let heroWarmGold = Color(red: 0.941, green: 0.863, blue: 0.714)
        /// Cool blue stage-light tone (#527FC9).
        static let glowBlue = Color(red: 0.322, green: 0.498, blue: 0.788)
        /// 出门清单 card tone (#7B678F).
        static let prepare = Color(red: 0.482, green: 0.404, blue: 0.561)
        /// Badge text: card tone pre-mixed toward white (design color-mix).
        static let prepareBadge = Color(red: 0.627, green: 0.573, blue: 0.682)

        /// Live pulse red (#FF6B75), live status title (#FFD0D3).
        static let live = Color(red: 1.000, green: 0.420, blue: 0.459)
        static let liveTitle = Color(red: 1.000, green: 0.816, blue: 0.827)
        /// Checked state (#A7C9B5).
        static let success = Color(red: 0.655, green: 0.788, blue: 0.710)
        static let danger = Color(red: 0.851, green: 0.537, blue: 0.569)
    }

}

// MARK: - Typography
// Matches the SplashView: light weights, generous tracking, cinematic spacing.

enum BSFont {
    /// Massive countdown / hero numbers.
    static let display = Font.system(size: 80, weight: .light, design: .default)
    /// Screen titles (current show name, large headings).
    static let heroTitle = Font.system(size: 32, weight: .light, design: .default)
    /// Section headings.
    static let title = Font.system(size: 22, weight: .regular, design: .default)
    /// Card titles and primary labels.
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    /// Body copy.
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    /// Captions, metadata, footnotes.
    static let caption = Font.system(size: 13, weight: .medium, design: .default)
    /// Small pills and tags.
    static let tag = Font.system(size: 12, weight: .semibold, design: .default)

    /// Letter spacing used for splash-style large text.
    static let splashTracking: CGFloat = 6
    static let titleTracking: CGFloat = 2

    enum V3 {
        static let display = Font.system(size: 40, weight: .light)
        static let title1 = Font.system(size: 28, weight: .semibold)
        static let title2 = Font.system(size: 22, weight: .semibold)
        static let title3 = Font.system(size: 17, weight: .medium)
        static let body = Font.system(size: 15, weight: .regular)
        static let small = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 11, weight: .medium)
    }
}

// MARK: - Spacing

enum BSSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let compact: CGFloat = 12
    static let roomy: CGFloat = 20
}

// MARK: - Radius

enum BSRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let v3Medium: CGFloat = 16
    static let lg: CGFloat = 20
    static let sheet: CGFloat = 24
    static let pill: CGFloat = 999
}

enum BSMotion {
    static let micro: TimeInterval = 0.16
    static let interface: TimeInterval = 0.22
    static let emphasis: TimeInterval = 0.60
}

enum BSLayout {
    /// Reserved space above the floating glass tab bar.
    static let floatingTabBarClearance: CGFloat = 108
    /// Extra scroll room so the last row clears the floating system tab bar.
    static let tabBarContentInset: CGFloat = 96
    /// Minimum tap target edge per HIG.
    static let minTouchTarget: CGFloat = 44
    /// Shared top inset for primary page headers across the two root tabs.
    static let pageHeaderTopPadding: CGFloat = 4
    static let emptyStateActionWidth: CGFloat = 180
    static let emptyStateActionHeight: CGFloat = 49
    /// Visible circle for sheet/page chrome (close, back). Hit target stays `minTouchTarget`.
    static let chromeButtonSize: CGFloat = 32
    static let chromeIconSize: CGFloat = 13
}

enum BSSettingsStyle {
    static let rowMinimumHeight: CGFloat = 68
    static let rowVerticalPadding: CGFloat = 14
    static let rowDividerInset: CGFloat = 62
    static let iconContainerSize: CGFloat = 34
    static let iconSize: CGFloat = 15
    static let iconCornerRadius: CGFloat = 10
    static let iconSurfaceOpacity: Double = 0.12
    static let pressedOpacity: Double = 0.72
    static let membershipGlowRadius: CGFloat = 180
    static let membershipGlowOpacity: Double = 0.13
    static let membershipBorderOpacity: Double = 0.20
}

// MARK: - Reusable View Modifiers

extension View {
    /// Splash-style gradient text, used sparingly for hero moments.
    func bsGradientText() -> some View {
        self
            .foregroundStyle(BSColor.brandGradient)
    }

    /// iOS 26 scroll-edge pocket so an inline navigation title stays readable.
    @ViewBuilder
    func bsNavigationScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func bsClearNavigationContainer() -> some View {
        if #available(iOS 18.0, *) {
            self.containerBackground(.clear, for: .navigation)
        } else {
            self
        }
    }

    /// Let the system sheet material show through a NavigationStack.
    /// Partial-height detents keep iOS 26 Liquid Glass; `.large` goes opaque.
    @ViewBuilder
    func bsSystemGlassSheet(
        detents: Set<PresentationDetent> = [.medium, .large]
    ) -> some View {
        if #available(iOS 18.0, *) {
            self
                .containerBackground(.clear, for: .navigation)
                .presentationDetents(detents)
                .presentationDragIndicator(.visible)
        } else {
            self
                .presentationDetents(detents)
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Stage Components

struct BSChromeIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: BSLayout.chromeIconSize, weight: .semibold))
                .foregroundColor(BSColor.textPrimary)
                .frame(width: BSLayout.chromeButtonSize, height: BSLayout.chromeButtonSize)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Toolbar leading close control. Uses the system toolbar icon style so it matches
/// sibling items like the trailing `plus` (same Liquid Glass size, no double chrome).
struct BSChromeToolbarCloseButton: ToolbarContent {
    var accessibilityLabel: String = "关闭"
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: action) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

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

struct BSSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(BSFont.tag)
            .tracking(1.4)
            .foregroundColor(BSColor.textTertiary)
            .textCase(.uppercase)
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
              let image = await ImageCache.shared.image(from: url),
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
struct BSInAppBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

struct BSInAppBrowser: UIViewControllerRepresentable {
    let page: BSInAppBrowserPage

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: page.url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct BSInputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(BSFont.body)
            .foregroundColor(BSColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.border, lineWidth: 1)
            )
    }
}

extension View {
    func bsInputField() -> some View {
        modifier(BSInputFieldStyle())
    }
}

struct BSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BSFont.caption)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.white.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            // Press-scale: 120ms is below the 160ms BSMotion.micro token, but
            // matches DESIGN.md "PrimaryStageAction — 120ms press scale to 0.98"
            // so the press reads as a single physical beat.
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BSFont.caption)
            .foregroundColor(BSColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BSDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BSFont.caption)
            .foregroundColor(BSColor.Stage.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(BSColor.Stage.danger.opacity(configuration.isPressed ? 0.18 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.Stage.danger.opacity(0.30), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - State Surfaces

enum BSToastTone: Equatable {
    case success
    case failure
    case neutral

    var iconName: String {
        switch self {
        case .success: return "checkmark"
        case .failure: return "xmark"
        case .neutral: return "exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .success: return BSColor.Accent.prepare
        case .failure: return BSColor.Accent.danger
        case .neutral: return BSColor.Accent.warm
        }
    }
}

struct BSToastPayload: Identifiable, Equatable {
    let id = UUID()
    let tone: BSToastTone
    let message: String
}

struct BSToast: View {
    let payload: BSToastPayload

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Image(systemName: payload.tone.iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(payload.tone.tint)
                .frame(width: 22, height: 22)
                .background(payload.tone.tint.opacity(0.14))
                .clipShape(Circle())

            Text(payload.message)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.72))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(BSColor.borderProminent, lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func bsToastOverlay(_ payload: BSToastPayload?, bottomPadding: CGFloat = 94) -> some View {
        overlay(alignment: .bottom) {
            if let payload {
                BSToast(payload: payload)
                    .padding(.horizontal, BSSpacing.md)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: payload?.id)
    }
}

struct BSEmptyPanel: View {
    let iconName: String
    let title: String
    let message: String
    var buttonTitle: String?
    var buttonIconName: String?
    var action: (() -> Void)?

    var body: some View {
        BSSurfacePanel {
            VStack(spacing: BSSpacing.md) {
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(BSColor.brandGradientSoft)
                    .accessibilityHidden(true)

                VStack(spacing: BSSpacing.xs) {
                    Text(title)
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let buttonTitle, let action {
                    Button(action: action) {
                        Label(buttonTitle, systemImage: buttonIconName ?? "plus")
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

enum ShowCoverPlaceholderReason: Equatable {
    case noCover
    case loading
    case failed
}

enum ShowCoverFallbackAlignment: Equatable {
    case center

    var swiftUIAlignment: Alignment {
        switch self {
        case .center: .center
        }
    }
}

struct ShowCoverFallbackPresentation: Equatable {
    let assetName: String
    let alignment: ShowCoverFallbackAlignment
    let visibleTexts: [String]

    init(reason: ShowCoverPlaceholderReason) {
        assetName = "default_cover"
        alignment = .center
        visibleTexts = []
    }
}

struct ShowCoverPlaceholderView: View {
    let reason: ShowCoverPlaceholderReason

    private var presentation: ShowCoverFallbackPresentation {
        ShowCoverFallbackPresentation(reason: reason)
    }

    var body: some View {
        ZStack {
            Image(presentation.assetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: presentation.alignment.swiftUIAlignment)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(reason == .loading ? 0.18 : 0.06),
                    Color.black.opacity(reason == .failed ? 0.18 : 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }
}

struct ShowCoverImageView: View {
    let urlString: String?
    var aspectRatio: CGFloat
    var contentMode: ContentMode = .fit
    var alignment: Alignment = .center
    var enforcesAspectRatio = true
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?
    @State private var loadState: LoadState = .idle

    enum LoadState: Equatable {
        case idle, loading, failed
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            } else if loadState == .failed || urlString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                ShowCoverPlaceholderView(reason: loadState == .failed ? .failed : .noCover)
            } else {
                ZStack {
                    ShowCoverPlaceholderView(reason: .loading)
                    ProgressView()
                        .tint(.white.opacity(0.7))
                }
            }
        }
        .modifier(ShowCoverAspectRatioModifier(aspectRatio: aspectRatio, isEnabled: enforcesAspectRatio))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .clipped()
        .accessibilityHidden(true)
        .task(id: urlString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let urlString,
              !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString) else { return }
        loadState = .loading
        image = await ImageCache.shared.image(from: url)
        loadState = image == nil ? .failed : .idle
    }
}

private actor ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(from url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

private struct ShowCoverAspectRatioModifier: ViewModifier {
    let aspectRatio: CGFloat
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            content
        }
    }
}


/// 单头像缩略;库行(28pt)、详情页(40pt)、搜索候选(28pt)共用。
struct ArtistAvatarThumb: View {
    let url: URL?
    var size: CGFloat = 28

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
        } else {
            placeholder
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .regular))
                    .foregroundColor(.white.opacity(0.46))
            )
    }
}

/// 阵容横滑条:现场详情 / 足迹详情共用。头像在上艺名在下,点击跳 Apple Music
/// (识别过的直达艺人页,未识别的按艺名搜索);未识别头像用首字符占位圆。
struct ArtistLineupStrip: View {
    let artists: [ArtistSlot]

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.md) {
                ForEach(Array(artists.enumerated()), id: \.offset) { _, artist in
                    item(artist)
                }
            }
        }
    }

    private func item(_ artist: ArtistSlot) -> some View {
        Button {
            openInAppleMusic(artist)
        } label: {
            VStack(spacing: BSSpacing.xs) {
                avatar(artist)

                Text(artist.name)
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.format("在 Apple Music 中查看 %@", artist.name))
    }

    private func avatar(_ artist: ArtistSlot) -> some View {
        if let urlString = artist.avatarURL,
           let url = URL(string: urlString) {
            return AnyView(ArtistAvatarThumb(url: url, size: 48))
        }
        let initial = String(artist.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
        return AnyView(
            Text(initial.isEmpty ? "?" : initial)
                .font(BSFont.caption.weight(.semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
        )
    }

    private func openInAppleMusic(_ artist: ArtistSlot) {
        if let urlString = artist.appleMusicURL,
           let url = URL(string: urlString) {
            openURL(url)
            return
        }
        var components = URLComponents(string: "https://music.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: artist.name)]
        if let url = components?.url {
            openURL(url)
        }
    }
}

private struct BSDrawerContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct BSDrawerSheet<Content: View>: View {
    let detents: [PresentationDetent]
    let contentInsets: EdgeInsets
    let fitsContent: Bool
    @ViewBuilder let content: Content
    @State private var fittedContentHeight: CGFloat = 300
    @State private var selectedFittedDetent: PresentationDetent = .height(300)
    @State private var contentExceedsAvailableHeight = false

    init(
        detent: PresentationDetent,
        fitsContent: Bool = false,
        contentInsets: EdgeInsets = EdgeInsets(
            top: BSSpacing.md,
            leading: BSSpacing.lg,
            bottom: BSSpacing.xl,
            trailing: BSSpacing.lg
        ),
        @ViewBuilder content: () -> Content
    ) {
        self.detents = [detent]
        self.fitsContent = fitsContent
        self.contentInsets = contentInsets
        self.content = content()
    }

    init(
        detents: [PresentationDetent],
        fitsContent: Bool = false,
        contentInsets: EdgeInsets = EdgeInsets(
            top: BSSpacing.md,
            leading: BSSpacing.lg,
            bottom: BSSpacing.xl,
            trailing: BSSpacing.lg
        ),
        @ViewBuilder content: () -> Content
    ) {
        self.detents = detents
        self.fitsContent = fitsContent
        self.contentInsets = contentInsets
        self.content = content()
    }

    var body: some View {
        Group {
            if fitsContent {
                if contentExceedsAvailableHeight {
                    ScrollView(.vertical, showsIndicators: false) {
                        drawerContent
                    }
                    .frame(maxHeight: maxFittedContentHeight)
                    .presentationDetents(Set(detents).union([.large]))
                } else {
                    drawerContent
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: BSDrawerContentHeightKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                        .onPreferenceChange(BSDrawerContentHeightKey.self) { height in
                            guard height > 0 else { return }
                            let maxHeight = maxFittedContentHeight
                            let fittedHeight = min(max(180, height), maxHeight)
                            contentExceedsAvailableHeight = height > maxHeight
                            fittedContentHeight = fittedHeight
                            selectedFittedDetent = .height(fittedHeight)
                        }
                        .presentationDetents(
                            [.height(fittedContentHeight)],
                            selection: $selectedFittedDetent
                        )
                }
            } else {
                drawerContent
                    .frame(maxHeight: .infinity, alignment: .top)
                    .presentationDetents(Set(detents))
            }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var drawerContent: some View {
        VStack(spacing: BSSpacing.lg) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(contentInsets)
    }

    private var maxFittedContentHeight: CGFloat {
        max(180, UIScreen.main.bounds.height - 120)
    }
}

struct BSProLimitSheet: View {
    let title: String
    let message: String
    var primaryTitle = "开通 Pro"
    var secondaryTitle = "稍后再说"
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    var body: some View {
        BSDrawerSheet(detent: .height(320)) {
            VStack(spacing: BSSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [
                                    BSColor.Accent.violet.opacity(0.20),
                                    BSColor.Accent.warm.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "crown.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(BSColor.brandGradient)
                }
                .frame(width: 58, height: 58)

                VStack(spacing: BSSpacing.xs) {
                    Text(title)
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: BSSpacing.sm) {
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(BSPrimaryButtonStyle())
                Button(secondaryTitle, action: onSecondary)
                    .buttonStyle(BSSecondaryButtonStyle())
            }
        }
    }
}


