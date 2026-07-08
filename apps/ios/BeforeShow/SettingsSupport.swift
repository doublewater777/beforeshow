import Foundation

enum SettingsEntry: String, CaseIterable, Equatable {
    case proMembership = "Pro会员"
    case defaultMusicPlatform = "默认音乐平台"
    case privacyAndLocalData = "隐私与本地数据"
    case feedback = "意见反馈"
    case about = "关于开场前"
}

enum HomeStyle: String, Equatable {
    case halfCover = "half-cover"

    var displayName: String { "半屏封面" }
}

enum SettingsInformation {
    static let defaultMusicPlatformName = MusicPlatform.neteaseCloudMusic.displayName
    static let musicPlatformNames = MusicPlatform.allCases.map(\.displayName)

    static let orderedEntries: [SettingsEntry] = [
        .proMembership,
        .defaultMusicPlatform,
        .privacyAndLocalData,
        .feedback,
        .about
    ]
}

enum PrivacyLocalDataCopy {
    static let points = [
        "票务截图只用于设备端 OCR，截图不会为了识别上传。",
        "相册里的图片和视频以系统相册引用保存，原文件仍由系统相册管理。",
        "App 内创建的语音片段保存在 BeforeShow 本地沙盒。",
        "候选曲目和往返草稿只在用户主动触发时发起 AI 请求。"
    ]

    static let clearDataExplanation = "清除本地数据会删除 BeforeShow 创建和保存的本地数据，包括现场、设置、生成结果和 App 内录音；不会删除系统相册中的原始图片或视频。"
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
            "SwiftData 中的现场、候选曲目、去程计划和偏好设置",
            "BeforeShow 沙盒中的 App 内录音与临时缓存"
        ],
        preservesSystemData: [
            "系统相册中的原始图片和视频",
            "Apple Music、网易云音乐、QQ 音乐或 Spotify 中的内容"
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
