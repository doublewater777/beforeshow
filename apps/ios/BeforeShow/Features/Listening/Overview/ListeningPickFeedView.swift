import SwiftUI

/// 帮我挑一张: one album per screen, or a record shelf (see `ListeningPickStyle`). With nothing playing, the album that settles on screen plays its previews;
/// opened over music, browsing is silent. Only 就听这张 puts an album on the deck and the mini player.
struct ListeningPickFeedView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    let startingDisc: ListeningDisc?
    /// Hands back the album the user stopped on, so Listen shows it.
    let onClose: (ListeningDisc?) -> Void
    @State private var order: [ListeningDisc] = []
    @State private var currentID: String?
    @State private var openingID: String?
    /// Opened while something plays: browsing stays silent, only 就听这张 changes the music.
    @State private var isListeningOutside = false
    @State private var audition = ListeningPickAudition()
    @AppStorage(ListeningPickStyle.storageKey) private var styleRawValue = ""
    @AppStorage(ListeningPickStyle.trialOpensKey) private var trialOpensUsed = 0
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    /// This open already used one of the Pro styles' free tries.
    @State private var countedTrialThisOpen = false
    @State private var isShowingStyles = false

    private var scopeKey: String { ListeningDiscPickPolicy.showScopeKey }
    /// The scroll view reports nil while it first lays out; the opening album still counts as on screen.
    private var settledID: String? { currentID ?? openingID ?? order.first?.id }
    private var settledDisc: ListeningDisc? { order.first { $0.id == settledID } }
    private var isPro: Bool { ProEntitlementStorage.decode(entitlementRawValue).isProActive }
    private var style: ListeningPickStyle {
        .resolved(storedRawValue: styleRawValue, isPro: isPro, trialOpensUsed: trialOpensUsed, countedThisOpen: countedTrialThisOpen)
    }

    var body: some View {
        ZStack(alignment: .top) {
            BSColor.Stage.background.ignoresSafeArea()
            if order.isEmpty {
                Text(ListeningCopy.text("这排柜子暂时没有可挑的唱片"))
                    .font(.subheadline)
                    .foregroundStyle(BSColor.Stage.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if style != .feed {
                ListeningPickShelfView(
                    style: style, discs: order, show: show, currentID: $currentID,
                    isAuditioning: { audition.isAuditioning($0) }, onListen: { listen($0) }
                )
                .id(style)
            } else {
                ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(order) { disc in
                            ListeningPickFeedPage(
                                room: room,
                                disc: disc,
                                show: show,
                                isCurrent: disc.id == settledID,
                                isAuditioning: audition.isAuditioning(disc),
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
                // Paging layouts ignore an initial scroll position; land on the opening album explicitly.
                .onAppear { if let openingID, openingID != order.first?.id { proxy.scrollTo(openingID, anchor: .top) } }
                }
            }
            header
        }
        .foregroundStyle(BSColor.Stage.foreground)
        .sheet(isPresented: $isShowingStyles) {
            ListeningPickStyleSheet(
                discs: order, show: show, currentID: settledID, current: style,
                trialLeft: ListeningPickStyle.trialOpensLeft(isPro: isPro, used: trialOpensUsed),
                isLocked: ListeningPickStyle.trialOpensLeft(isPro: isPro, used: trialOpensUsed) == 0 && !countedTrialThisOpen,
                onChoose: { styleRawValue = $0.rawValue }
            )
        }
        .onChange(of: style, initial: true) { _, style in countTrial(for: style) }
        .onChange(of: style) { _, _ in rebuild(startingWith: settledDisc, keepingPlaying: true) }
        .onAppear {
            isListeningOutside = room.wantsPlayback
            rebuild(startingWith: startingDisc, keepingPlaying: true)
        }
        .task(id: settledID) {
            prefetchNextPage()
            guard !isListeningOutside else { return }
            await playSettledPage()
        }
        .onDisappear { audition.stop(resumeListening: true) }
    }

    private var header: some View {
        HStack {
            Button {
                audition.stop(resumeListening: true)
                onClose(settledDisc)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(Circle().fill(ListeningOverviewStyle.scrim))
            }
            .accessibilityLabel(BSLocalization.text("关闭"))
            .accessibilityIdentifier("listening.pickFeed.close")
            Spacer()
            if style == .feed {
                Text(ListeningCopy.text("帮我挑一张")).font(ListeningOverviewStyle.headerTitle)
            }
            Spacer()
            Button { isShowingStyles = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(ListeningOverviewStyle.headerTitle)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(Circle().fill(ListeningOverviewStyle.scrim))
            }
            .accessibilityLabel(ListeningCopy.text("样式"))
            .accessibilityIdentifier("listening.pickFeed.style")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, BSSpacing.compact)
    }

    /// Free users' opens of a Pro style count towards the shared trial, once per open.
    private func countTrial(for style: ListeningPickStyle) {
        guard style.isPro, !isPro, !countedTrialThisOpen else { return }
        countedTrialThisOpen = true
        trialOpensUsed += 1
    }

    private func rebuild(startingWith start: ListeningDisc?, keepingPlaying: Bool) {
        let drawn = ListeningPickOrder.feed(first: start, drawn: ListeningDiscPickPolicy.order(
            showID: show.id, scopeKey: scopeKey, candidates: room.pickCandidates(), lineupNames: show.artistNames
        ))
        let playing = keepingPlaying && room.wantsPlayback ? room.loadedDisc : nil
        let kept = ListeningPickOrder.keeping(playing, above: drawn)
        let leading = (kept.firstIndex { $0.id == drawn.first?.id } ?? 0) + 1
        order = style == .feed ? kept : ListeningPickOrder.centred(kept, leading: leading)
        openingID = drawn.first?.id
        currentID = openingID
    }

    /// Paging is forward, so the album below is warmed while this one plays.
    private func prefetchNextPage() {
        guard let index = order.firstIndex(where: { $0.id == settledID }), order.indices.contains(index + 1) else { return }
        room.prefetch(order[index + 1])
    }

    private func playSettledPage() async {
        guard let disc = order.first(where: { $0.id == settledID }) else { return }
        // A page flicked past is not played; only the one the user settles on.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        ListeningDiscPickPolicy.recordDraw(showID: show.id, scopeKey: scopeKey, discID: disc.id)
        // Back on the record already in the mini player: drop the audition and let it carry on.
        if disc.id == room.loadedDisc?.id {
            audition.stop(resumeListening: true)
            return
        }
        audition.play(disc)
    }

    private func listen(_ disc: ListeningDisc) {
        audition.stop(resumeListening: false)
        room.play(disc)
        onClose(disc)
    }
}

private struct ListeningPickFeedPage: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    let show: Show
    let isCurrent: Bool
    let isAuditioning: Bool
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
                            Image(systemName: "headphones")
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
                Text(disc.displayArtistName(for: show))
                    .font(ListeningOverviewStyle.caps(14)).tracking(2.5).textCase(.uppercase)
                    .foregroundStyle(BSColor.Stage.accent)
                    .lineLimit(1)
                if isCurrent, isAuditioning || (room.isOnDeckAndPlaying(disc) && room.isPlaying) {
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
