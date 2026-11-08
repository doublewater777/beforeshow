import Foundation
import Observation
import SwiftData

/// What an invite link sent by an older app version carries in its token.
struct CompanionInviteSnapshot: Equatable, Sendable {
    let token: String
    let showName: String
    let showStartTime: Date
    let timeZoneIdentifier: String?
    let timeZoneSecondsFromGMT: Int?
    let location: String?
    let ownerName: String?
    let coverImageURL: String?
}

/// Read-only decoder for links the retired invite flow handed out:
/// `https://beforeshow.doublewaterapps.com/join/<token>`, `beforeshow://join/<token>`
/// and raw iCloud share URLs. New links are never produced.
enum CompanionInviteWebLink {
    static let host = "beforeshow.doublewaterapps.com"
    static let path = "/join/"

    private struct Payload: Decodable {
        let v: Int
        let n: String
        let t: Int64
        let z: String?
        let s: Int?
        let l: String?
        let o: String?
        let c: String?
    }

    static func isLegacyInviteURL(_ url: URL) -> Bool {
        isJoinLink(url) || isCloudShareURL(url)
    }

    static func snapshot(from url: URL) -> CompanionInviteSnapshot? {
        guard isJoinLink(url) else { return nil }
        let rawToken = url.scheme?.lowercased() == "https"
            ? String(url.path.dropFirst(path.count))
            : String(url.path.dropFirst())
        guard !rawToken.isEmpty, rawToken.count < 8_192,
              rawToken.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            return nil
        }
        var padded = rawToken
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.v == 1,
              let name = nonEmpty(payload.n) else {
            return nil
        }
        return CompanionInviteSnapshot(
            token: rawToken,
            showName: name,
            showStartTime: Date(timeIntervalSince1970: TimeInterval(payload.t)),
            timeZoneIdentifier: payload.z.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 },
            timeZoneSecondsFromGMT: payload.s,
            location: nonEmpty(payload.l),
            ownerName: nonEmpty(payload.o),
            coverImageURL: nonEmpty(payload.c)
        )
    }

    private static func isJoinLink(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        if scheme == "https", host == Self.host { return url.path.hasPrefix(path) }
        return scheme == "beforeshow" && host == "join"
    }

    private static func isCloudShareURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        let isICloud = ["icloud.com", "icloud.com.cn"].contains { host == $0 || host.hasSuffix(".\($0)") }
        return isICloud && url.path.hasPrefix("/share/")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

/// Holds the one old invite waiting to be handled until the root can show it.
@MainActor
@Observable
final class LegacyCompanionInviteInbox {
    static let shared = LegacyCompanionInviteInbox()

    var pending: CompanionInviteSnapshot?
    @ObservationIgnored private var receivedTokens = Set<String>()

    /// `true` when the URL belongs to the retired invite flow, whether or not it decoded;
    /// such links never fall through to other routes and never surface an error.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard CompanionInviteWebLink.isLegacyInviteURL(url) else { return false }
        // Scene delegate and SwiftUI may both deliver the same open.
        if let snapshot = CompanionInviteWebLink.snapshot(from: url),
           receivedTokens.insert(snapshot.token).inserted {
            pending = snapshot
        }
        return true
    }
}

enum LegacyCompanionInviteOutcome: Equatable {
    case deferred
    case addedCompanion(showID: UUID, name: String?)
    case prefillAddShow(ShowDraft)
}

@MainActor
enum LegacyCompanionInviteRouting {
    static func resolve(
        _ snapshot: CompanionInviteSnapshot,
        isOnboardingActive: Bool,
        in modelContext: ModelContext
    ) throws -> LegacyCompanionInviteOutcome {
        guard !isOnboardingActive else { return .deferred }
        let draft = draft(from: snapshot)
        var probeDraft = draft
        probeDraft.venueName = ""
        probeDraft.city = ""
        let probe = try probeDraft.makeShow()
        let shows = try modelContext.fetch(FetchDescriptor<Show>())
        guard let existing = ShowDuplicateMatcher.firstDuplicate(of: probe, in: shows) else {
            return .prefillAddShow(draft)
        }
        if let owner = snapshot.ownerName, existing.addCompanion(owner) {
            try modelContext.save()
        }
        return .addedCompanion(showID: existing.id, name: snapshot.ownerName)
    }

    static func draft(from snapshot: CompanionInviteSnapshot) -> ShowDraft {
        let parts = snapshot.location?
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        var draft = ShowDraft(
            name: snapshot.showName,
            date: snapshot.showStartTime,
            startTime: snapshot.showStartTime,
            timeZoneSecondsFromGMT: snapshot.timeZoneSecondsFromGMT,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            city: parts.count > 1 ? parts[parts.count - 1] : "",
            venueName: parts.first ?? "",
            coverImageURL: snapshot.coverImageURL ?? "",
            source: .link
        )
        draft.companionNames = [snapshot.ownerName].compactMap { $0 }
        draft.creationOrigin = .companionImport
        return draft
    }
}
