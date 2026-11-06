import SwiftUI

/// One album per screen; whichever album settles on screen starts playing.
struct ListeningPickFeedView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    let startingDisc: ListeningDisc?
    let onClose: () -> Void
    @State private var filter: ListeningDiscPickFilter = .all
    @State private var order: [ListeningDisc] = []
    @State private var currentID: String?

    private var scopeKey: String { ListeningDiscPickPolicy.showScopeKey }
    /// The scroll view reports nil while it first lays out; the opening album still counts as on screen.
    private var settledID: String? { currentID ?? order.first?.id }

    var body: some View {
        ZStack(alignment: .top) {
            BSColor.Stage.background.ignoresSafeArea()
            if order.isEmpty {
                Text(ListeningCopy.text(filter == .all ? "这排柜子暂时没有可挑的唱片" : "没有符合筛选条件的唱片"))
                    .font(.subheadline)
                    .foregroundStyle(BSColor.Stage.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(order) { disc in
                            ListeningPickFeedPage(
                                room: room,
                                disc: disc,
                                show: show,
                                isCurrent: disc.id == settledID,
                                onListen: { listen(disc) }
                            )
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(disc.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentID)
                .ignoresSafeArea()
            }
            header
        }
        .foregroundStyle(BSColor.Stage.foreground)
        .onAppear { rebuild(startingWith: startingDisc) }
        .onChange(of: filter) { _, _ in rebuild(startingWith: nil) }
        .task(id: settledID) { await playSettledPage() }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(Circle().fill(ListeningOverviewStyle.scrim))
            }
            .accessibilityLabel(BSLocalization.text("关闭"))
            .accessibilityIdentifier("listening.pickFeed.close")
            Spacer()
            Text(ListeningCopy.text("帮我挑一张")).font(ListeningOverviewStyle.headerTitle)
            Spacer()
            Menu {
                Picker(ListeningCopy.text("筛选唱片"), selection: $filter) {
                    ForEach(ListeningDiscPickFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(ListeningOverviewStyle.headerTitle)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(Circle().fill(ListeningOverviewStyle.scrim))
            }
            .accessibilityLabel(ListeningCopy.text("筛选唱片"))
            .accessibilityIdentifier("listening.pickFeed.filter")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, BSSpacing.compact)
    }

    private func rebuild(startingWith start: ListeningDisc?) {
        let candidates = room.pickCandidates(filter: filter)
        order = ListeningPickOrder.feed(first: start, candidates: candidates) { remaining in
            ListeningDiscPickPolicy.pick(showID: show.id, scopeKey: scopeKey, candidates: remaining)
        }
        currentID = order.first?.id
    }

    private func playSettledPage() async {
        guard let disc = order.first(where: { $0.id == settledID }) else { return }
        try? await Task.sleep(for: .milliseconds(350))
        // A load already under way finishes first, but a stuck one cannot hold the page forever.
        let deadline = ContinuousClock.now + .seconds(6)
        while !Task.isCancelled, room.busy || room.mechanism.isAutomatic, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(60))
        }
        guard !Task.isCancelled else { return }
        ListeningDiscPickPolicy.recordDraw(showID: show.id, scopeKey: scopeKey, discID: disc.id)
        room.play(disc)
    }

    private func listen(_ disc: ListeningDisc) {
        room.play(disc)
        onClose()
    }
}

private struct ListeningPickFeedPage: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    let show: Show
    let isCurrent: Bool
    let onListen: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let cover = min(proxy.size.width - BSSpacing.xl * 2, proxy.size.height * 0.42)
            ZStack(alignment: .bottomLeading) {
                ListeningArtwork(url: disc.artworkURL, title: disc.title)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 60)
                    .opacity(0.6)
                LinearGradient(colors: [BSColor.Stage.background.opacity(0.2), .clear, BSColor.Stage.background.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: cover, height: cover)
                    .shadow(color: .black.opacity(0.6), radius: 34, y: 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, proxy.size.height * 0.2)
                HStack(alignment: .bottom, spacing: BSSpacing.md) {
                    info
                    Button(action: onListen) {
                        VStack(spacing: BSSpacing.xs) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(BSColor.Stage.background)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(BSColor.Stage.foreground))
                            Text(ListeningCopy.text("就听这张")).font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("listening.pickFeed.listen")
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.bottom, proxy.safeAreaInsets.bottom + 72)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            HStack(spacing: BSSpacing.sm) {
                Text(disc.artistNames.first ?? "")
                    .font(ListeningOverviewStyle.caps(14)).tracking(2.5).textCase(.uppercase)
                    .foregroundStyle(BSColor.Stage.accent)
                    .lineLimit(1)
                if isCurrent, room.isOnDeckAndPlaying(disc), room.isPlaying {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BSColor.Stage.accent)
                }
            }
            Text(disc.title).font(ListeningOverviewStyle.serif(42)).lineLimit(2).minimumScaleFactor(0.7)
            Text(ListeningReleaseMeta.yearAndTrackCount(disc)).font(ListeningOverviewStyle.meta).foregroundStyle(BSColor.Stage.foreground.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
