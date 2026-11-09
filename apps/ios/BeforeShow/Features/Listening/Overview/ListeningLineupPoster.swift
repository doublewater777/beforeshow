import SwiftUI

struct ListeningLineupPoster: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    let onArtist: (ListeningBrowseArtist) -> Void

    private var artists: [ListeningBrowseArtist] {
        var seen = Set<String>()
        return room.browseArtists.sorted { $0.slotIndex < $1.slotIndex }.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let artists = artists
        ListeningPosterLayout(
            show: show,
            fallbackCoverURL: artists.first?.artworkURL,
            names: artists.map { artist in
                ListeningPosterName(id: artist.id, name: artist.name, color: nameColor(artist),
                                    accessibilityID: "listening.overview.artist.\(artist.slotIndex)") { onArtist(artist) }
            },
            expandable: true
        )
    }

    private func nameColor(_ artist: ListeningBrowseArtist) -> Color {
        if !artist.isConnected { return BSColor.Stage.muted }
        return room.track?.artistName == artist.name ? BSColor.Stage.accent : BSColor.Stage.foreground
    }
}

struct ListeningPosterName: Identifiable {
    let id: String
    let name: String
    var color: Color = BSColor.Stage.foreground
    var accessibilityID: String?
    var action: (() -> Void)?
}

/// The show poster: cover behind, lineup set in tiers like a printed festival bill.
struct ListeningPosterLayout: View {
    let show: Show
    var fallbackCoverURL: URL?
    let names: [ListeningPosterName]
    var expandable = false
    @State private var isExpanded = false

    private var coverURL: URL? { show.coverImageURL.flatMap(URL.init(string:)) ?? fallbackCoverURL }

    var body: some View {
        let tiers = ListeningPosterTiers(names, expanded: isExpanded)
        VStack(spacing: BSSpacing.sm) {
            Text(show.name)
                .font(ListeningOverviewStyle.serif(22))
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.85))
                .lineLimit(2)
            Rectangle().fill(BSColor.Stage.foreground.opacity(0.3)).frame(width: 32, height: 1)
            tier(tiers.headliners, font: .system(size: 34, design: .serif), separator: 22)
            tier(tiers.second, font: ListeningOverviewStyle.caps(16), uppercase: true, separator: 14)
            tier(tiers.rest, font: ListeningOverviewStyle.caps(12), uppercase: true, separator: 10, opacity: 0.62)
            if tiers.hasMore, expandable {
                Button {
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: BSSpacing.xs) {
                        Text(isExpanded ? ListeningCopy.text("收起") : ListeningCopy.format("全部 %d 组艺人", names.count))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(ListeningOverviewStyle.badgeGlyph)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, BSSpacing.compact)
                    .frame(height: 32)
                    .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listening.overview.lineup")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSSpacing.xl)
        // The cover stays pinned behind the title; unfolding only lengthens the bill below it.
        // It extends upward behind the page header and into the top safe area so the ambient cover glows through.
        .background(alignment: .top) {
            let headerReach: CGFloat = 200
            // The cover fades out to transparent so it melts into the room's tinted light below.
            Color.clear
                .frame(height: ListeningOverviewStyle.posterHeight + headerReach)
                .overlay { ListeningArtwork(url: coverURL, title: show.name) }
                .clipped()
                .mask {
                    LinearGradient(
                        stops: [.init(color: .black.opacity(0.35), location: 0),
                                .init(color: .black.opacity(0.4), location: headerReach / (ListeningOverviewStyle.posterHeight + headerReach)),
                                .init(color: .black.opacity(0.38), location: (headerReach + 100) / (ListeningOverviewStyle.posterHeight + headerReach)),
                                .init(color: .black.opacity(0.1), location: 0.75),
                                .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .offset(y: -headerReach)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func tier(_ items: [ListeningPosterName], font: Font, uppercase: Bool = false,
                      separator: CGFloat, opacity: Double = 1) -> some View {
        if !items.isEmpty {
            ListeningCenteredFlow(spacing: separator * 0.5, lineSpacing: 2) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: separator * 0.5) {
                        if index > 0 {
                            Text(verbatim: "·").foregroundStyle(BSColor.Stage.foreground.opacity(0.3))
                        }
                        let label = Text(item.name)
                            .textCase(uppercase ? .uppercase : nil)
                            .foregroundStyle(item.color.opacity(opacity))
                            .lineLimit(1)
                        if let action = item.action {
                            Button(action: action) { label }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(item.accessibilityID ?? "")
                        } else {
                            label
                        }
                    }
                    .font(font)
                }
            }
        }
    }
}

/// Wraps names onto centered lines like a printed festival poster.
struct ListeningCenteredFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.midX - line.width / 2
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if added > width, !current.indices.isEmpty {
                lines.append(current)
                current = Line(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = added
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}
