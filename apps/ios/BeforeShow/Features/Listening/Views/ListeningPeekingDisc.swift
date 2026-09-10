import SwiftUI

/// High-precision physical holographic CD disc peeking from an album sleeve jacket.
struct ListeningPeekingDisc: View {
    let disc: ListeningDisc
    var size: CGFloat = 68
    @State private var centerImage: UIImage?

    init(disc: ListeningDisc, size: CGFloat = 68) {
        self.disc = disc
        self.size = size
        _centerImage = State(initialValue: disc.artworkURL.flatMap { ShowCoverImageCache.shared.memoryImage(for: $0) })
    }

    var body: some View {
        ZStack {
            // Holographic rainbow optical diffraction
            AngularGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.70, green: 0.74, blue: 0.79),
                    Color(red: 0.90, green: 0.93, blue: 0.98),
                    BSColor.Stage.accent,
                    Color(red: 0.43, green: 0.77, blue: 0.85),
                    Color(red: 0.73, green: 0.56, blue: 0.94),
                    Color(red: 0.88, green: 0.91, blue: 0.96),
                    BSColor.Stage.accent,
                    Color(red: 0.41, green: 0.75, blue: 0.82),
                    Color(red: 0.64, green: 0.47, blue: 0.84),
                    Color(red: 0.70, green: 0.74, blue: 0.79)
                ]),
                center: .center,
                angle: .degrees(35)
            )
            .clipShape(Circle())

            // Concentric data grooves
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: size * 0.20)
                .padding(size * 0.12)

            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: size * 0.08)
                .padding(size * 0.26)

            // Spindle hub ring
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                .frame(width: size * 0.28, height: size * 0.28)

            Circle()
                .fill(Color(white: 0.08))
                .frame(width: size * 0.18, height: size * 0.18)

            // Center disc artwork label or metallic spindle hub
            if let centerImage {
                Image(uiImage: centerImage)
                    .resizable().scaledToFill()
                    .frame(width: size * 0.38, height: size * 0.38)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.75))
            } else {
                Circle()
                    .stroke(BSColor.Stage.accent.opacity(0.45), lineWidth: 1)
                    .frame(width: size * 0.32, height: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.65), radius: 5, x: -2, y: 3)
        .accessibilityHidden(true)
        .task(id: disc.artworkURL) {
            guard let url = disc.artworkURL else { centerImage = nil; return }
            if centerImage == nil {
                centerImage = ShowCoverImageCache.shared.memoryImage(for: url)
            }
            if centerImage == nil {
                let loaded = await ShowCoverImageCache.shared.image(from: url)
                guard !Task.isCancelled else { return }
                centerImage = loaded
            }
        }
    }
}

