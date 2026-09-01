import SafariServices
import UIKit
import SwiftUI

extension View {
    /// Scroll-linked reveal for modules entering the viewport.
    @ViewBuilder
    func bsScrollReveal(reduceMotion: Bool) -> some View {
        bsScrollReveal(reduceMotion: reduceMotion, delay: 0)
    }

    @ViewBuilder
    func bsScrollReveal(reduceMotion: Bool, delay: TimeInterval) -> some View {
        if reduceMotion {
            self
        } else {
            self.scrollTransition(.animated(.easeOut(duration: BSMotion.interface).delay(delay))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.72)
                    .offset(y: phase.isIdentity ? 0 : 18)
            }
        }
    }

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

/// SwiftUI's NavigationStack does not engage `interactivePopGestureRecognizer` once
/// `.toolbar(.hidden, for: .navigationBar)` hides the system bar, so the left-edge
/// back-swipe does nothing. This fallback is kept for legacy screens that still draw
/// their own navigation bar; new push destinations should use the system bar instead.

struct BSNavigationBackSwipeRestorer: UIViewControllerRepresentable {
    let onBack: () -> Void

    func makeUIViewController(context: Context) -> BSNavigationBackSwipeController {
        BSNavigationBackSwipeController(onBack: onBack)
    }

    func updateUIViewController(_ uiViewController: BSNavigationBackSwipeController, context: Context) {
        uiViewController.onBack = onBack
    }
}

final class BSNavigationBackSwipeController: UIViewController {
    var onBack: (() -> Void)?

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let recognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan))
        recognizer.edges = .left
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
    }

    @objc private func handleEdgePan(_ g: UIScreenEdgePanGestureRecognizer) {
        guard g.state == .ended, let onBack else { return }
        let translation = g.translation(in: view)
        let velocity = g.velocity(in: view)
        guard translation.x > 60 || velocity.x > 400 else { return }
        onBack()
    }
}

extension BSNavigationBackSwipeController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
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
