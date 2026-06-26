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
        static let music = Color(red: 1.0, green: 0.70, blue: 0.28)      // amber
        static let travel = Color(red: 0.49, green: 0.81, blue: 1.0)     // cyan
        static let video = Color(red: 0.70, green: 0.53, blue: 1.0)      // purple
        static let candidate = Color(red: 1.0, green: 0.48, blue: 0.72)  // pink
        static let prepare = Color(red: 0.34, green: 0.84, blue: 0.56)   // mint
        static let fragment = Color(red: 1.0, green: 0.42, blue: 0.42)   // coral
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
}

// MARK: - Spacing

enum BSSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Radius

enum BSRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let pill: CGFloat = 999
}

enum BSLayout {
    /// Reserved space above the floating glass tab bar.
    static let floatingTabBarClearance: CGFloat = 108
}

// MARK: - Reusable View Modifiers

extension View {
    /// Standard card treatment: dark surface, large radius, hairline border.
    func bsCard() -> some View {
        self
            .background(BSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.lg)
                    .stroke(BSColor.border, lineWidth: 1)
            )
    }

    /// Splash-style gradient text, used sparingly for hero moments.
    func bsGradientText() -> some View {
        self
            .foregroundStyle(BSColor.brandGradient)
    }
}

// MARK: - Stage Components

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

private struct StageBeam: View {
    let color: Color
    let rotation: Double
    let pulseDuration: TimeInterval
    let pulseDelay: TimeInterval

    @State private var isPulsing = false

    var body: some View {
        LinearGradient(
            colors: [
                color,
                color.opacity(0.45),
                .clear
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(width: 100, height: 420)
        .blur(radius: 8)
        .opacity(isPulsing ? 0.5 : 0.2)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + pulseDelay) {
                withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

struct BSStageScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var bottomPadding: CGFloat = 32
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(BSColor.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        if let subtitle {
                            Text(subtitle)
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textTertiary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    content
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.top, BSSpacing.lg)
                .padding(.bottom, bottomPadding)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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

struct BSFloatingGlassTabBar: View {
    @Binding var selection: BeforeShowTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BeforeShowTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 28, weight: selection == tab ? .semibold : .regular))
                            .symbolVariant(selection == tab ? .fill : .none)
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selection == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.42)))
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Color.white.opacity(0.13))
                                .overlay(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.31, green: 0.82, blue: 0.67).opacity(0.30),
                                                    Color.white.opacity(0.06)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(height: 92)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(BSColor.borderProminent, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.42), radius: 24, x: 0, y: 10)
        }
    }
}

struct CurrentShowAmbientBackground: View {
    let coverImageURL: String?

    var body: some View {
        ZStack {
            Color.black

            ShowCoverImageView(
                urlString: coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                alignment: .center,
                enforcesAspectRatio: false,
                cornerRadius: 0
            )
            .blur(radius: 36)
            .scaleEffect(1.16)
            .saturation(1.12)
            .opacity(0.28)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.72),
                    Color.black.opacity(0.84),
                    Color.black.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct BSGlassPanel<Content: View>: View {
    var padding: CGFloat = BSSpacing.md
    @ViewBuilder var content: Content

    var body: some View {
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
        case .failure: return BSColor.Accent.fragment
        case .neutral: return BSColor.Accent.music
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

struct BSLoadingStatePanel: View {
    let title: String
    let message: String

    var body: some View {
        BSGlassPanel {
            HStack(alignment: .center, spacing: BSSpacing.md) {
                ProgressView()
                    .tint(BSColor.textPrimary)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(title)
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                    Text(message)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        BSGlassPanel {
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
    case top

    var swiftUIAlignment: Alignment {
        switch self {
        case .top: .top
        }
    }
}

struct ShowCoverFallbackPresentation: Equatable {
    let assetName: String
    let alignment: ShowCoverFallbackAlignment
    let visibleTexts: [String]

    init(reason: ShowCoverPlaceholderReason) {
        assetName = "splash_bg"
        alignment = .top
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

struct ArtistAvatarStackView: View {
    let urls: [String]
    var size: CGFloat = 32

    private var displayURLs: [String] {
        Array(urls
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(5))
    }

    var body: some View {
        if !displayURLs.isEmpty {
            HStack(spacing: -8) {
                ForEach(Array(displayURLs.enumerated()), id: \.offset) { _, urlString in
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: size * 0.38, weight: .regular))
                                            .foregroundColor(.white.opacity(0.46))
                                    )
                            }
                        }
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }
}

struct BSDrawerSheet<Content: View>: View {
    let detent: PresentationDetent
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: BSSpacing.lg) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 42, height: 4)

            content
        }
        .padding(.horizontal, BSSpacing.lg)
        .padding(.top, BSSpacing.md)
        .padding(.bottom, BSSpacing.xl)
        .presentationDetents([detent])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .background(Color.black)
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
                                    BSColor.Accent.video.opacity(0.20),
                                    BSColor.Accent.music.opacity(0.20)
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

struct BSDangerConfirmationSheet: View {
    let title: String
    let message: String
    let destructiveTitle: String
    var cancelTitle = "取消"
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(292)) {
            VStack(spacing: BSSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(BSColor.Accent.fragment)
                    .frame(width: 58, height: 58)
                    .background(BSColor.Accent.fragment.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

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

            HStack(spacing: BSSpacing.sm) {
                Button(cancelTitle, action: onCancel)
                    .buttonStyle(BSSecondaryButtonStyle())
                Button(destructiveTitle, action: onConfirm)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Accent.fragment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(BSColor.Accent.fragment.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.Accent.fragment.opacity(0.30), lineWidth: 1)
                    )
            }
        }
    }
}
