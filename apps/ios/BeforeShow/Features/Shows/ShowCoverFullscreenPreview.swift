import SwiftUI

struct ShowCoverFullscreenPreview: View {
    let urlString: String?

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        BSFullscreenImageViewer(pageCount: 1, currentIndex: $page) { _ in
            if let url = Self.coverURL(urlString) {
                BSZoomableImagePage(source: .cover(url), onSingleTap: { dismiss() })
            } else {
                ShowCoverImageView(
                    urlString: nil,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fit,
                    enforcesAspectRatio: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, BSSpacing.roomy)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            }
        }
    }

    private static func coverURL(_ urlString: String?) -> URL? {
        urlString.flatMap(URL.init(string:))
    }
}
