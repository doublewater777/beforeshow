import SwiftUI

/// 分享图署名：当前语言的 App Store 名称（开场前 / 開場前 / BeforeShow），
/// 让看到图的人能直接去 App Store 搜。每张分享卡都放在最后一行的最前面。
struct BSShareByline: View {
    var tone: Color = BSColor.Stage.muted
    var scale: CGFloat = 1

    static var appName: String { BSLocalization.text("开场前 · 分享图署名") }

    var body: some View {
        HStack(spacing: 6 * scale) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 16 * scale, height: 16 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 4 * scale, style: .continuous))
                // The icon is near-black; the edge keeps it an icon on the dark cards.
                .overlay(RoundedRectangle(cornerRadius: 4 * scale, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5 * scale))
            Text(Self.appName)
                .font(.system(size: 11 * scale, weight: .semibold))
                .tracking(0.6 * scale)
                .foregroundStyle(tone)
        }
        .lineLimit(1)
        .fixedSize()
    }
}
