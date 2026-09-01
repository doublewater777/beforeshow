import CloudKit
import Foundation

enum CompanionSharingPresentation {
    static func acceptedMessage(ownerDisplayName: String?) -> String {
        BSLocalization.format(
            "已与%@确认同行",
            ownerDisplayName ?? BSLocalization.text("朋友")
        )
    }

    static var companionLeftMessage: String {
        BSLocalization.text("同行者已退出，同行关系已取消")
    }

    static var membershipSyncWarning: String {
        BSLocalization.text("同行成员状态暂时无法同步，请稍后重试")
    }

    static func userMessage(for error: Error) -> String {
        if let sharing = error as? CompanionSharingError {
            switch sharing {
            case .iCloudAccountUnavailable:
                return BSLocalization.text("需要登录 iCloud 才能邀请同行")
            case .networkFailure:
                return BSLocalization.text("网络不可用，请稍后重试")
            case .sharePreparationFailed:
                return BSLocalization.text("邀请创建失败，请稍后重试")
            case .acceptFailed:
                return BSLocalization.text("接受邀请失败，请确认链接有效")
            case .sessionNotFound:
                return BSLocalization.text("找不到这场同行邀请")
            case .invalidPayload:
                return BSLocalization.text("邀请内容无效")
            case .permissionDenied:
                return BSLocalization.text("没有权限更新同行状态")
            case .conflict:
                return BSLocalization.text("同行状态已变更，请刷新后重试")
            case .statusSyncPending:
                return BSLocalization.text("已接受邀请，但状态同步失败，请稍后刷新")
            }
        }
        if error is ShowCompanionMutationError {
            return BSLocalization.text("同行状态无法更新")
        }
        if let cloudKitError = error as? CKError {
            return message(forCloudKit: cloudKitError)
        }
        return BSLocalization.format("同行操作失败：%@", error.localizedDescription)
    }

    private static func message(forCloudKit error: CKError) -> String {
        switch error.code {
        case .notAuthenticated, .managedAccountRestricted:
            return BSLocalization.text("需要登录 iCloud 才能邀请同行")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return BSLocalization.text("网络不可用，请稍后重试")
        case .permissionFailure:
            return BSLocalization.text("没有权限创建同行邀请，请确认 iCloud 云盘已打开")
        case .quotaExceeded:
            return BSLocalization.text("iCloud 空间不足，无法创建同行邀请")
        case .invalidArguments, .constraintViolation:
            return BSLocalization.text("邀请创建失败：CloudKit 拒绝了这次请求")
        case .serverRejectedRequest:
            return BSLocalization.text("邀请创建失败：CloudKit 容器未就绪，请在 Xcode 打开 iCloud 能力并确认 Development 环境可用")
        default:
            return BSLocalization.format("邀请创建失败：%@", error.localizedDescription)
        }
    }
}
