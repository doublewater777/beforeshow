import Foundation

struct ShowTip: Equatable {
    let message: String
    let buttonTitle: String
    let action: ShowTipAction

    enum ShowTipAction: Equatable {
        case candidateSongs
        case outboundPlan
        case showPreparation
        case showVideos
        case showFragments
    }
}

enum ShowTipsResolver {
    static func resolve(
        phase: CurrentShowTimeState,
        hasCandidateSongs: Bool,
        hasOutboundPlan: Bool,
        hasFragments: Bool,
        now: Date = Date()
    ) -> ShowTip? {
        switch phase.kind {
        case .before:
            let days = phase.dayDistance
            if days > 14 {
                return nil
            }

            if days >= 8 {
                return ShowTip(message: "还有 \(days) 天，先去熟悉一下曲目？", buttonTitle: "去看看", action: .candidateSongs)
            }

            if days >= 2 {
                return hasOutboundPlan
                    ? nil
                    : ShowTip(message: "还有 \(days) 天，先定好怎么去？", buttonTitle: "生成计划", action: .outboundPlan)
            }

            if days >= 1 {
                return ShowTip(message: "明天开场，出门前要带的都确认了吗？", buttonTitle: "看准备", action: .showPreparation)
            }

            return ShowTip(message: "就是今天，先定好怎么到现场？", buttonTitle: "生成计划", action: .outboundPlan)

        case .today:
            if let startTime = phase.effectiveStartTime, now < startTime {
                return hasOutboundPlan
                    ? ShowTip(message: "就是今天，出发时间再确认一下？", buttonTitle: "查看去程", action: .outboundPlan)
                    : ShowTip(message: "就是今天，先定好怎么到现场？", buttonTitle: "生成计划", action: .outboundPlan)
            }

            return ShowTip(message: "正在现场，拍一张留给这场？", buttonTitle: "记一笔", action: .showFragments)

        case .postShow:
            return hasFragments
                ? nil
                : ShowTip(message: "刚散场，把这一刻先留下来？", buttonTitle: "记一笔", action: .showFragments)

        case .ended, .canceled, .postponed:
            return nil
        }
    }
}
