import Foundation

// MARK: Primary action：几乎每个人此刻都会做、一下就完成的那件事
// 开场前 → 听几首；当天未开场 → 看路线；现场中与音乐节当日落幕 → 无；
// 散场停留期 → 听今晚的歌（没记歌单时听几首）；停留期后没有下一场 → 添加下一场；
// 时间待定 → 填上新时间；已取消 → 无。

extension HomeCountdownLockup {
    enum PrimaryAction: Equatable {
        case listen
        case route
        case listenTonight
        case addShow
        case fillNewDate

        var title: String {
            switch self {
            case .listen: return BSLocalization.text("听几首")
            case .route: return BSLocalization.text("看路线")
            case .listenTonight: return BSLocalization.text("听今晚的歌")
            case .addShow: return BSLocalization.text("添加下一场")
            case .fillNewDate: return BSLocalization.text("填上新时间")
            }
        }

        /// 播放中按钮变成暂停，不换成别的动作。
        var playsMusic: Bool { self == .listen || self == .listenTonight }
    }

    nonisolated static func primaryAction(
        timeState: CurrentShowTimeState,
        now: Date,
        hasPlayedSongs: Bool,
        hasFutureShow: Bool
    ) -> PrimaryAction? {
        switch timeState.kind {
        case .before:
            return .listen
        case .today:
            if let start = timeState.effectiveStartTime, now >= start { return nil }
            return .route
        case .dayEnded, .canceled:
            return nil
        case .postShow:
            return hasPlayedSongs ? .listenTonight : .listen
        case .ended:
            return hasFutureShow ? nil : .addShow
        case .postponed:
            return .fillNewDate
        }
    }
}
