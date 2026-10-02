import Foundation

struct NotificationNodeContent {
    let body: String
    let destination: NotificationDeepLink.Destination
    var feature: RecommendedFeature?
}

/// 标题是现场名，正文先说事实（还有几天、开场时刻、场馆），再说此刻可以顺手做的事。
/// 不写「试试」「新功能」「你还没」；散场后的文案不预设好坏（ADR 0037）。
struct NotificationCopy {
    let context: NotificationCopyContext

    var title: String { context.showName }

    func recommendation(_ feature: RecommendedFeature, daysLeft: Int) -> String {
        BSLocalization.format("还有 %lld 天。", Int64(max(0, daysLeft))) + recommendationLine(feature)
    }

    private func recommendationLine(_ feature: RecommendedFeature) -> String {
        switch feature {
        case .widget:
            return BSLocalization.text("把小组件放到主屏幕。")
        case .companion:
            return BSLocalization.text("和朋友一起去？邀请他们加入这场。")
        case .listen:
            if let artist = context.artistName {
                return BSLocalization.format("先听听 %@ 的歌。", artist)
            }
            return BSLocalization.text("先听听这场的歌。")
        case .timetable:
            return BSLocalization.text("时刻表出来了保存在这里，可快速打开。")
        case .dispersal:
            return BSLocalization.text("这场结束了，留下一点记忆。")
        case .memoryFragments:
            return BSLocalization.text("把这场的照片放进记忆碎片。")
        case .footprint:
            return BSLocalization.text("已收进足迹，可以做一张回忆卡片。")
        case .nextShow, .addShow:
            return BSLocalization.text("添加下一场现场。")
        }
    }

    func oneDayBefore() -> String {
        let tail = context.artistName.map { BSLocalization.format("今晚可以再听听 %@ 的歌。", $0) }
            ?? BSLocalization.text("今晚可以再听听这场的歌。")
        if context.isMultiDay {
            let lead = context.startClock.map { BSLocalization.format("明天 %@ 开始。", $0) }
                ?? BSLocalization.text("明天开始。")
            return lead + tail
        }
        let lead = context.startClock.map { BSLocalization.format("明天 %@ 开场。", $0) }
            ?? BSLocalization.text("明天开场。")
        return lead + tail
    }

    func morning(showsTimetable: Bool) -> String {
        let lead: String
        switch (context.startClock, context.place) {
        case let (clock?, place?):
            lead = BSLocalization.format("今天 %1$@ 开场 · %2$@。", clock, place)
        case let (clock?, nil):
            lead = BSLocalization.format("今天 %@ 开场。", clock)
        case let (nil, place?):
            lead = BSLocalization.format("今天开场 · %@。", place)
        case (nil, nil):
            lead = BSLocalization.text("今天开场。")
        }
        return lead + (showsTimetable
            ? BSLocalization.text("看一下时刻表，别错过想看的艺术家。")
            : BSLocalization.text("出门前看一下路线。"))
    }

    /// `remainingSeconds` 只在临时补发时给出，按真实剩余时间写。
    func showDay(remainingSeconds: Int?) -> String {
        let placeSuffix = context.place.map { " · \($0)" } ?? ""
        guard let remainingSeconds else {
            let lead = context.startClock.map { BSLocalization.format("%@ 开场", $0) }
                ?? BSLocalization.text("今天开场")
            return lead + placeSuffix + BSLocalization.text("。还有 3 小时，准备出门。")
        }
        let remaining = max(60, remainingSeconds)
        let lead = remaining >= 3_600
            ? BSLocalization.format("%lld 小时后开场", Int64(remaining / 3_600))
            : BSLocalization.format("%lld 分钟后开场", Int64(remaining / 60))
        return lead + placeSuffix + BSLocalization.text("。别错过开场。")
    }

    var opening: String {
        BSLocalization.text("开始了。现场怎么样，可以记一段记忆。")
    }

    func postShowRitual(isConfirmed: Bool) -> String {
        isConfirmed
            ? BSLocalization.text("散场了，记下这一刻。")
            : BSLocalization.text("散场了吗？记下时间，也记下这一刻的感受。")
    }

    func afterShow(isConfirmed: Bool) -> String {
        isConfirmed
            ? BSLocalization.text("这场结束了，留下一点记忆。")
            : BSLocalization.text("这场几点散场？记下时间，也可以留一句感受。")
    }

    var confirmEndForFootprint: String {
        BSLocalization.text("这场几点散场？记下时间，这场就会收进足迹。")
    }

    func afterRetention(_ feature: RecommendedFeature, nextShow: NotificationNextShow?) -> String {
        if feature == .nextShow, let nextShow {
            return BSLocalization.format("下一场是 %1$@，还有 %2$lld 天。", nextShow.name, Int64(nextShow.daysUntil))
        }
        return recommendationLine(feature)
    }
}
