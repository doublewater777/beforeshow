import SwiftUI
import UIKit

struct BSSwipeRevealActionRow<Content: View>: View {
    let isRevealed: Bool
    let actionTitle: String
    let actionIcon: String
    let tint: Color
    let onReveal: (Bool) -> Void
    let onAction: () -> Void
    private let content: Content

    @State private var dragTranslation: CGFloat = 0
    @State private var suppressContentTap = false
    @State private var tapReleaseTask: Task<Void, Never>?

    private let actionWidth: CGFloat = 88

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

    private var restingOffset: CGFloat { isRevealed ? -actionWidth : 0 }

    private var rowOffset: CGFloat {
        min(0, max(-actionWidth, restingOffset + dragTranslation))
    }

    private var revealProgress: CGFloat {
        min(1, max(0, -rowOffset / actionWidth))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                onReveal(false)
                onAction()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(tint)
                .frame(width: 72, height: 54)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .opacity(revealProgress)
            .allowsHitTesting(isRevealed && dragTranslation == 0)
            .accessibilityHidden(true)

            ZStack {
                content
                    .disabled(suppressContentTap || isRevealed)
                    .allowsHitTesting(!suppressContentTap && !isRevealed)

                if suppressContentTap || isRevealed {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard isRevealed else { return }
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.90)) {
                                onReveal(false)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .offset(x: rowOffset)
            .modifier(dragGesture)
        }
        .background(BSColor.Stage.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .onDisappear {
            tapReleaseTask?.cancel()
        }
        .accessibilityAction(named: actionTitle) {
            onAction()
        }
    }

    private var dragGesture: some ViewModifier {
        BSHorizontalSwipeModifier(
            onChanged: { translation in
                tapReleaseTask?.cancel()
                suppressContentTap = true
                dragTranslation = translation
            },
            onEnded: { translation, velocity, cancelled in
                let projected = restingOffset + translation + velocity * 0.2
                withAnimation(.spring(response: 0.24, dampingFraction: 0.90)) {
                    if !cancelled {
                        onReveal(projected < -(actionWidth * 0.45))
                    }
                    dragTranslation = 0
                }

                tapReleaseTask?.cancel()
                tapReleaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }
                    suppressContentTap = false
                }
            }
        )
    }
}

/// Reject vertical pans before recognition so the parent scroll view keeps them.
@available(iOS 18, *)
private struct BSHorizontalSwipeGesture: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, Bool) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).x, false)
        case .cancelled, .failed:
            onEnded(translation, 0, true)
        default:
            break
        }
    }
}

private struct BSHorizontalSwipeModifier: ViewModifier {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, Bool) -> Void
    @State private var horizontal: Bool?

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.gesture(BSHorizontalSwipeGesture(onChanged: onChanged, onEnded: onEnded))
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        if horizontal == nil {
                            horizontal = abs(value.translation.width) > abs(value.translation.height)
                        }
                        if horizontal == true { onChanged(value.translation.width) }
                    }
                    .onEnded { value in
                        if horizontal == true {
                            onEnded(value.translation.width, value.velocity.width, false)
                        }
                        horizontal = nil
                    }
            )
            .onDisappear {
                if horizontal == true { onEnded(0, 0, true) }
                horizontal = nil
            }
        }
    }
}
