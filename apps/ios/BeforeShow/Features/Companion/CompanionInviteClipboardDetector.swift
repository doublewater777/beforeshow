import Foundation
import SwiftData
import UIKit

@MainActor
enum CompanionInviteClipboardDetector {
    private static let lastProcessedTokenKey = "CompanionInviteLastProcessedToken"
    private(set) static var pendingFirstTimeInvite: CompanionInviteSnapshot?

    static func setPendingFirstTimeInvite(_ snapshot: CompanionInviteSnapshot?) {
        pendingFirstTimeInvite = snapshot
    }

    static func activeFirstTimeInvite(userDefaults: UserDefaults = .standard) -> CompanionInviteSnapshot? {
        #if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--invite-url=") }) {
            let urlString = String(arg.dropFirst("--invite-url=".count))
            if let snapshot = CompanionInviteWebLink.extractSnapshot(from: urlString),
               !isTokenProcessed(snapshot.token, userDefaults: userDefaults) {
                return snapshot
            }
        }
        #endif
        if let pending = pendingFirstTimeInvite, !isTokenProcessed(pending.token, userDefaults: userDefaults) {
            return pending
        }
        let detected = detectInviteFromPasteboard(userDefaults: userDefaults)
        if let detected {
            pendingFirstTimeInvite = detected
        }
        return detected
    }

    static func isTokenProcessed(_ token: String, userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.string(forKey: lastProcessedTokenKey) == token
    }

    static func markTokenProcessed(_ token: String, userDefaults: UserDefaults = .standard) {
        userDefaults.set(token, forKey: lastProcessedTokenKey)
    }

    static func clearProcessedToken(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: lastProcessedTokenKey)
    }

    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// Detects a pending companion invite from the system clipboard.
    /// Returns the decoded snapshot if a valid, unhandled invite is found.
    static func detectInviteFromPasteboard(userDefaults: UserDefaults = .standard) -> CompanionInviteSnapshot? {
        guard !isRunningUnitTests else { return nil }
        guard UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs else { return nil }
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return nil }
        guard let snapshot = CompanionInviteWebLink.extractSnapshot(from: text) else { return nil }
        guard !isTokenProcessed(snapshot.token, userDefaults: userDefaults) else { return nil }
        return snapshot
    }

    /// Check pasteboard on launch or foreground transition.
    /// For returning users who have completed onboarding, delivers the invite via the standard sheet.
    /// For first-time users, the invite is surfaced through customized invited onboarding.
    static func checkPasteboardForInvite(
        appDelegate: BeforeShowAppDelegate?,
        userDefaults: UserDefaults = .standard
    ) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--invite-url=") }) {
            return
        }
        #endif
        guard let snapshot = detectInviteFromPasteboard(userDefaults: userDefaults) else { return }

        if OnboardingCompletionStore.hasCompleted(in: userDefaults) {
            markTokenProcessed(snapshot.token, userDefaults: userDefaults)
            CompanionDebugLog.write("CompanionInviteClipboardDetector: delivering invite to returning user for show=\(snapshot.showName)")
            appDelegate?.deliverCompanionInviteURL(snapshot.shareURL)
        }
    }

    /// Directly accepts an invitation during first-time onboarding without redundant popups.
    static func acceptDirectly(
        snapshot: CompanionInviteSnapshot,
        in modelContext: ModelContext,
        userDefaults: UserDefaults = .standard
    ) async -> (success: Bool, errorMessage: String?) {
        do {
            try await CloudKitCompanionSharingService().ensureAccountAvailable()
            let metadata = try await CloudKitCompanionSharingService.fetchMetadataWithRootRecord(for: snapshot.shareURL)
            let session = try await CloudKitCompanionSharingService().acceptShare(
                metadata: metadata,
                participantDisplayName: CompanionUserProfile.nickname
            )
            try CompanionAcceptedSessionImporter.apply(
                session,
                in: modelContext,
                strategy: .automatic
            )
            CompanionCloudSyncMarker.enable(in: userDefaults, usesKeychain: true)
            markTokenProcessed(snapshot.token, userDefaults: userDefaults)
            OnboardingCompletionStore.markCompleted(in: userDefaults)
            return (true, nil)
        } catch {
            CompanionDebugLog.write("CompanionInviteClipboardDetector.acceptDirectly failed: \(error)")
            let message = CompanionSharingPresentation.userMessage(for: error)
            return (false, message)
        }
    }
}
