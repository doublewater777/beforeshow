import SwiftData
import SwiftUI

// MARK: - Current Show Management Actions
// 快捷入口、主卡推荐和通知转来的落点，统一在当前现场首页里打开（ADR 0037）。

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

    func performRecommendation(_ feature: RecommendedFeature) {
        switch feature {
        case .widget:
            presentedSheet = .widgetGuide
        case .companion:
            presentedSheet = .companion
        case .listen:
            NotificationDeepLinkRouter.shared.route(to: NotificationDeepLink(showID: show.id, destination: .listen))
        case .timetable:
            presentedSheet = .asset(.timetable)
        case .dispersal:
            openDispersal()
        case .memoryFragments:
            openMemoryFragments()
        case .footprint:
            presentedSheet = .footprint
        case .nextShow:
            if let next = FeatureRecommendationLedger.nextFutureShow(excluding: show.id, in: attachedCandidateShows, now: Date()) {
                onSetCurrentShow(next)
            } else {
                onAddShow()
            }
        case .addShow:
            onAddShow()
        }
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
