import SafariServices
import UIKit
import SwiftUI

struct ArtistAvatarThumb: View {
    let url: URL?
    var size: CGFloat = 28
    @State private var image: UIImage?

    init(url: URL?, size: CGFloat = 28) {
        self.url = url
        self.size = size
        _image = State(initialValue: url.flatMap { ShowCoverImageCache.shared.memoryImage(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = ShowCoverImageCache.shared.memoryImage(for: url)
            if image == nil {
                let loaded = await ShowCoverImageCache.shared.image(from: url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .regular))
                    .foregroundStyle(.white.opacity(0.46))
            )
    }
}
