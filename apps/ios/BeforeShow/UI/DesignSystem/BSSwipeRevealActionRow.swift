import SwiftUI

struct BSSwipeRevealActionRow<Content: View>: View {
    let isRevealed: Bool
    let actionTitle: String
    let actionIcon: String
    let tint: Color
    let onReveal: (Bool) -> Void
    let onAction: () -> Void
    private let content: Content

    @State private var dragTranslation: CGFloat = 0
    @State private var horizontalDrag: Bool?
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
                .foregroundColor(tint)
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
            .offset(x: rowOffset)
            .simultaneousGesture(dragGesture)
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if horizontalDrag == nil {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard max(horizontal, vertical) >= 4 else { return }
                    horizontalDrag = horizontal >= vertical
                    if horizontalDrag == true {
                        tapReleaseTask?.cancel()
                        suppressContentTap = true
                    }
                }

                guard horizontalDrag == true else { return }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                let wasHorizontal = horizontalDrag == true
                horizontalDrag = nil

                guard wasHorizontal else {
                    dragTranslation = 0
                    return
                }

                let projected = restingOffset + value.predictedEndTranslation.width
                withAnimation(.spring(response: 0.24, dampingFraction: 0.90)) {
                    onReveal(projected < -(actionWidth * 0.45))
                    dragTranslation = 0
                }

                tapReleaseTask?.cancel()
                tapReleaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }
                    suppressContentTap = false
                }
            }
    }
}
