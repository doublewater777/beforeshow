import SwiftUI

struct CDPlayerBodySurface: View {
    let configuration: CDPlayerConfiguration
    var extensionHeight: CGFloat = 0

    var body: some View {
        let rect = configuration.geometry.body
        ZStack(alignment: .top) {
            Image(decorative: configuration.assets.body)
                .resizable()
                .brightness(CDPlayerSurfaceTokens.bodyBrightness)
                .opacity(CDPlayerSurfaceTokens.bodyOpacity)
                .frame(width: rect.width, height: rect.height)
            if extensionHeight > 0 {
                // Extend only the faceplate; the tray and hinge retain their geometry.
                let faceplateTop = configuration.geometry.lcd.minY - rect.minY - BSSpacing.sm
                Rectangle().fill(CDPlayerSurfaceTokens.chassisMetal)
                    .frame(height: rect.height + extensionHeight - faceplateTop)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
                    .offset(y: faceplateTop)
            }
        }
            .frame(width: rect.width, height: rect.height + extensionHeight, alignment: .top)
            .background(CDPlayerSurfaceTokens.chassisMetal, in: RoundedRectangle(cornerRadius: CDPlayerSurfaceTokens.chassisCorner))
            .clipShape(RoundedRectangle(cornerRadius: CDPlayerSurfaceTokens.chassisCorner))
            .overlay(RoundedRectangle(cornerRadius: CDPlayerSurfaceTokens.chassisCorner).strokeBorder(.white.opacity(0.09), lineWidth: BSListeningTokens.hairline))
            .position(x: rect.midX, y: rect.midY + extensionHeight / 2)
            .shadow(color: .black.opacity(0.35), radius: BSSpacing.md, y: BSSpacing.sm)
            .allowsHitTesting(false)
    }
}
