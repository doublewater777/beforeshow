import SwiftData
import SwiftUI

// MARK: - Current Show Management Actions
// 快捷入口、主卡推荐和通知转来的落点，统一在当前现场首页里打开（ADR 0037）。

extension CurrentShowManagementSection {
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
            if let next = FeatureRecommendationLedger.nextFutureShow(excluding: show.id, in: candidateShows, now: Date()) {
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
            pendingMemoryCreate = nil
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
        case .home, .listen, .nextShow:
            break
        }
    }

    /// 散场仪式从确认散场时间开始：还没确认的先确认，确认后接到仪式。
    func openDispersal() {
        if show.endedAt == nil {
            presentedSheet = .endConfirmation
        } else {
            ceremonySheetShowID = show.id
        }
    }

    func openMemoryFragments() {
        pendingMemoryCreate = nil
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
