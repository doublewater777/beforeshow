import SwiftUI
import UIKit

/// A screenshot of 当前 before doors floats one small bubble that offers the countdown card with its code. It leaves
/// on its own; nothing opens unless it is tapped.
struct CountdownScreenshotShare: ViewModifier {
    let show: Show?
    /// 当前 is on screen with nothing over it.
    let isVisible: Bool

    @State private var offer: Offer?
    @State private var toast: BSToastPayload?

    private struct Offer: Equatable {
        let id = UUID()
        let show: Show
    }

    static func offers(_ show: Show?, isVisible: Bool, now: Date) -> Bool {
        guard isVisible, let show else { return false }
        return CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: now))
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if let offer {
                    bubble(offer.show)
                        // Trailing, clear of the system's own screenshot thumbnail at the leading corner.
                        .padding(.trailing, BSSpacing.md)
                        .padding(.bottom, BSSpacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .bsToastOverlay(toast, bottomPadding: 90)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: offer)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                guard Self.offers(show, isVisible: isVisible, now: .now), let show else { return }
                offer = Offer(show: show)
            }
            .onChange(of: isVisible) { _, visible in
                if !visible { offer = nil }
            }
            .task(id: offer?.id) {
                guard offer != nil else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                offer = nil
            }
    }

    private func bubble(_ show: Show) -> some View {
        Button {
            offer = nil
            Task { @MainActor in
                let shared = await CountdownShareExport.share(show: show, snapshot: HomeHeroSnapshot(show: show, now: .now))
                guard !shared else { return }
                let payload = BSToastPayload(tone: .failure, message: BSLocalization.text("分享图片生成失败，请重试"))
                toast = payload
                try? await Task.sleep(for: .milliseconds(2200))
                if toast == payload { toast = nil }
            }
        } label: {
            HStack(spacing: BSSpacing.sm) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(width: 22, height: 22)
                Text(BSLocalization.text("分享这场"))
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.textPrimary)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(BSColor.borderProminent, lineWidth: 1))
            .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}
