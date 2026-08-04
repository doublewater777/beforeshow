import Foundation

enum SettingsEntry: String, CaseIterable, Equatable {
    case proMembership = "Pro会员"
    case privacyAndLocalData = "隐私与本地数据"
    case feedback = "意见反馈"
    case about = "关于开场前"
}

enum HomeStyle: String, Equatable {
    case halfCover = "half-cover"

    var displayName: String { "半屏封面" }
}

enum SettingsInformation {
    static let orderedEntries: [SettingsEntry] = [
        .proMembership,
        .privacyAndLocalData,
        .feedback,
        .about
    ]
}

enum PrivacyLocalDataCopy {
    static let points = [
        "添加现场时的票务截图只用于设备端 OCR，不会为了识别上传。",
        "票根与时刻表保存在 BeforeShow 的设备本地 App 沙盒中；BeforeShow 不会主动上传这些图片，也不会加入同行 CloudKit 分享记录，并会将它们排除在 iOS 系统备份之外。",
        "链接解析、同行分享等你主动使用的联网功能会发起网络请求；系统备份是否包含 App 数据由 iOS 和你的系统设置决定。",
        "记忆碎片、票根和时刻表里的图片是 App 沙盒副本，不是系统相册原始内容；BeforeShow 不提供跨设备同步或恢复保证。"
    ]

    static let clearDataExplanation = "清除本地数据会删除 BeforeShow 管理的本地记录、记忆碎片文字，以及 App 沙盒中的票根/时刻表、照片/视频副本和临时缓存；不会删除系统相册中的原始图片或视频。"
}

enum ProMembershipCopy {
    static let summary = "Pro 提供更高的现场保存额度，不锁本地已有内容。"

    /// 以 `ProFeatureGate` 实际接线的现场保存额度为准。
    static let unlockedPoints = [
        "无限添加现场（免费版限 1 场）"
    ]

    /// `ProFeatureGate` 中始终放行的能力：已有现场、手动编辑。
    static let freePoints = [
        "查看与编辑已有现场",
        "手动编辑所有内容"
    ]
}

enum FeedbackCategory: String, CaseIterable, Identifiable, Equatable {
    case product = "使用感受"
    case bug = "问题反馈"
    case privacy = "隐私与数据"

    var id: String { rawValue }
}

struct FeedbackDiagnostics: Equatable {
    let appVersion: String
    let osVersion: String
}

struct FeedbackDraft: Equatable {
    var category: FeedbackCategory
    var message: String
    var includesDiagnostics: Bool
}

struct FeedbackPayload: Equatable {
    let category: FeedbackCategory
    let message: String
    let diagnostics: FeedbackDiagnostics?
}

enum FeedbackValidationError: Error, Equatable {
    case emptyMessage
}

struct FeedbackPayloadBuilder {
    var diagnosticsProvider: () -> FeedbackDiagnostics = {
        FeedbackDiagnostics(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    func build(from draft: FeedbackDraft) throws -> FeedbackPayload {
        let trimmedMessage = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw FeedbackValidationError.emptyMessage
        }

        return FeedbackPayload(
            category: draft.category,
            message: trimmedMessage,
            diagnostics: draft.includesDiagnostics ? diagnosticsProvider() : nil
        )
    }
}

protocol FeedbackSubmitting {
    func submit(_ payload: FeedbackPayload) async throws
}

actor LocalFeedbackSubmitter: FeedbackSubmitting {
    private(set) var submittedPayloads: [FeedbackPayload] = []

    func submit(_ payload: FeedbackPayload) async throws {
        submittedPayloads.append(payload)
    }
}

struct LocalDataClearancePlan: Equatable {
    let deletesAppOwnedData: [String]
    let preservesSystemData: [String]
}

enum LocalDataClearancePolicy {
    static let defaultPlan = LocalDataClearancePlan(
        deletesAppOwnedData: [
            "SwiftData 中的现场和偏好设置",
            "记忆碎片文字与元数据",
            "BeforeShow 沙盒中的票根和时刻表图片",
            "BeforeShow 沙盒中保存的记忆照片和视频副本",
            "BeforeShow 沙盒中的临时缓存"
        ],
        preservesSystemData: [
            "系统相册中的原始图片和视频"
        ]
    )
}

enum LocalMediaCleanupRetry {
    struct PendingAsset: Codable, Equatable {
        let showID: UUID
        let kind: ShowAssetKind
        let relativePath: String
    }

    struct PendingMemoryCleanup: Codable, Equatable {
        let showID: UUID
        let fragmentID: UUID
        let relativePath: String?
    }

    struct PendingMemoryStaging: Codable, Equatable {
        let draftID: UUID
    }

    private static let pendingMemoryFullCleanupKey = "BeforeShow.pendingFullMemoryMediaCleanup"
    private static let pendingShowAssetFullCleanupKey = "BeforeShow.pendingFullShowAssetMediaCleanup"
    private static let pendingShowCleanupKey = "BeforeShow.pendingShowMediaCleanup"
    private static let pendingAssetCleanupKey = "BeforeShow.pendingAssetMediaCleanup"
    private static let pendingMemoryCleanupKey = "BeforeShow.pendingMemoryCleanup"
    private static let pendingMemoryStagingCleanupKey = "BeforeShow.pendingMemoryStagingCleanup"
    private static let legacyPendingMemoryPathCleanupKey = "BeforeShow.pendingMemoryPathCleanup"

    static var isMemoryFullCleanupPending: Bool {
        UserDefaults.standard.bool(forKey: pendingMemoryFullCleanupKey)
    }

    static var isShowAssetFullCleanupPending: Bool {
        UserDefaults.standard.bool(forKey: pendingShowAssetFullCleanupKey)
    }

    static var isFullCleanupPending: Bool {
        isMemoryFullCleanupPending || isShowAssetFullCleanupPending
    }

    static func markFullCleanupPending(memory: Bool = true, showAssets: Bool = true) {
        if memory {
            UserDefaults.standard.set(true, forKey: pendingMemoryFullCleanupKey)
        }
        if showAssets {
            UserDefaults.standard.set(true, forKey: pendingShowAssetFullCleanupKey)
        }
    }

    static func clearFullCleanupPending(memory: Bool = true, showAssets: Bool = true) {
        if memory {
            UserDefaults.standard.removeObject(forKey: pendingMemoryFullCleanupKey)
        }
        if showAssets {
            UserDefaults.standard.removeObject(forKey: pendingShowAssetFullCleanupKey)
        }
    }

    static var pendingShowCleanupIDs: [UUID] {
        let rawValues = UserDefaults.standard.stringArray(forKey: pendingShowCleanupKey) ?? []
        return rawValues.compactMap(UUID.init(uuidString:))
    }

    static func markShowCleanupPending(_ showID: UUID) {
        var ids = Set(pendingShowCleanupIDs.map(\.uuidString))
        ids.insert(showID.uuidString)
        UserDefaults.standard.set(Array(ids).sorted(), forKey: pendingShowCleanupKey)
    }

    static func clearShowCleanupPending(_ showID: UUID) {
        let remaining = pendingShowCleanupIDs
            .filter { $0 != showID }
            .map(\.uuidString)
        if remaining.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingShowCleanupKey)
        } else {
            UserDefaults.standard.set(remaining, forKey: pendingShowCleanupKey)
        }
    }

    static var pendingAssets: [PendingAsset] {
        guard let data = UserDefaults.standard.data(forKey: pendingAssetCleanupKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingAsset].self, from: data)) ?? []
    }

    static func markAssetCleanupPending(
        showID: UUID,
        kind: ShowAssetKind,
        relativePath: String
    ) {
        let pending = PendingAsset(showID: showID, kind: kind, relativePath: relativePath)
        var values = pendingAssets
        if !values.contains(pending) {
            values.append(pending)
            persistAssets(values)
        }
    }

    static func clearAssetCleanupPending(_ pending: PendingAsset) {
        persistAssets(pendingAssets.filter { $0 != pending })
    }

    private static func persistAssets(_ values: [PendingAsset]) {
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingAssetCleanupKey)
            return
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: pendingAssetCleanupKey)
        }
    }

    static var pendingMemoryCleanups: [PendingMemoryCleanup] {
        if let data = UserDefaults.standard.data(forKey: pendingMemoryCleanupKey),
           let values = try? JSONDecoder().decode([PendingMemoryCleanup].self, from: data) {
            return values.filter { pending in
                guard let path = pending.relativePath else { return true }
                return MemoryMediaLocation.isValidCommittedPath(
                    path,
                    showID: pending.showID,
                    fragmentID: pending.fragmentID
                )
            }
        }

        // Migrate the old unscoped path journal only when the path itself has the
        // canonical UUID ownership shape. Anything else is discarded instead of
        // replaying an untrusted string during startup cleanup.
        let legacy = UserDefaults.standard.stringArray(forKey: legacyPendingMemoryPathCleanupKey) ?? []
        let migrated = legacy.compactMap { path -> PendingMemoryCleanup? in
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard (components.count == 2 || components.count == 3),
                  let showID = UUID(uuidString: String(components[0])),
                  let fragmentID = UUID(uuidString: String(components[1])) else {
                return nil
            }
            if components.count == 3,
               !MemoryMediaLocation.isValidCommittedPath(
                   path,
                   showID: showID,
                   fragmentID: fragmentID
               ) {
                return nil
            }
            return PendingMemoryCleanup(
                showID: showID,
                fragmentID: fragmentID,
                relativePath: components.count == 3 ? path : nil
            )
        }
        UserDefaults.standard.removeObject(forKey: legacyPendingMemoryPathCleanupKey)
        persistMemoryCleanups(migrated)
        return migrated
    }

    static func markMemoryFragmentCleanupPending(showID: UUID, fragmentID: UUID) {
        var values = pendingMemoryCleanups
        let pending = PendingMemoryCleanup(showID: showID, fragmentID: fragmentID, relativePath: nil)
        if !values.contains(pending) {
            values.append(pending)
            persistMemoryCleanups(values)
        }
    }

    static func markMemoryPathCleanupPending(
        showID: UUID,
        fragmentID: UUID,
        relativePath: String
    ) {
        guard MemoryMediaLocation.isValidCommittedPath(
            relativePath,
            showID: showID,
            fragmentID: fragmentID
        ) else { return }
        var values = pendingMemoryCleanups
        let pending = PendingMemoryCleanup(
            showID: showID,
            fragmentID: fragmentID,
            relativePath: relativePath
        )
        if !values.contains(pending) {
            values.append(pending)
            persistMemoryCleanups(values)
        }
    }

    static func clearMemoryFragmentCleanupPending(showID: UUID, fragmentID: UUID) {
        persistMemoryCleanups(pendingMemoryCleanups.filter {
            !($0.showID == showID && $0.fragmentID == fragmentID && $0.relativePath == nil)
        })
    }

    static func clearMemoryPathCleanupPending(
        showID: UUID,
        fragmentID: UUID,
        relativePath: String
    ) {
        persistMemoryCleanups(pendingMemoryCleanups.filter {
            !($0.showID == showID && $0.fragmentID == fragmentID && $0.relativePath == relativePath)
        })
    }

    private static func persistMemoryCleanups(_ values: [PendingMemoryCleanup]) {
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingMemoryCleanupKey)
            return
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: pendingMemoryCleanupKey)
        }
    }

    static var pendingMemoryStaging: [PendingMemoryStaging] {
        guard let data = UserDefaults.standard.data(forKey: pendingMemoryStagingCleanupKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingMemoryStaging].self, from: data)) ?? []
    }

    static func markMemoryStagingCleanupPending(_ draftID: UUID) {
        var values = pendingMemoryStaging
        let pending = PendingMemoryStaging(draftID: draftID)
        if !values.contains(pending) {
            values.append(pending)
            persistMemoryStaging(values)
        }
    }

    static func clearMemoryStagingCleanupPending(_ draftID: UUID) {
        persistMemoryStaging(pendingMemoryStaging.filter { $0.draftID != draftID })
    }

    private static func persistMemoryStaging(_ values: [PendingMemoryStaging]) {
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingMemoryStagingCleanupKey)
            return
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: pendingMemoryStagingCleanupKey)
        }
    }
}

protocol LocalDataClearing {
    func clearAppOwnedLocalData() async throws -> LocalDataClearancePlan
}

actor LocalDataClearer: LocalDataClearing {
    func clearAppOwnedLocalData() async throws -> LocalDataClearancePlan {
        LocalDataClearancePolicy.defaultPlan
    }
}
