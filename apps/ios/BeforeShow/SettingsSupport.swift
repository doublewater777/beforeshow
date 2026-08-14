import Foundation
import UIKit

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

struct SettingsMembershipSummary: Equatable {
    let title: String
    let subtitle: String

    init(entitlement: ProEntitlementState) {
        switch entitlement {
        case .free:
            self.init(title: "免费版", subtitle: "可保存 1 场现场")
        case .active:
            self.init(title: "Pro 已启用", subtitle: "可以无限添加现场")
        case .expired:
            self.init(title: "Pro 已过期", subtitle: "已有本地内容仍可查看和编辑")
        }
    }

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

enum NotificationSettingsAction: Equatable {
    case requestPermission
    case openSystemSettings
}

struct NotificationSettingsPresentation: Equatable {
    let status: String
    let subtitle: String
    let action: NotificationSettingsAction

    init(authorizationState: NotificationAuthorizationState) {
        switch authorizationState {
        case .notDetermined:
            self.init(
                status: "尚未开启",
                subtitle: "轻点开启开场提醒",
                action: .requestPermission
            )
        case .denied:
            self.init(
                status: "未开启",
                subtitle: "去系统设置开启通知",
                action: .openSystemSettings
            )
        case .authorized, .provisional:
            self.init(status: "已开启", subtitle: "可在系统设置中调整", action: .openSystemSettings)
        }
    }

    init(status: String, subtitle: String, action: NotificationSettingsAction) {
        self.status = status
        self.subtitle = subtitle
        self.action = action
    }
}

struct AppVersionInformation: Equatable {
    let marketingVersion: String
    let buildNumber: String

    init(infoDictionary: [String: Any]) {
        self.init(
            marketingVersion: infoDictionary["CFBundleShortVersionString"] as? String ?? "未知版本",
            buildNumber: infoDictionary["CFBundleVersion"] as? String ?? "未知构建"
        )
    }

    init(marketingVersion: String, buildNumber: String) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    static var current: AppVersionInformation {
        AppVersionInformation(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    var compactCopy: String { "v\(marketingVersion)" }
    var fullCopy: String { "版本 \(marketingVersion)（构建 \(buildNumber)）" }
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
    var diagnosticsProvider: () -> FeedbackDiagnostics

    init(diagnosticsProvider: @escaping () -> FeedbackDiagnostics = {
        FeedbackDiagnostics(
            appVersion: AppVersionInformation.current.marketingVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }) {
        self.diagnosticsProvider = diagnosticsProvider
    }

    init(appVersion: AppVersionInformation, osVersion: String) {
        self.init {
            FeedbackDiagnostics(appVersion: appVersion.marketingVersion, osVersion: osVersion)
        }
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

struct FeedbackShareTextBuilder {
    func build(from payload: FeedbackPayload) -> String {
        var text = [
            "类型：\(payload.category.rawValue)",
            "反馈：\(payload.message)"
        ].joined(separator: "\n")

        if let diagnostics = payload.diagnostics {
            text += "\n\n" +
                "诊断信息\nApp 版本：\(diagnostics.appVersion)\n系统版本：\(diagnostics.osVersion)"
        }

        return text
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
            "动态封面正反面偏好",
            "BeforeShow 沙盒中的临时缓存"
        ],
        preservesSystemData: [
            "系统相册中的原始图片和视频"
        ]
    )
}

/// Retry journal for ticket/timetable files only. Memory-fragment cleanup keeps
/// the implementation from `main` and deliberately does not use this type.
enum ShowAssetCleanupRetry {
    struct PendingAsset: Codable, Equatable {
        let showID: UUID
        let kind: ShowAssetKind
        let relativePath: String
    }

    struct PendingDynamicCover: Codable, Equatable {
        let showID: UUID
        let relativePath: String
    }

    private static let pendingFullCleanupKey = "BeforeShow.pendingFullShowAssetMediaCleanup"
    private static let pendingDynamicCoverCleanupKey = "BeforeShow.pendingDynamicCoverMediaCleanup"
    private static let preparedFullCleanupKey = "BeforeShow.preparedShowAssetCleanup"
    // Keep the pre-split ticket markers readable so an interrupted ticket-only
    // cleanup from an earlier build is still recovered after this refactor.
    private static let pendingShowCleanupKey = "BeforeShow.pendingShowMediaCleanup"
    private static let pendingAssetCleanupKey = "BeforeShow.pendingAssetMediaCleanup"

    static var isFullCleanupPending: Bool {
        UserDefaults.standard.bool(forKey: pendingFullCleanupKey)
    }

    static var isFullCleanupPrepared: Bool {
        UserDefaults.standard.bool(forKey: preparedFullCleanupKey)
    }

    static func markFullCleanupPrepared() {
        UserDefaults.standard.set(true, forKey: preparedFullCleanupKey)
        UserDefaults.standard.synchronize()
    }

    static func clearFullCleanupPrepared() {
        UserDefaults.standard.removeObject(forKey: preparedFullCleanupKey)
    }

    static func markFullCleanupPending() {
        UserDefaults.standard.set(true, forKey: pendingFullCleanupKey)
        UserDefaults.standard.synchronize()
    }

    static func clearFullCleanupPending() {
        UserDefaults.standard.removeObject(forKey: pendingFullCleanupKey)
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
        guard ShowAsset.isValidRelativePath(relativePath, showID: showID, kind: kind) else { return }
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

    static var pendingDynamicCovers: [PendingDynamicCover] {
        guard let data = UserDefaults.standard.data(forKey: pendingDynamicCoverCleanupKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingDynamicCover].self, from: data)) ?? []
    }

    static func markDynamicCoverCleanupPending(showID: UUID, relativePath: String) {
        guard DynamicCover.isValidRelativePath(relativePath, showID: showID) else { return }
        let pending = PendingDynamicCover(showID: showID, relativePath: relativePath)
        var values = pendingDynamicCovers
        if !values.contains(pending) {
            values.append(pending)
            persistDynamicCovers(values)
        }
    }

    static func clearDynamicCoverCleanupPending(_ pending: PendingDynamicCover) {
        persistDynamicCovers(pendingDynamicCovers.filter { $0 != pending })
    }

    private static func persistDynamicCovers(_ values: [PendingDynamicCover]) {
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingDynamicCoverCleanupKey)
            return
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: pendingDynamicCoverCleanupKey)
        }
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
}

/// 真实反馈渠道：`mailto:` 邮件收件人。RELEASE/DEBUG 共用同一地址。
/// `mailto:` 是系统 URL scheme，不需要 `LSApplicationQueriesSchemes` 声明。
enum FeedbackDestination {
    /// 反馈收件邮箱。占位待用户替换为实际网易 163 邮箱。
    static let address = "feedback@163.com"

    static func mailtoURL(prefilledBody: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "BeforeShow 反馈"),
            URLQueryItem(name: "body", value: prefilledBody)
        ]
        return components.url
    }
}

/// 调起邮件 app 的薄包装。`@Environment(\.openURL)` 不提供 completion，
/// 改用 UIKit 的 `UIApplication.shared.open(_:options:completionHandler:)` 才能区分
/// "用户接受了跳转" / "未配邮件账户被系统拒绝"——避免假阳性"已发送 ✓"。
@MainActor
enum FeedbackMailOpener {
    static func open(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { accepted in
                continuation.resume(returning: accepted)
            }
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
