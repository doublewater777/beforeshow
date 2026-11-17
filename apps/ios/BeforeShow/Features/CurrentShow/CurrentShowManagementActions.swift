import SwiftData
import SwiftUI
import UIKit

// MARK: - Current Show Management Actions
// 快捷入口、主按钮和通知转来的落点，统一在当前现场首页里打开（ADR 0037）。

@MainActor @Observable
final class CurrentShowListeningPresentation {
    private(set) var isStarting = false
    private var startTask: Task<Void, Never>?

    @discardableResult
    func start(_ operation: @escaping @MainActor () async -> Void) -> Bool {
        guard !isStarting else { return false }
        isStarting = true
        startTask = Task { @MainActor [weak self] in
            defer {
                self?.isStarting = false
                self?.startTask = nil
            }
            await operation()
        }
        return true
    }

    func cancel() {
        startTask?.cancel()
        startTask = nil
        isStarting = false
    }
}

extension CurrentShowManagementSection {
    /// 删除当前现场后，父视图切到下一场之前，本视图可能先带着上一帧的 show / 列表重算。
    @ViewBuilder var body: some View {
        if show.isAttached { liveBody }
    }

    var attachedCandidateShows: [Show] { candidateShows.filter(\.isAttached) }

    func performQuickAction(_ action: CurrentShowQuickAction) {
        switch action {
        case .route:
            openRouteChooser()
        case .companion:
            presentedSheet = .companion
        case .ticket:
            presentedSheet = .asset(.ticket)
        case .timetable:
            presentedSheet = .asset(.timetable)
        case .memoryFragments:
            openMemoryFragments()
        case .dispersal:
            ceremonySheetShowID = show.id
        case .endShow:
            presentedSheet = .endConfirmation
        }
    }

    /// 散场停留期里一直带着这场的序号和解锁；揭晓动画只在第一次真正可见时播放。
    func revealUnlocksIfNeeded(isPostShow: Bool) {
        guard isPostShow, isHeroPlaybackActive, revealedUnlocks?.showID != show.id else { return }
        let store = ShowUnlockRevealStore()
        unlocksAnimateArrival = !store.hasShown(show.id)
        store.markShown(show.id)
        let unlocks = ShowUnlockReveal.unlocks(for: show, shows: attachedCandidateShows, in: modelContext)
        withAnimation(unlocksAnimateArrival ? .easeOut(duration: 0.3) : nil) { revealedUnlocks = unlocks }
    }

    func performPrimaryAction(_ action: HomeCountdownLockup.PrimaryAction) {
        if action.playsMusic, let room = ListeningRoomSessionStore.shared.room, room.wantsPlayback {
            if isPlayingCurrentShowContent(action: action, in: room) {
                listeningPresentation.cancel()
                room.playPause()
                return
            }
        }
        switch action {
        case .listen:
            if listeningPresentation.isStarting {
                listeningPresentation.cancel()
                if let room = ListeningRoomSessionStore.shared.room,
                   room.wantsPlayback,
                   isPlayingCurrentShowContent(action: action, in: room) {
                    room.playPause()
                }
                return
            }
            listeningPresentation.start {
                await startListeningFromHome()
            }
        case .playRecord:
            guard let record = unlockedRecord else { return }
            Task { await FootprintNumberSongPlayer.shared.start(record) }
        case .route:
            openRouteChooser()
        case .addShow:
            onAddShow()
        case .fillNewDate:
            homeRoute = .editShow(show.id)
        }
    }

    @MainActor
    func startListeningFromHome() async {
        let result = await ListeningHomePlaybackCoordinator.start(show: show, context: modelContext)
        guard !Task.isCancelled else {
            if let room = ListeningRoomSessionStore.shared.room,
               room.wantsPlayback,
               isPlayingCurrentShowContent(action: .listen, in: room) {
                room.playPause()
            }
            return
        }
        ProductAnalytics.capture(.listenTapped(
            source: .currentHome,
            outcome: result.analyticsOutcome,
            reason: result.analyticsReason
        ))

        applyHomeListeningRecovery(result)
    }

    func applyHomeListeningRecovery(_ result: ListeningHomePlaybackResult) {
        if case .needsArtistMatch(_, let slotIndex, _, _) = result {
            ListeningRoomSessionStore.shared.requestArtistMatch(
                showID: show.id,
                slotIndex: slotIndex,
                resumePlaybackOnSuccess: true
            )
        }

        if result.revealsListenTab {
            rootTabSelection?.wrappedValue = .listen
        }
    }

    /// 这场散场后解锁的数字唱片；揭晓过才有。
    var unlockedRecord: FootprintNumberSong? {
        revealedUnlocks?.showID == show.id ? revealedUnlocks?.record : nil
    }

    /// 播放机里放的是不是主按钮这件事的内容；是才把按钮当暂停。
    func isPlayingCurrentShowContent(
        action: HomeCountdownLockup.PrimaryAction,
        in room: ListeningRoomCoordinator
    ) -> Bool {
        switch action {
        case .playRecord:
            return unlockedRecord.map { room.loadedDisc?.id == FootprintNumberSongPlayer.discID($0.number) } ?? false
        case .listen:
            return room.show?.id == show.id
        default:
            return false
        }
    }

    func isCurrentShowAudioActive(
        room: ListeningRoomCoordinator?,
        action: HomeCountdownLockup.PrimaryAction?
    ) -> Bool {
        guard let action else { return false }
        if action == .listen, listeningPresentation.isStarting { return true }
        guard let room, room.wantsPlayback else { return false }
        return isPlayingCurrentShowContent(action: action, in: room)
    }

    /// 通知转来的当前现场落点：首页真正可见时才打开，避免冲掉正在进行的编辑。
    func consumeCurrentShowActionIfVisible() {
        guard isHeroPlaybackActive,
              let deepLink = notificationRouter.currentShowAction,
              deepLink.showID == show.id else {
            return
        }
        notificationRouter.consumeCurrentShowAction()
        switch deepLink.destination {
        case .route:
            openRouteChooser()
        case .memoryCreate:
            presentedSheet = .memoryCreate
        case .memoryFragments:
            openMemoryFragments()
        case .timetable:
            presentedSheet = .asset(.timetable)
        case .companion:
            presentedSheet = .companion
        case .widgetGuide:
            presentedSheet = .widgetGuide
        case .dispersal:
            openDispersal()
        case .footprint:
            presentedSheet = show.endedAt == nil ? .endConfirmation : .footprint
        case .addShow:
            onAddShow()
        case .weatherDetail:
            openWeatherDetail()
        case .home, .listen, .nextShow:
            break
        }
    }

    func openWeatherDetail() {
        presentedSheet = .weatherDetail
    }

    /// 散场仪式从确认散场时间开始：还没确认的先确认，确认后接到仪式。
    func openDispersal() {
        if show.endedAt != nil {
            ceremonySheetShowID = show.id
        } else if let end = CurrentShowEndPolicy.automaticEnd(for: show) {
            Task { @MainActor in
                if await onConfirmEnd(end) { ceremonySheetShowID = show.id }
            }
        } else {
            presentedSheet = .endConfirmation
        }
    }

    func openMemoryFragments() {
        presentedSheet = .memory
    }

    /// 用户在当前页用过功能后，按此刻重排通知并撤掉已完成的推荐。
    func reconcileNotificationsAfterFeatureUse() {
        let container = modelContext.container
        Task {
            await LocalNotificationCenter.shared.reconcilePortfolio(in: ModelContext(container))
        }
    }
}

/// 从推荐或通知打开的整页内容，统一给一个关闭按钮。
struct CurrentShowClosableSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(BSLocalization.text("关闭"))
                    }
                }
        }
    }
}

struct HomeHeaderScrollObserver: ViewModifier {
    @Binding var isOverContent: Bool

    func body(content: Content) -> some View {
        content.bsOnScrollOffset { offset in
            let next = offset.y > 10
            if isOverContent != next {
                isOverContent = next
            }
        }
    }
}

extension CurrentShowManagementSection {
    var routeQuery: String? {
        MapDestinationQuery.make(
            venueAddress: show.venueAddress,
            venueName: show.venueName,
            city: show.city,
            showName: show.name
        )
    }
    var hasMapDestination: Bool {
        guard let routeQuery else { return false }
        return !routeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// 弹窗副标题：优先场馆名，其次城市 / 演出名。
    var mapDestinationLabel: String {
        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let venue, !venue.isEmpty { return venue }
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let city, !city.isEmpty { return city }
        return show.name
    }
    var companionPresentation: CompanionQuickActionPresentation {
        CompanionQuickActionPresentation(companionNames: show.companionNames)
    }

}

enum CurrentShowHomeRoute: Hashable, Identifiable {
    case detail(UUID)
    case editShow(UUID)
    case recordWall
    case badgeWall

    var id: String {
        switch self {
        case .detail(let showID): "detail-\(showID.uuidString)"
        case .editShow(let showID): "edit-\(showID.uuidString)"
        case .recordWall: "recordWall"
        case .badgeWall: "badgeWall"
        }
    }
}

struct HomeRouteDestination: View {
    let route: CurrentShowHomeRoute
    let shows: [Show]

    private func show(id: UUID) -> Show? {
        shows.first { $0.id == id }
    }

    var body: some View {
        switch route {
        case .detail(let showID):
            if let show = show(id: showID) {
                ShowDetailView(show: show)
            }
        case .editShow(let showID):
            if let show = show(id: showID) {
                ShowDetailView(show: show, startsEditing: true)
            }
        case .recordWall:
            FootprintRecordWallView(archive: FootprintArchiveBuilder.make(shows: shows))
        case .badgeWall:
            FootprintBadgeWallView(archive: FootprintArchiveBuilder.make(shows: shows))
        }
    }
}
