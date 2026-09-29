import SafariServices
import UIKit
import SwiftUI

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
            // Press-scale springs to 0.96 instead of easing to 0.98: the slight
            // overshoot on release makes the press read as one physical beat.
            // Supersedes DESIGN.md "PrimaryStageAction — 120ms press scale to 0.98".
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: configuration.isPressed)
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
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: configuration.isPressed)
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
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: configuration.isPressed)
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


// MARK: - Swipe Reveal

struct BSSwipeRevealActionRow<Content: View>: View {
    let isRevealed: Bool
    let actionTitle: String
    let actionIcon: String
    let tint: Color
    let onReveal: (Bool) -> Void
    let onAction: () -> Void
    private let content: Content

    @State private var dragTranslation: CGFloat = 0
    @State private var dragAxis: DragAxis?

    private let actionWidth: CGFloat = 92
    private let actionHeight: CGFloat = 80
    private let settleAnimation = Animation.spring(response: 0.24, dampingFraction: 0.90)

    private enum DragAxis {
        case horizontal
        case vertical
    }

    init(
        isRevealed: Bool,
        actionTitle: String,
        actionIcon: String,
        tint: Color,
        onReveal: @escaping (Bool) -> Void,
        onAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isRevealed = isRevealed
        self.actionTitle = actionTitle
        self.actionIcon = actionIcon
        self.tint = tint
        self.onReveal = onReveal
        self.onAction = onAction
        self.content = content()
    }

    private var restingOffset: CGFloat {
        isRevealed ? -actionWidth : 0
    }

    private var rowOffset: CGFloat {
        clampedOffset(restingOffset + dragTranslation)
    }

    private func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(0, max(-actionWidth, offset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                onReveal(false)
                onAction()
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(actionTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundColor(tint)
                .frame(width: actionWidth, height: actionHeight)
                .background(tint.opacity(0.13))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            content
                .offset(x: rowOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if dragAxis == nil {
                                let horizontalDistance = abs(value.translation.width)
                                let verticalDistance = abs(value.translation.height)
                                guard max(horizontalDistance, verticalDistance) >= 4 else {
                                    return
                                }
                                dragAxis = horizontalDistance >= verticalDistance ? .horizontal : .vertical
                            }

                            guard dragAxis == .horizontal else {
                                return
                            }
                            dragTranslation = value.translation.width
                        }
                        .onEnded { value in
                            let endedAxis = dragAxis
                            dragAxis = nil

                            guard endedAxis == .horizontal else {
                                dragTranslation = 0
                                return
                            }

                            let projectedOffset = clampedOffset(
                                restingOffset + value.predictedEndTranslation.width
                            )
                            let shouldReveal = projectedOffset < -(actionWidth * 0.45)

                            withAnimation(settleAnimation) {
                                onReveal(shouldReveal)
                                dragTranslation = 0
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityAction(named: actionTitle) {
            onAction()
        }
    }
}
