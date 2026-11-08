import SwiftUI
import UIKit

/// Title + one-line summary in the navigation bar of the newer archive rooms.
struct FootprintArchiveTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.5))
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The selected-item card pinned to the bottom of each room; slides up when the selection changes.
struct FootprintArchiveCard<Content: View>: View {
    var fill: Color = Color(white: 0.086)
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
}

/// One dated show line in a card: tapping opens the show's footprint page.
struct FootprintArchiveShowLine: View {
    let show: Show
    let onOpen: (Show) -> Void

    var body: some View {
        Button { onOpen(show) } label: {
            HStack(spacing: 12) {
                Text(footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.5))
                    .frame(width: 82, alignment: .leading)
                Text(Self.place(show))
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func place(_ show: Show) -> String {
        let place = [show.city, show.venueName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return place.map { "\($0) · \(show.name)" } ?? show.name
    }
}

/// A plain list of the shows behind a number, e.g. 「看你们的 N 场」.
struct FootprintShowListView: View {
    let title: String
    let shows: [Show]
    let archive: FootprintArchiveSnapshot

    @State private var detailTarget: FootprintDetailDestination?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(shows) { show in
                    FootprintArchiveShowLine(show: show) { detailTarget = FootprintDetailDestination(show: $0) }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(16)
            .bsAdaptiveContentWidth()
        }
        .background { FootprintBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: title) } }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
    }
}

/// A photo from the app's media folder, loaded off the main thread.
struct FootprintLocalPhoto: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Color.white.opacity(0.06)
            }
        }
        .bsMaskUserContent()
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
        }
    }
}

extension MerchItem {
    func photoURL(cutout: Bool) -> URL? {
        guard let root = try? ShowAssetMediaLocation.applicationSupport().rootDirectory else { return nil }
        return root.appendingPathComponent(cutout ? (cutoutRelativePath ?? relativePath) : relativePath)
    }
}
