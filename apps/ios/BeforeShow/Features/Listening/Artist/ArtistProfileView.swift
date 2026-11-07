import SwiftData
import SwiftUI

/// The one artist page every artist tap opens: releases, shuffle, play, and the way out to Apple Music.
/// Push it inside a NavigationStack; `ArtistProfileSheet` wraps it for surfaces without one.
struct ArtistProfileView: View {
    let reference: ArtistReference
    var show: Show?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var model: ArtistProfileModel
    @State private var room: ListeningRoomCoordinator?

    init(reference: ArtistReference, show: Show? = nil) {
        self.reference = reference
        self.show = show
        _model = State(initialValue: ArtistProfileModel(reference: reference))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: BSSpacing.xl) {
                hero
                content
                appleMusicLink
            }
            .padding(.bottom, BSSpacing.xl)
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .foregroundStyle(BSColor.Stage.foreground)
        .task(id: reference) {
            await model.load(in: modelContext)
            room = await ListeningIntentHandler.shared.roomForPlayback()
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ListeningArtwork(url: model.artworkURL, title: reference.name)
                .frame(height: ListeningOverviewStyle.artistHeroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, BSColor.Stage.background], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: BSSpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reference.name)
                        .font(ListeningOverviewStyle.serif(44))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if !model.genres.isEmpty {
                        Text(model.genres.prefix(2).joined(separator: " · "))
                            .font(BSListeningTokens.caption)
                            .foregroundStyle(BSColor.Stage.muted)
                    }
                }
                Spacer(minLength: 0)
                if !model.releases.isEmpty, let room { shuffleButton(room) }
            }
            .padding(.horizontal, BSSpacing.roomy)
        }
        .frame(height: ListeningOverviewStyle.artistHeroHeight)
    }

    private func shuffleButton(_ room: ListeningRoomCoordinator) -> some View {
        let isOn = room.isShuffling(reference.id)
        return Button {
            room.shuffleDiscography(of: reference.id, discs: model.releases)
        } label: {
            Label(BSLocalization.text(isOn ? "换一张" : "随机播放"), systemImage: isOn ? "waveform" : "shuffle")
                .font(ListeningOverviewStyle.buttonLabel)
                .foregroundStyle(BSColor.Stage.background)
                .padding(.horizontal, BSSpacing.md)
                .frame(height: ListeningOverviewStyle.pillHeight)
                .background(Capsule().fill(BSColor.Stage.foreground))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .accessibilityIdentifier("artist.shuffle")
    }

    // MARK: Releases

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .loading:
            ProgressView().tint(BSColor.Stage.foreground).frame(maxWidth: .infinity)
        case .unmatched:
            note(BSLocalization.text("还没关联 Apple Music，暂时没有可听的唱片"))
        case .needsAccess:
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                note(BSLocalization.text("允许访问 Apple Music 后可以在这里听这位艺人"))
                Button(BSLocalization.text("允许访问")) {
                    Task { await model.requestAccess(in: modelContext) }
                }
                .font(ListeningOverviewStyle.buttonLabel)
                .padding(.horizontal, BSSpacing.roomy)
            }
        case .failed:
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                note(BSLocalization.text("暂时没有找到可翻的唱片"))
                Button(BSLocalization.text("重试")) {
                    Task { await model.load(in: modelContext) }
                }
                .font(ListeningOverviewStyle.buttonLabel)
                .padding(.horizontal, BSSpacing.roomy)
            }
        case .ready:
            let featured = ListeningArtistReleases.featured(model.releases)
            let rest = model.releases.filter { $0.id != featured?.id }
            if let featured { latest(featured) }
            shelf(ListeningDiscPickFilter.albums.title, rest.filter(ListeningDiscPickFilter.albums.includes))
            shelf(ListeningDiscPickFilter.singlesAndEPs.title, rest.filter(ListeningDiscPickFilter.singlesAndEPs.includes))
            if model.releases.isEmpty {
                note(BSLocalization.text("暂时没有找到可翻的唱片"))
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(ListeningOverviewStyle.meta)
            .foregroundStyle(BSColor.Stage.muted)
            .padding(.horizontal, BSSpacing.roomy)
    }

    private func latest(_ disc: ListeningDisc) -> some View {
        HStack(alignment: .bottom, spacing: BSSpacing.md) {
            discLink(disc) {
                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: ListeningOverviewStyle.featuredCover, height: ListeningOverviewStyle.featuredCover)
            }
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(disc.title).font(ListeningOverviewStyle.serif(24)).lineLimit(2)
                Text(ListeningReleaseMeta.yearAndTrackCount(disc))
                    .font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
                if let room {
                    Button { room.play(disc) } label: {
                        Label(BSLocalization.text("播放"), systemImage: room.isOnDeckAndPlaying(disc) ? "waveform" : "play.fill")
                            .font(ListeningOverviewStyle.buttonLabel)
                            .foregroundStyle(BSColor.Stage.background)
                            .padding(.horizontal, BSSpacing.md)
                            .frame(height: ListeningOverviewStyle.pillHeight)
                            .background(Capsule().fill(BSColor.Stage.foreground))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, BSSpacing.xs)
                    .accessibilityIdentifier("artist.playLatest")
                }
            }
        }
        .padding(.horizontal, BSSpacing.roomy)
    }

    @ViewBuilder
    private func shelf(_ title: String, _ discs: [ListeningDisc]) -> some View {
        if !discs.isEmpty {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: title).font(ListeningOverviewStyle.sectionTitle)
                    Spacer()
                    Text(verbatim: "\(discs.count)").font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
                }
                .padding(.horizontal, BSSpacing.roomy)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: BSSpacing.compact) {
                        ForEach(discs) { disc in releaseCard(disc) }
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                }
            }
        }
    }

    private func releaseCard(_ disc: ListeningDisc) -> some View {
        let width = ListeningOverviewStyle.releaseCard
        return discLink(disc) {
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: width, height: width)
                    .overlay(alignment: .bottomTrailing) {
                        if room?.isOnDeckAndPlaying(disc) == true {
                            Image(systemName: "waveform")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(BSColor.Stage.background)
                                .frame(width: ListeningOverviewStyle.badge, height: ListeningOverviewStyle.badge)
                                .background(Circle().fill(BSColor.Stage.foreground))
                                .padding(BSSpacing.xs)
                        }
                    }
                Text(disc.title).font(ListeningOverviewStyle.itemTitle).lineLimit(2).multilineTextAlignment(.leading)
                Text(ListeningReleaseMeta.yearAndTrackCount(disc)).font(BSListeningTokens.caption).foregroundStyle(BSColor.Stage.muted)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    /// With the player ready a release opens its track list; before that a tap waits rather than doing nothing.
    @ViewBuilder
    private func discLink<Label: View>(_ disc: ListeningDisc, @ViewBuilder label: () -> Label) -> some View {
        if let room {
            NavigationLink {
                ArtistProfileDiscDetail(room: room, disc: disc)
            } label: { label() }
            .buttonStyle(.plain)
        } else {
            label()
        }
    }

    // MARK: Apple Music

    @ViewBuilder
    private var appleMusicLink: some View {
        if let url = reference.appleMusicURL
            ?? reference.appleMusicArtistID.flatMap({ URL(string: "https://music.apple.com/artist/\($0)") }) {
            Button { openURL(url) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right")
                    Text(BSLocalization.text("在 Apple Music 打开"))
                }
                .font(ListeningOverviewStyle.buttonLabel)
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: ListeningOverviewStyle.pillHeight)
                .background(Capsule().fill(ListeningOverviewStyle.buttonFill))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, BSSpacing.roomy)
        }
    }
}

/// A release pushed inside the artist page; playing from it returns to the artist.
private struct ArtistProfileDiscDetail: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ListeningDiscDetailView(room: room, disc: disc, showsCloseButton: false, dismissPresentation: { dismiss() })
    }
}

/// The artist page for surfaces that present rather than push.
struct ArtistProfileSheet: View {
    let reference: ArtistReference
    var show: Show?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ArtistProfileView(reference: reference, show: show)
                .toolbar { BSChromeToolbarCloseButton { dismiss() } }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
