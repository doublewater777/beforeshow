import Foundation
import SwiftUI
import UIKit

enum FeedbackShakePreferences {
    static let appStorageKey = "feedbackShakeEnabled"
}

enum FeedbackShakePresentationPolicy {
    static func shouldPresent(
        isShakeEnabled: Bool,
        isFeedbackPresented: Bool,
        hasPresentedModal: Bool
    ) -> Bool {
        isShakeEnabled && !isFeedbackPresented && !hasPresentedModal
    }
}

@MainActor
enum FeedbackShakePresentationState {
    static var hasPresentedModal: Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return true
        }
        return root.presentedViewController != nil
    }
}

struct FeedbackShakeResponder: UIViewRepresentable {
    let isArmed: Bool
    let onShake: @MainActor () -> Void

    func makeUIView(context: Context) -> FeedbackShakeResponderView {
        let view = FeedbackShakeResponderView()
        view.onShake = onShake
        view.setArmed(isArmed)
        return view
    }

    func updateUIView(_ uiView: FeedbackShakeResponderView, context: Context) {
        uiView.onShake = onShake
        uiView.setArmed(isArmed)
    }
}

@MainActor
final class FeedbackShakeResponderView: UIView {
    var onShake: @MainActor () -> Void = {}
    private var isArmed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        observeKeyboard()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeKeyboard()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeFirstResponder: Bool { isArmed }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        rearmIfNeeded()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard isArmed, motion == .motionShake else { return }
        onShake()
    }

    func setArmed(_ armed: Bool) {
        guard isArmed != armed else { return }
        isArmed = armed
        if armed {
            rearmIfNeeded()
        } else if isFirstResponder {
            resignFirstResponder()
        }
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
    }

    @objc
    private func keyboardDidHide() {
        rearmIfNeeded()
    }

    private func rearmIfNeeded() {
        guard isArmed, window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isArmed, self.window != nil, !self.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }
}

struct FeedbackShakeShortcutModifier: ViewModifier {
    @AppStorage(FeedbackShakePreferences.appStorageKey) private var isShakeEnabled = true
    @State private var isShowingFeedback = false
    @State private var toast: BSToastPayload?

    func body(content: Content) -> some View {
        content
            .background {
                FeedbackShakeResponder(
                    isArmed: isShakeEnabled && !isShowingFeedback,
                    onShake: handleShake
                )
                .frame(width: 0, height: 0)
            }
            .sheet(isPresented: $isShowingFeedback) {
                FeedbackShakeSheet {
                    presentToast(BSLocalization.text("已收到，谢谢你的反馈"))
                }
            }
            .bsToastOverlay(toast, bottomPadding: 100)
    }

    private func presentToast(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == payload { toast = nil }
        }
    }

    @MainActor
    private func handleShake() {
        guard FeedbackShakePresentationPolicy.shouldPresent(
            isShakeEnabled: isShakeEnabled,
            isFeedbackPresented: isShowingFeedback,
            hasPresentedModal: FeedbackShakePresentationState.hasPresentedModal
        ) else { return }
        isShowingFeedback = true
    }
}

private struct FeedbackShakeSheet: View {
    var onSubmitted: (() -> Void)? = nil
    @AppStorage(FeedbackShakePreferences.appStorageKey) private var isShakeEnabled = true
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingForm = false

    var body: some View {
        if isShowingForm {
            NavigationStack {
                FeedbackView {
                    dismiss()
                    onSubmitted?()
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        } else {
            BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
                BSStageSheetHeader(
                    icon: "exclamationmark.bubble",
                    title: BSLocalization.text("遇到问题？"),
                    subtitle: BSLocalization.text("有问题或建议，都可以告诉我们。")
                )

                Button {
                    isShowingForm = true
                } label: {
                    Label(
                        BSLocalization.text("提交反馈"),
                        systemImage: "paperplane.fill"
                    )
                }
                .buttonStyle(BSPrimaryButtonStyle())

                Divider()
                    .overlay(BSColor.Stage.border)

                Toggle(isOn: $isShakeEnabled) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(BSLocalization.text("晃动 iPhone 打开反馈"))
                            .font(BSFont.V3.body.weight(.semibold))
                            .foregroundColor(BSColor.Stage.foreground)

                        Text(BSLocalization.text("关闭以禁用"))
                            .font(BSFont.V3.small)
                            .foregroundColor(BSColor.Stage.muted)
                    }
                }
                .tint(BSColor.Stage.accent)
            }
        }
    }
}
