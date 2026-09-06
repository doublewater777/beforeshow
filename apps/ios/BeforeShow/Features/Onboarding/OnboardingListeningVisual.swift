import SwiftUI

struct OnboardingListeningVisual: View {
    var body: some View {
        ZStack {
            Circle().fill(BSColor.Stage.accent.opacity(0.1)).blur(radius: BSSpacing.xl)
            Image("listen_01_body_shell").resizable().scaledToFit().padding(BSSpacing.xl)
            Image("listen_02_lid_outer").resizable().scaledToFit()
                .padding(.horizontal, BSSpacing.xl).padding(.bottom, BSSpacing.xl * 2)
        }.accessibilityHidden(true)
    }
}
