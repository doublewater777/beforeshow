import Foundation
import ObjectiveC
import SwiftData
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

enum AppLanguage: String, CaseIterable, Identifiable, Equatable {
    case system = ""
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return BSLocalization.text("跟随系统")
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .zhHant: return Locale(identifier: "zh-Hant")
        case .en: return Locale(identifier: "en")
        }
    }

    var bundle: Bundle? {
        guard self != .system else { return nil }
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}

/// In-app language override, active immediately without an app restart.
///
/// `BSLocalization` resolves through `Bundle.main.localizedString`, so swapping
/// `Bundle.main`'s class for `LanguageSwizzledBundle` makes every lookup hit the
/// selected `lproj`. `.system` keeps the swizzled class but drops the override
/// bundle, so lookups fall through to the device language.
nonisolated(unsafe) private var languageBundleAssociationKey: UInt8 = 0

private final class LanguageSwizzledBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let override = objc_getAssociatedObject(self, &languageBundleAssociationKey) as? Bundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return override.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum AppLanguageManager {
    static let storageKey = "appLanguage"

    static var persisted: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    static func apply(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        object_setClass(Bundle.main, LanguageSwizzledBundle.self)
        objc_setAssociatedObject(
            Bundle.main,
            &languageBundleAssociationKey,
            language.bundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

@MainActor
final class AppLanguageController: ObservableObject {
    static let shared = AppLanguageController()
    @Published var language: AppLanguage

    private init() {
        language = AppLanguageManager.persisted
    }

    func select(_ language: AppLanguage) {
        AppLanguageManager.apply(language)
        self.language = language
    }
}

/// 在官网链接上追加当前 App 语言，让 App 内打开的页面跟随语言切换。
@MainActor
func localizedSiteURL(_ base: URL) -> URL {
    let language = AppLanguageController.shared.language
    guard language != .system else { return base }
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
    var queryItems = components?.queryItems ?? []
    queryItems.append(URLQueryItem(name: "lang", value: language.rawValue))
    components?.queryItems = queryItems
    return components?.url ?? base
}

enum SettingsInformation {
    static let orderedEntries: [SettingsEntry] = [
        .proMembership,
        .privacyAndLocalData,
        .feedback,
        .about
    ]
}

struct SettingsMembershipSummary: Equatable {
    let title: String
    let subtitle: String

    init(entitlement: ProEntitlementState) {
        switch entitlement {
        case .free:
            self.init(title: BSLocalization.text("免费版"), subtitle: BSLocalization.text("可保存 20 场现场"))
        case .active:
            self.init(title: BSLocalization.text("Pro 已启用"), subtitle: BSLocalization.text("可以无限添加现场"))
        case .expired:
            self.init(title: BSLocalization.text("Pro 已过期"), subtitle: BSLocalization.text("已有本地内容仍可查看和编辑"))
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
    let action: NotificationSettingsAction

    init(authorizationState: NotificationAuthorizationState) {
        switch authorizationState {
        case .notDetermined:
            self.init(
                status: BSLocalization.text("尚未开启"),
                action: .requestPermission
            )
        case .denied:
            self.init(
                status: BSLocalization.text("未开启"),
                action: .openSystemSettings
            )
        case .authorized, .provisional:
            self.init(status: BSLocalization.text("已开启"), action: .openSystemSettings)
        }
    }

    init(status: String, action: NotificationSettingsAction) {
        self.status = status
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

struct LocalDataInventory: Equatable {
    var showCount = 0
    var memoryFragmentCount = 0
    var assetCount = 0
    var dynamicCoverCount = 0
    var appBytes: Int64 = 0
    var mediaBytes: Int64 = 0

    var isEmpty: Bool {
        showCount == 0 && memoryFragmentCount == 0 && assetCount == 0 && dynamicCoverCount == 0 && mediaBytes == 0
    }
}

@MainActor
enum LocalDataInventoryService {
    static func compute(modelContext: ModelContext) async -> LocalDataInventory {
        var inventory = LocalDataInventory()
        inventory.showCount = (try? modelContext.fetchCount(FetchDescriptor<Show>())) ?? 0
        inventory.memoryFragmentCount = (try? modelContext.fetchCount(FetchDescriptor<MemoryFragment>())) ?? 0
        inventory.assetCount = (try? modelContext.fetchCount(FetchDescriptor<ShowAsset>())) ?? 0
        inventory.dynamicCoverCount = (try? modelContext.fetchCount(FetchDescriptor<DynamicCover>())) ?? 0

        inventory.appBytes = directoryBytes(at: URL(fileURLWithPath: NSHomeDirectory()))

        var bytes: Int64 = 0
        bytes += directoryBytes(at: await ShowAssetMediaStore.shared.rootDirectoryURL())
        bytes += directoryBytes(at: await DynamicCoverMediaStore.shared.rootDirectoryURL())
        bytes += directoryBytes(at: MemoryFragmentMediaStore.shared.location.rootDirectory)
        inventory.mediaBytes = bytes
        return inventory
    }

    static func directoryBytes(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
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
            URLQueryItem(name: "subject", value: BSLocalization.text("BeforeShow 反馈")),
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
