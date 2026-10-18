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

extension Notification.Name {
    static let bsDeviceDidShake = Notification.Name("BeforeShow.deviceDidShake")
}

// 摇一摇沿 responder 链传到 window；在这里接收，不占用 first responder，
// 否则会抢走输入框焦点（第一次点击不弹键盘、原生搜索框无法聚焦）。
extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: .bsDeviceDidShake, object: self)
    }
}

struct FeedbackShakeShortcutModifier: ViewModifier {
    @AppStorage(FeedbackShakePreferences.appStorageKey) private var isShakeEnabled = true
    @State private var isShowingFeedback = false
    @State private var toast: BSToastPayload?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .bsDeviceDidShake)) { _ in
                handleShake()
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
            try? await Task.sleep(for: .seconds(2))
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
                            .foregroundStyle(BSColor.Stage.foreground)

                        Text(BSLocalization.text("关闭以禁用"))
                            .font(BSFont.V3.small)
                            .foregroundStyle(BSColor.Stage.muted)
                    }
                }
                .tint(BSColor.Stage.accent)
            }
        }
    }
}
