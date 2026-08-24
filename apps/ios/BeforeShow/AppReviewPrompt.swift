import Foundation
import PostHog
import StoreKit
import UIKit

enum AppReviewPromptMoment: String {
    case addedShow
    case completedCeremony
    case settings
}

enum AppReviewPromptPolicy {
    static let lastPromptAtKey = "appReview.lastPromptAt"
    static let lastPromptVersionKey = "appReview.lastPromptVersion"
    static let minimumInterval: TimeInterval = 90 * 24 * 60 * 60

    static func presentationDelayNanoseconds(for moment: AppReviewPromptMoment) -> UInt64 {
        // Adding a show now hands off through a completion card and a home-arrival
        // transition. Let that meaningful product feedback finish before StoreKit
        // presents its review card.
        moment == .addedShow ? 2_000_000_000 : 800_000_000
    }

    static func shouldPrompt(
        now: Date,
        version: String,
        defaults: UserDefaults,
        arguments: [String]
    ) -> Bool {
        guard !isAutomatedLaunch(arguments) else { return false }
        guard defaults.string(forKey: lastPromptVersionKey) != version else { return false }
        if let lastPromptAt = defaults.object(forKey: lastPromptAtKey) as? Date,
           now.timeIntervalSince(lastPromptAt) < minimumInterval {
            return false
        }
        return true
    }

    static func recordPrompt(
        now: Date,
        version: String,
        defaults: UserDefaults
    ) {
        defaults.set(now, forKey: lastPromptAtKey)
        defaults.set(version, forKey: lastPromptVersionKey)
    }

    static func isAutomatedLaunch(_ arguments: [String]) -> Bool {
        arguments.contains { argument in
            argument.hasPrefix("--seed-")
                || argument.hasPrefix("--open-")
                || argument.hasPrefix("--auto-")
        }
    }
}

enum AppReviewPrompt {
    static let appStoreID = "6780078298"

    static var writeReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    @MainActor
    static func consider(
        _ moment: AppReviewPromptMoment,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        version: String = AppVersionInformation.current.marketingVersion,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        if moment == .settings {
            PostHogSDK.shared.capture(
                "app_review_store_opened",
                properties: ["moment": moment.rawValue]
            )
            openWriteReviewPage()
            return
        }

        guard AppReviewPromptPolicy.shouldPrompt(
            now: now,
            version: version,
            defaults: defaults,
            arguments: arguments
        ) else { return }

        AppReviewPromptPolicy.recordPrompt(
            now: now,
            version: version,
            defaults: defaults
        )
        PostHogSDK.shared.capture(
            "app_review_prompt_requested",
            properties: ["moment": moment.rawValue]
        )

        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: AppReviewPromptPolicy.presentationDelayNanoseconds(for: moment)
            )
            requestNativeReview()
        }
    }

    @MainActor
    static func openWriteReviewPage() {
        guard let url = writeReviewURL else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    static func requestNativeReview() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
    }
}
