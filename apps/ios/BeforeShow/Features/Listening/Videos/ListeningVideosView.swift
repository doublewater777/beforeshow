import SwiftUI

enum ListeningSurface: Hashable {
    case listen
    case watch
}

/// Lineup artists in show order, each with their first set when a timetable exists.
struct ListeningVideoLineup: Equatable {
    struct Artist: Equatable, Identifiable {
        let name: String
        let set: ListeningShowInputs.Stage.Set?
        let stageName: String?
        var id: String { name }
    }

    let artists: [Artist]

    init(_ inputs: ListeningShowInputs) {
        var firstSet: [String: (ListeningShowInputs.Stage.Set, String)] = [:]
        for stage in inputs.stages {
            for set in stage.sets where firstSet[set.name].map({ set.start < $0.0.start }) ?? true {
                firstSet[set.name] = (set, stage.name)
            }
        }
        let names = inputs.artists.map(\.name)
            + inputs.stages.flatMap(\.sets).sorted { $0.start < $1.start }.map(\.name)
        var seen: Set<String> = []
        artists = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { Artist(name: $0, set: firstSet[$0]?.0, stageName: firstSet[$0]?.1) }
    }
}

struct ListeningVideosView: View {
    let lineup: ListeningVideoLineup
    @State private var filter: String?
    @State private var library = ListeningVideoLibrary()

    /// "All" hides artists Bilibili has nothing for; a single artist still says so.
    private var visibleArtists: [ListeningVideoLineup.Artist] {
        guard let filter else {
            return lineup.artists.filter { artist in
                if case .success(let videos) = library.results[artist.name] { return !videos.isEmpty }
                return true
            }
        }
        return lineup.artists.filter { $0.name == filter }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: BSSpacing.lg) {
                if lineup.artists.count > 1 { chips }
                ForEach(visibleArtists) { artist in
                    section(artist)
                }
                Text(ListeningCopy.text("视频来自哔哩哔哩"))
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                    .padding(.horizontal, BSSpacing.roomy)
            }
            .padding(.top, BSSpacing.sm)
            .padding(.bottom, 120)
        }
        .task(id: lineup) { await library.loadAll(lineup.artists.map(\.name)) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.sm) {
                chip(ListeningCopy.text("全部"), selected: filter == nil) { filter = nil }
                ForEach(lineup.artists) { artist in
                    chip(artist.name, selected: filter == artist.name) { filter = artist.name }
                }
            }
            .padding(.horizontal, BSSpacing.roomy)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? BSColor.Stage.background : BSColor.Stage.foreground)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(selected ? BSColor.Stage.foreground : .clear, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : BSColor.Stage.border, lineWidth: 1))
        }
        .buttonStyle(BSListeningPressStyle())
    }

    @ViewBuilder
    private func section(_ artist: ListeningVideoLineup.Artist) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(artist.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: BSSpacing.sm)
                if let set = artist.set {
                    Text(setLabel(set, stage: artist.stageName))
                        .font(BSListeningTokens.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
            .padding(.horizontal, BSSpacing.roomy)

            switch library.results[artist.name] {
            case .success(let videos) where !videos.isEmpty:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: BSSpacing.compact) {
                        ForEach(videos) { video in
                            Button {
                                ListeningVideoDock.shared.open(
                                    ListeningVideoSelection(artist: artist.name, video: video, related: videos)
                                )
                            } label: {
                                ListeningVideoCard(video: video)
                            }
                            .buttonStyle(BSListeningPressStyle(scale: 0.97))
                        }
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                }
            case .success:
                status(ListeningCopy.text("没有找到相关视频"))
            case .failure:
                Button {
                    Task { await library.load(artist.name) }
                } label: {
                    status(ListeningCopy.text("暂时无法载入视频，点按重试"))
                }
                .buttonStyle(.plain)
            case nil:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BSSpacing.compact) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: BSRadius.sm + 2)
                                .fill(BSColor.Stage.surface)
                                .frame(width: ListeningVideoCard.width, height: ListeningVideoCard.width * 9 / 16)
                        }
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                }
                .disabled(true)
            }
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(BSListeningTokens.caption)
            .foregroundStyle(BSColor.Stage.muted)
            .padding(.horizontal, BSSpacing.roomy)
    }

    private func setLabel(_ set: ListeningShowInputs.Stage.Set, stage: String?) -> String {
        let time = set.start.formatted(date: .omitted, time: .shortened)
        guard let stage, !stage.isEmpty else { return time }
        return "\(time) · \(stage)"
    }
}

struct ListeningVideoSelection: Equatable {
    let artist: String
    var video: ArtistVideo
    let related: [ArtistVideo]
}

struct ListeningVideoCard: View {
    static let width: CGFloat = 240
    let video: ArtistVideo
    var width: CGFloat = Self.width

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ListeningVideoThumbnail(video: video)
                .frame(width: width, height: width * 9 / 16)
                .padding(.bottom, BSSpacing.xs + 2)
            Text(video.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(ListeningVideoFormat.byline(video))
                .font(BSListeningTokens.caption)
                .foregroundStyle(BSColor.Stage.muted)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}

struct ListeningVideoThumbnail: View {
    let video: ArtistVideo
    var showsDuration = true

    var body: some View {
        Color(BSColor.Stage.surface)
            .overlay {
                AsyncImage(url: video.coverURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsDuration { duration }
            }
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm + 2))
    }

    private var duration: some View {
        Text(video.duration)
            .font(.system(size: 11, design: .monospaced))
            .fixedSize()
            .foregroundStyle(BSColor.Stage.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .padding(BSSpacing.sm)
    }
}

enum ListeningVideoFormat {
    static func byline(_ video: ArtistVideo) -> String {
        "\(video.author) · \(ListeningCopy.format("%@ 次播放", plays(video.playCount)))"
    }

    static func plays(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}
