import Foundation

/// 围绕单场现场的工具状态汇总。
///
/// 首页（当前现场）和现场详情页都需要展示「候选曲目 / 去程计划 / 现场准备 /
/// 现场视频 / 现场碎片」的状态文案。这里把计数与状态文案计算收敛到一处，
/// 避免两个页面各算一遍、文案漂移。
///
/// Tips 文案与显隐由 ShowTipsResolver 单独负责；
/// 本结构只负责客观的状态数据与文案（工具区 status 等）。
struct ShowToolSummary {
    let show: Show

    let candidateSongCount: Int
    let hasOutboundPlan: Bool

    let checkedPreparationCount: Int
    let preparationTotal: Int

    let showFragmentsCount: Int

    init(
        show: Show,
        candidateGroups: [CandidateSongGroup],
        candidateSongs: [CandidateSong],
        roundTripPlans: [RoundTripPlan],
        preparationPlans: [ShowPreparationPlan]
    ) {
        self.show = show

        let groupsForShow = candidateGroups.filter { $0.showID == show.id }
        let groupIDs = Set(groupsForShow.map(\.id))
        self.candidateSongCount = candidateSongs.filter { groupIDs.contains($0.groupID) }.count

        let plan = roundTripPlans.first { $0.showID == show.id }
        self.hasOutboundPlan = plan?.hasSavedDeparturePlan == true || Self.trimmed(plan?.outboundContent) != nil

        let preparationPlan = preparationPlans.first { $0.showID == show.id }
        let suggestions = ShowPreparationGuide().sections(for: show).flatMap(\.suggestions)
        self.preparationTotal = max(suggestions.count, 1)
        self.checkedPreparationCount = preparationPlan.map { plan in
            suggestions.filter { plan.isChecked($0.text) }.count
        } ?? 0

        self.showFragmentsCount = show.fragments.count
    }

    // MARK: - Derived Flags

    var hasCandidateSongs: Bool { candidateSongCount > 0 }
    var hasCheckedAllPreparation: Bool { checkedPreparationCount >= preparationTotal }
    var hasFragments: Bool { showFragmentsCount > 0 }

    // MARK: - Status Copy

    var candidateSongsStatus: String {
        hasCandidateSongs ? "\(candidateSongCount) 首候选" : "未生成"
    }

    var roundTripStatus: String {
        hasOutboundPlan ? "已保存" : "缺信息"
    }

    var preparationStatus: String {
        hasCheckedAllPreparation ? "已确认" : "\(checkedPreparationCount)/\(preparationTotal) 已确认"
    }

    var fragmentsStatus: String {
        hasFragments ? "\(showFragmentsCount) 条已存" : "还没记录"
    }

    // MARK: - Helpers

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
