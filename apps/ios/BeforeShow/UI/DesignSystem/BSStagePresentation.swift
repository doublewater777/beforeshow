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
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)

            Text(subtitle)
                .font(BSFont.caption)
                .foregroundStyle(BSColor.Stage.muted)
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
                            .foregroundStyle(BSColor.textPrimary)
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
                                            .foregroundStyle(BSColor.textPrimary)
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
            .foregroundStyle(BSColor.textTertiary)
            .lineLimit(2)
    }
}

/// The 当前 page's backdrop: the dark of the house around the stage, with the evening's weather
/// tinting the sky above it. The stage brings its own light, so nothing here glows from the cover;
/// pulling past the top just shows more of the room.
struct CurrentShowAmbientBackground: View {
    var weatherTone: WeatherAtmosphereTone? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.024, green: 0.02, blue: 0.02), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            // 远景天气天际层 (WeatherSky)
            if let weatherTone, weatherTone != .neutral {
                weatherSkyBackdrop(for: weatherTone)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: weatherTone)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func weatherSkyBackdrop(for tone: WeatherAtmosphereTone) -> some View {
        switch tone {
        case .sunsetGold:
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.22, green: 0.10, blue: 0.05).opacity(0.85), location: 0.0),
                    .init(color: Color(red: 0.12, green: 0.05, blue: 0.07).opacity(0.45), location: 0.45),
                    .init(color: Color.clear, location: 0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .rainBlue:
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.05, green: 0.11, blue: 0.18).opacity(0.90), location: 0.0),
                    .init(color: Color(red: 0.03, green: 0.07, blue: 0.12).opacity(0.50), location: 0.45),
                    .init(color: Color.clear, location: 0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .coldNightIndigo:
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.06, green: 0.06, blue: 0.18).opacity(0.90), location: 0.0),
                    .init(color: Color(red: 0.03, green: 0.04, blue: 0.10).opacity(0.50), location: 0.45),
                    .init(color: Color.clear, location: 0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .neutral:
            EmptyView()
        }
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
