import SwiftUI

struct HomeLivePulse: View {
    let reduceMotion: Bool
    @State private var rippling = false

    var body: some View {
        Circle()
            .fill(BSColor.Stage.live)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(BSColor.Stage.live.opacity(0.55), lineWidth: 1)
                    .scaleEffect(rippling ? 2.2 : 1)
                    .opacity(rippling ? 0 : 1)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    rippling = true
                }
            }
    }
}
