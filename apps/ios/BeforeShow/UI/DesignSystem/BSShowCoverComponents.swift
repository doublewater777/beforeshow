import SafariServices
import UIKit
import SwiftUI

struct BSEmptyPanel: View {
    let iconName: String
    let title: String
    let message: String
    var buttonTitle: String?
    var buttonIconName: String?
    var action: (() -> Void)?

    var body: some View {
        BSSurfacePanel {
            VStack(spacing: BSSpacing.md) {
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(BSColor.brandGradientSoft)
                    .accessibilityHidden(true)

                VStack(spacing: BSSpacing.xs) {
                    Text(title)
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let buttonTitle, let action {
                    Button(action: action) {
                        Label(buttonTitle, systemImage: buttonIconName ?? "plus")
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

enum ShowCoverPlaceholderReason: Equatable {
    case noCover
    case loading
    case failed
}

enum ShowCoverFallbackAlignment: Equatable {
    case center

    var swiftUIAlignment: Alignment {
        switch self {
        case .center: .center
        }
    }
}

struct ShowCoverFallbackPresentation: Equatable {
    let assetName: String
    let alignment: ShowCoverFallbackAlignment
    let visibleTexts: [String]

    init(reason: ShowCoverPlaceholderReason) {
        assetName = "default_cover"
        alignment = .center
        visibleTexts = []
    }
}

struct ShowCoverPlaceholderView: View {
    let reason: ShowCoverPlaceholderReason

    private var presentation: ShowCoverFallbackPresentation {
        ShowCoverFallbackPresentation(reason: reason)
    }

    var body: some View {
        ZStack {
            Image(presentation.assetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: presentation.alignment.swiftUIAlignment)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(reason == .loading ? 0.18 : 0.06),
                    Color.black.opacity(reason == .failed ? 0.18 : 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }
}

struct ShowCoverImageView: View {
    let urlString: String?
    var aspectRatio: CGFloat
    var contentMode: ContentMode = .fit
    var alignment: Alignment = .center
    var enforcesAspectRatio = true
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?
    @State private var loadState: LoadState = .idle

    enum LoadState: Equatable {
        case idle, loading, failed
    }

    init(
        urlString: String?,
        aspectRatio: CGFloat,
        contentMode: ContentMode = .fit,
        alignment: Alignment = .center,
        enforcesAspectRatio: Bool = true,
        cornerRadius: CGFloat = 8
    ) {
        self.urlString = urlString
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.alignment = alignment
        self.enforcesAspectRatio = enforcesAspectRatio
        self.cornerRadius = cornerRadius
        _image = State(initialValue: Self.persistedImage(for: urlString))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            } else if loadState == .failed || urlString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                ShowCoverPlaceholderView(reason: loadState == .failed ? .failed : .noCover)
            } else {
                ZStack {
                    ShowCoverPlaceholderView(reason: .loading)
                    ProgressView()
                        .tint(.white.opacity(0.7))
                }
            }
        }
        .modifier(ShowCoverAspectRatioModifier(aspectRatio: aspectRatio, isEnabled: enforcesAspectRatio))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .clipped()
        .accessibilityHidden(true)
        .task(id: urlString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let urlString,
              !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString) else { return }
        loadState = .loading
        let loadedImage = await ShowCoverImageCache.shared.image(from: url)
        guard !Task.isCancelled else { return }
        image = loadedImage
        loadState = image == nil ? .failed : .idle
    }

    private static func persistedImage(for urlString: String?) -> UIImage? {
        // Sync memory-only lookup. Disk + widget cache + network are handled
        // by `loadImage()` in the body `.task`, off the main thread.
        guard let urlString,
              let url = URL(string: urlString) else { return nil }
        return ShowCoverImageCache.shared.memoryImage(for: url)
    }
}

actor ShowCoverImageCache {
    typealias FetchData = @Sendable (URL) async -> Data?

    static let shared = ShowCoverImageCache()
    /// NSCache is documented thread-safe, so the actor does not need to
    /// mediate memory hits. `nonisolated(unsafe)` lets Views call the sync
    /// memory lookup from `.init` without hopping the actor.
    private nonisolated(unsafe) let memory = NSCache<NSURL, UIImage>()
    private let diskCache: ShowCoverDiskCache
    private let fetchData: FetchData

    init(
        directoryURL: URL = ShowCoverDiskCache.application.directoryURL,
        fetchData: @escaping FetchData = { url in
            try? await URLSession.shared.data(from: url).0
        }
    ) {
        diskCache = ShowCoverDiskCache(directoryURL: directoryURL)
        self.fetchData = fetchData
    }

    /// Synchronous memory lookup. Safe to call from any context, including
    /// SwiftUI `View.init` and `body`. Returns nil on miss; callers should
    /// fall through to `image(from:)` inside a `.task` to fill the disk /
    /// network path off the main thread.
    nonisolated func memoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(from url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let image = await readDisk(for: url) {
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        if let data = await fetchData(url),
           let image = UIImage(data: data) {
            await writeDisk(data, for: url)
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        return await readWidgetCache(for: url)
    }

    /// Disk read runs off the actor's executor so a slow filesystem does
    /// not block other callers queueing on this actor.
    private func readDisk(for url: URL) async -> UIImage? {
        let cache = diskCache
        return await Task.detached(priority: .userInitiated) {
            cache.image(from: url)
        }.value
    }

    private func readWidgetCache(for url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let path = WidgetCoverCache.cachedCoverPath(matching: url.absoluteString) else {
                return nil
            }
            return UIImage(contentsOfFile: path)
        }.value
    }

    private func writeDisk(_ data: Data, for url: URL) async {
        let cache = diskCache
        await Task.detached(priority: .utility) {
            cache.store(data, for: url)
        }.value
    }
}

struct ShowCoverDiskCache: Sendable {
    let directoryURL: URL

    static var application: ShowCoverDiskCache {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ShowCoverDiskCache(
            directoryURL: cachesURL.appendingPathComponent("ShowCovers", isDirectory: true)
        )
    }

    func image(from sourceURL: URL) -> UIImage? {
        let fileURL = sourceURL.isFileURL ? sourceURL : cachedFileURL(for: sourceURL)
        return UIImage(contentsOfFile: fileURL.path)
    }

    func store(_ data: Data, for sourceURL: URL) {
        guard !sourceURL.isFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: cachedFileURL(for: sourceURL), options: .atomic)
        } catch {
            #if DEBUG
            print("[ShowCoverDiskCache] store failed: \(error)")
            #endif
        }
    }

    private func cachedFileURL(for sourceURL: URL) -> URL {
        directoryURL.appendingPathComponent(
            WidgetCoverCache.filename(for: sourceURL.absoluteString),
            isDirectory: false
        )
    }
}

private struct ShowCoverAspectRatioModifier: ViewModifier {
    let aspectRatio: CGFloat
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            content
        }
    }
}


/// 单头像缩略;库行(28pt)、详情页(40pt)、搜索候选(28pt)共用。
