import Foundation

struct NotificationNodeContent {
    let body: String
    let destination: NotificationDeepLink.Destination
    var feature: RecommendedFeature?
    var discID: String?
}

/// 听歌与前一天提醒用现场名作标题；其他节点保留状态标题与正文现场名。
/// 正文继续先说事实（还有几天、开场时刻、场馆），再说此刻可以顺手做的事。
/// 不写「试试」「新功能」「你还没」；散场后的文案不预设好坏（ADR 0037）。
struct NotificationCopy {
    let context: NotificationCopyContext

    func displayTitle(for milestone: ShowNotificationMilestone) -> String {
        switch milestone {
        case .listeningReminder, .oneDayBefore, .interestedPerformance,
             .addedFollowUp, .fourteenDaysBefore, .openingMemory,
             .sevenDaysBefore, .threeDaysBefore, .afterShow, .footprintArrival:
            return context.showName
        case .showDayMorning:
            return BSLocalization.text("今天开场")
        case .showDay:
            return BSLocalization.text("快开场了")
        case .postShowRitual:
            return BSLocalization.text("散场后")
        }
    }

    /// Status titles ("快开场了") name the show on the first body line; show-name titles don't repeat it.
    func displayBody(_ message: String, for milestone: ShowNotificationMilestone) -> String {
        displayTitle(for: milestone) == context.showName ? message : context.showName + "\n" + message
    }

    func recommendation(_ feature: RecommendedFeature, daysLeft: Int) -> String? {
        let line: String
        switch feature {
        case .companion:
            line = BSLocalization.text("和谁一起去？记下来，散场后会留在足迹里。")
        case .timetable:
            line = BSLocalization.text("把时刻表存进这里，在现场能随时查看。")
        default:
            return nil
        }
        return BSLocalization.format("还有 %lld 天。", Int64(max(0, daysLeft))) + line
    }

    func oneDayBefore(hasDisc: Bool, isWanted: Bool, weatherTip: String? = nil) -> String {
        let tail: String
        if let weatherTip, !weatherTip.isEmpty {
            tail = weatherTip
        } else if isWanted {
            tail = BSLocalization.text("听听你标记的那些艺人吧。")
        } else if hasDisc {
            tail = BSLocalization.text("挑几首常演的热门歌预热一下。")
        } else if let artist = context.artistName {
            tail = BSLocalization.format("听听%@的歌。", artist)
        } else {
            tail = BSLocalization.text("先听听这场的歌吧。")
        }
        let lead = context.isMultiDay ? BSLocalization.text("明天开始。") : BSLocalization.text("明天开场。")
        return BSLocalization.format("%1$@%2$@", lead, tail)
    }

    func morning() -> String {
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
        return lead + BSLocalization.text("看看时刻表，确认想看的艺人场次。")
    }

    /// `remainingSeconds` 只在临时补发时给出，按真实剩余时间写。
    func showDay(remainingSeconds: Int?, weatherTip: String? = nil, sunsetArtist: String? = nil) -> String {
        let placeSuffix = context.place.map { " · \($0)" } ?? ""
        let extra: String
        if let weatherTip, !weatherTip.isEmpty {
            extra = weatherTip
        } else if let sunsetArtist, !sunsetArtist.isEmpty {
            extra = BSLocalization.format("今天的日落现场是%@。", sunsetArtist)
        } else {
            extra = ""
        }
        guard let remainingSeconds else {
            // Without a start time this fires at noon; it can't promise "3 hours".
            guard let clock = context.startClock else {
                return BSLocalization.text("今天开场") + placeSuffix + BSLocalization.text("。记得留好出门时间。") + extra
            }
            return BSLocalization.format("%@ 开场", clock) + placeSuffix + BSLocalization.text("。还有 3 小时，准备出门。") + extra
        }
        let remaining = max(60, remainingSeconds)
        let lead = remaining >= 3_600
            ? BSLocalization.format("%lld 小时后开场", Int64(remaining / 3_600))
            : BSLocalization.format("%lld 分钟后开场", Int64(remaining / 60))
        return lead + placeSuffix + BSLocalization.text("。别错过开场。") + extra
    }

    func postShowRitual(isConfirmed: Bool) -> String {
        isConfirmed
            ? BSLocalization.text("散场了，记下这一刻。")
            : BSLocalization.text("散场了吗？记下时间，聊聊这场怎么样。")
    }

    func afterShow(isConfirmed: Bool) -> String {
        isConfirmed
            ? BSLocalization.text("这场结束了，留下一点记忆。")
            : BSLocalization.text("这场几点散场？记下时间，也可以留一句感受。")
    }

    func afterRetention(_ feature: RecommendedFeature, nextShow: NotificationNextShow?) -> String? {
        switch feature {
        case .footprint:
            return BSLocalization.text("已收进足迹，可以生成一张卡片留念。")
        case .nextShow:
            guard let nextShow else { return nil }
            return BSLocalization.format("这场已收进足迹。下一场是 %1$@，还有 %2$lld 天。", nextShow.name, Int64(nextShow.daysUntil))
        case .addShow:
            return BSLocalization.text("这场已收进足迹。有新的演出计划了吗？可以记下下一场。")
        default:
            return nil
        }
    }
}
