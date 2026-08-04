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
        "票根与时刻表默认保存在 BeforeShow 的设备本地 App 沙盒中；正常保存流程不会主动上传这些图片，也不会加入同行 CloudKit 分享记录。",
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
            "BeforeShow 沙盒中保存的记忆照片和视频副本",
            "BeforeShow 沙盒中的临时缓存"
        ],
        preservesSystemData: [
            "系统相册中的原始图片和视频"
        ]
    )
}

protocol LocalDataClearing {
    func clearAppOwnedLocalData() async throws -> LocalDataClearancePlan
}

actor LocalDataClearer: LocalDataClearing {
    func clearAppOwnedLocalData() async throws -> LocalDataClearancePlan {
        LocalDataClearancePolicy.defaultPlan
    }
}
