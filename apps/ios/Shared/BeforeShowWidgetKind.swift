import WidgetKit

enum BeforeShowWidgetKind {
    static let homeCountdown = "BeforeShowCountdownWidget"
    static let lockScreenCountdown = "BeforeShowLockScreenCountdownWidget"

    static var all: [String] { [homeCountdown, lockScreenCountdown] }

    static func reloadAllTimelines() {
        for kind in all {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}

enum LockScreenCountdownCopy {
    /// 圆形锁屏放不下 `hh:mm:ss`。按设计稿收成 `H:MM`。
    static func circularNearClock(remainingSeconds: Int) -> String {
        let remaining = max(0, remainingSeconds)
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
