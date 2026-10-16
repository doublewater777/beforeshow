import Foundation

/// 产品分析事件。名称与属性已上线即固定；改动同步 `docs/observability/product-analytics.md`。
/// 不带姓名、现场名、艺人、场馆、token、URL 或任何用户输入文字。
enum AnalyticsEvent {
    enum OpenSource: String {
        case notification
        case widget
        case liveActivity = "live_activity"
    }

    enum RecommendationSurface: String {
        case card
        case notification
    }

    case onboardingStarted
    case onboardingPageViewed(page: String)
    case onboardingAddShowTapped
    case onboardingInviteAccepted
    case onboardingSkipped(fromPage: String)
    case onboardingCompleted(method: String)
    case screenshotRecognized
    case showLinkParsed
    case duplicateShowBlocked(method: String, existingShowID: UUID)
    case proLimitReached
    case showAdded(showID: UUID, method: String, lifecycle: String, isFirstShow: Bool, isFestival: Bool)
    case showEndedConfirmed(showID: UUID)
    case listenPlaybackStarted(source: ListeningPlaybackSource)
    case timetableSaved(showID: UUID, performanceCount: Int, isNew: Bool)
    case memoryFragmentCreated(showID: UUID, mediaCount: Int, phase: MemoryFragmentPhase)
    case dispersalCeremonyCompleted(showID: UUID, rating: Int?, hasNote: Bool)
    case dispersalCeremonySkipped(showID: UUID, trigger: String)
    case memoryCardShared(showID: UUID, materialCount: Int)
    case appOpenedFrom(source: OpenSource, destination: String, feature: RecommendedFeature?)
    case featureRecommendationShown(showID: UUID, feature: RecommendedFeature)
    case featureRecommendationTapped(showID: UUID, feature: RecommendedFeature, surface: RecommendationSurface)
    case proPaywallViewed
    case proPurchaseCompleted(plan: String)
    case proPurchaseFailed(plan: String)
    case proRestored
    case appReviewPromptRequested(moment: String)
    case appReviewStoreOpened(moment: String)

    var name: String {
        switch self {
        case .onboardingStarted: "onboarding_started"
        case .onboardingPageViewed: "onboarding_page_viewed"
        case .onboardingAddShowTapped: "onboarding_add_show_tapped"
        case .onboardingInviteAccepted: "onboarding_invite_accepted"
        case .onboardingSkipped: "onboarding_skipped"
        case .onboardingCompleted: "onboarding_completed"
        case .screenshotRecognized: "screenshot_recognized"
        case .showLinkParsed: "show_link_parsed"
        case .duplicateShowBlocked: "duplicate_show_blocked"
        case .proLimitReached: "pro_limit_reached"
        case .showAdded: "show_added"
        case .showEndedConfirmed: "show_ended_confirmed"
        case .listenPlaybackStarted: "listen_playback_started"
        case .timetableSaved: "timetable_saved"
        case .memoryFragmentCreated: "memory_fragment_created"
        case .dispersalCeremonyCompleted: "dispersal_ceremony_completed"
        case .dispersalCeremonySkipped: "dispersal_ceremony_skipped"
        case .memoryCardShared: "memory_card_shared"
        case .appOpenedFrom: "app_opened_from"
        case .featureRecommendationShown: "feature_recommendation_shown"
        case .featureRecommendationTapped: "feature_recommendation_tapped"
        case .proPaywallViewed: "pro_paywall_viewed"
        case .proPurchaseCompleted: "pro_purchase_completed"
        case .proPurchaseFailed: "pro_purchase_failed"
        case .proRestored: "pro_restored"
        case .appReviewPromptRequested: "app_review_prompt_requested"
        case .appReviewStoreOpened: "app_review_store_opened"
        }
    }

    /// 北极星「月陪伴现场数」计入的陪伴行为。
    var isCoreAction: Bool {
        switch self {
        case .listenPlaybackStarted, .timetableSaved, .memoryFragmentCreated,
             .dispersalCeremonyCompleted, .memoryCardShared:
            true
        case .appOpenedFrom(let source, _, _):
            source != .notification
        default:
            false
        }
    }

    var properties: [String: Any] {
        var properties = payload
        if isCoreAction { properties["core_action"] = true }
        return properties
    }

    private var payload: [String: Any] {
        switch self {
        case .onboardingStarted, .onboardingAddShowTapped, .onboardingInviteAccepted,
             .screenshotRecognized, .showLinkParsed, .proLimitReached,
             .proPaywallViewed, .proRestored:
            return [:]
        case .onboardingPageViewed(let page):
            return ["page": page]
        case .onboardingSkipped(let fromPage):
            return ["from_page": fromPage]
        case .onboardingCompleted(let method):
            return ["method": method]
        case .duplicateShowBlocked(let method, let existingShowID):
            return ["method": method, "existing_show_id": existingShowID.uuidString]
        case .showAdded(let showID, let method, let lifecycle, let isFirstShow, let isFestival):
            return [
                "show_id": showID.uuidString,
                "method": method,
                "lifecycle": lifecycle,
                "is_first_show": isFirstShow,
                "is_festival": isFestival
            ]
        case .showEndedConfirmed(let showID):
            return ["show_id": showID.uuidString]
        case .listenPlaybackStarted(let source):
            return ["source": source == .fullCatalog ? "full" : "preview"]
        case .timetableSaved(let showID, let performanceCount, let isNew):
            return ["show_id": showID.uuidString, "performance_count": performanceCount, "is_new": isNew]
        case .memoryFragmentCreated(let showID, let mediaCount, let phase):
            return [
                "show_id": showID.uuidString,
                "has_media": mediaCount > 0,
                "media_count": mediaCount,
                "phase": phase.rawValue
            ]
        case .dispersalCeremonyCompleted(let showID, let rating, let hasNote):
            var properties: [String: Any] = [
                "show_id": showID.uuidString,
                "has_rating": rating != nil,
                "has_note": hasNote
            ]
            if let rating { properties["rating_value"] = rating }
            return properties
        case .dispersalCeremonySkipped(let showID, let trigger):
            return ["show_id": showID.uuidString, "trigger": trigger]
        case .memoryCardShared(let showID, let materialCount):
            return ["show_id": showID.uuidString, "material_count": materialCount]
        case .appOpenedFrom(let source, let destination, let feature):
            var properties: [String: Any] = ["source": source.rawValue, "destination": destination]
            if let feature { properties["feature"] = feature.rawValue }
            return properties
        case .featureRecommendationShown(let showID, let feature):
            return ["show_id": showID.uuidString, "feature": feature.rawValue, "surface": RecommendationSurface.card.rawValue]
        case .featureRecommendationTapped(let showID, let feature, let surface):
            return ["show_id": showID.uuidString, "feature": feature.rawValue, "surface": surface.rawValue]
        case .proPurchaseCompleted(let plan), .proPurchaseFailed(let plan):
            return ["plan": plan]
        case .appReviewPromptRequested(let moment), .appReviewStoreOpened(let moment):
            return ["moment": moment]
        }
    }
}
