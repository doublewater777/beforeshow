import CloudKit
import Foundation

// MARK: - Domain

/// CloudKit-side companion session status (maps to local `ShowCompanionStatus`).
enum CompanionCloudStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case pending
    case accepted
    case canceled

    var localStatus: ShowCompanionStatus {
        switch self {
        case .pending: return .pending
        case .accepted: return .confirmed
        case .canceled: return .canceled
        }
    }
}

/// Full CloudKit record identity (name + zone + owner).
/// Sharing requires a custom private zone; default-zone records cannot be shared.
struct CompanionRecordLocator: Equatable, Sendable, Codable, Hashable {
    static let companionZoneName = "CompanionSessions"

    var recordName: String
    var zoneName: String
    var ownerName: String

    init(
        recordName: String,
        zoneName: String = CompanionRecordLocator.companionZoneName,
        ownerName: String = CKCurrentUserDefaultName
    ) {
        self.recordName = recordName
        self.zoneName = zoneName
        self.ownerName = ownerName
    }

    init(recordID: CKRecord.ID) {
        self.recordName = recordID.recordName
        self.zoneName = recordID.zoneID.zoneName
        self.ownerName = recordID.zoneID.ownerName
    }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    var recordID: CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    /// Shared-database zone IDs use the share owner's identity, not the current user token.
    func sharedDatabaseLocator(ownerName sharedOwnerName: String) -> CompanionRecordLocator {
        CompanionRecordLocator(
            recordName: recordName,
            zoneName: zoneName,
            ownerName: sharedOwnerName
        )
    }
}

struct CompanionSessionSnapshot: Equatable, Sendable {
    var sessionLocator: CompanionRecordLocator
    var shareLocator: CompanionRecordLocator?
    var show: CompanionShowSnapshot
    var ownerDisplayName: String?
    var participantDisplayName: String?
    var participantDisplayNames: [String]
    var status: CompanionCloudStatus
    var createdAt: Date
    var acceptedAt: Date?
    var canceledAt: Date?

    /// Convenience for tests / call sites that only need the record name.
    var recordName: String { sessionLocator.recordName }
    var shareRecordName: String? { shareLocator?.recordName }

    /// Names this device should show for the other people in the group.
    func companionDisplayNames(isOwner: Bool) -> [String] {
        let listed = CompanionNameList.normalized(participantDisplayNames)
        if isOwner {
            if status == .accepted { return listed }
            if !listed.isEmpty { return listed }
            return CompanionNameList.normalized([participantDisplayName].compactMap { $0 })
        }
        var names = CompanionNameList.normalized([ownerDisplayName].compactMap { $0 })
        names.append(contentsOf: listed)
        if names.isEmpty {
            names = CompanionNameList.normalized([participantDisplayName].compactMap { $0 })
        }
        return CompanionNameList.normalized(names)
    }

    /// Joined display name for the other people in the group.
    func companionDisplayName(isOwner: Bool) -> String? {
        CompanionNameList.joined(companionDisplayNames(isOwner: isOwner))
    }
}

struct CompanionPreparedShare: Equatable, Sendable {
    var session: CompanionSessionSnapshot
    /// Archived saved `CKShare`. Distribution reads its stable invitation URL.
    var shareSystemFields: Data
}

enum CompanionSharingError: Error, Equatable, Sendable {
    case iCloudAccountUnavailable
    case networkFailure
    case sharePreparationFailed
    case acceptFailed
    case sessionNotFound
    case invalidPayload
    case permissionDenied
    case conflict
    /// Share was accepted but local reconciliation could not complete yet.
    case statusSyncPending
}

enum CompanionMembershipState: Equatable, Sendable {
    case healthy
    case removed
    case warning(String)

    var warning: String? {
        if case .warning(let message) = self { return message }
        return nil
    }
}

enum CompanionShareMemberStatus: Equatable, Sendable {
    case accepted
    case pending
    case removed
    case unknown
}

/// Owner-side share membership without mutating CloudKit.
/// Product membership is append-only: missing/pending/removed CloudKit participants
/// never erase an already-recorded local companion fact.
enum CompanionMembershipPolicy {
    static func evaluate(
        nonOwnerStatuses: [CompanionShareMemberStatus]
    ) -> CompanionMembershipState {
        let unknown = nonOwnerStatuses.filter { $0 == .unknown }.count
        if unknown > 0 {
            return .warning("同行成员状态暂时无法确认，请稍后重试")
        }
        return .healthy
    }
}

enum CompanionNameList {
    static func normalized(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    static func joined(_ names: [String]) -> String? {
        let cleaned = normalized(names)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.joined(separator: "、")
    }

    static func isSameGroup(_ lhs: [String], _ rhs: [String]) -> Bool {
        Set(normalized(lhs)) == Set(normalized(rhs))
    }
}
