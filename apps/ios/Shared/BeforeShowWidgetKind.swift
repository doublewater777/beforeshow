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
    /// live 已进行时长收成 `H:MM`,跳秒在圆形里放不下。
    static func circularLiveElapsed(elapsedSeconds: Int) -> String {
        clockText(totalMinutes: max(0, elapsedSeconds) / 60)
    }

    private static func clockText(totalMinutes: Int) -> String {
        String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}
