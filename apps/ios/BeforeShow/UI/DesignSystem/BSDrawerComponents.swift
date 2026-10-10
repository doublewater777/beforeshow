import SafariServices
import UIKit
import SwiftUI

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
    @State private var measuredContentHeight: CGFloat = 0
    @State private var windowHeight: CGFloat?

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
                            measuredContentHeight = height
                            updateFittedContentHeight()
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
        .background {
            BSDrawerWindowHeightReader { windowHeight = $0 }
        }
        .onChange(of: windowHeight) { updateFittedContentHeight() }
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
        max(180, (windowHeight ?? .infinity) - 120)
    }

    private func updateFittedContentHeight() {
        guard fitsContent, measuredContentHeight > 0 else { return }
        let maxHeight = maxFittedContentHeight
        let fittedHeight = min(max(180, measuredContentHeight), maxHeight)
        contentExceedsAvailableHeight = measuredContentHeight > maxHeight
        fittedContentHeight = fittedHeight
        selectedFittedDetent = .height(fittedHeight)
    }
}

private struct BSDrawerWindowHeightReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> WindowHeightView {
        let view = WindowHeightView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: WindowHeightView, context: Context) {
        uiView.onChange = onChange
    }

    final class WindowHeightView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var lastHeight: CGFloat?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportWindowHeight()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportWindowHeight()
        }

        private func reportWindowHeight() {
            guard let height = window?.bounds.height, height != lastHeight else { return }
            lastHeight = height
            Task { @MainActor in onChange?(height) }
        }
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
