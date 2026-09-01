import Foundation

// MARK: - Footprint Archive Share Copy

@MainActor
enum FootprintArchiveShareCopy {
    static func title(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("分享完整档案")
        case .artist: return BSLocalization.text("分享艺人档案")
        case .city: return BSLocalization.text("分享城市档案")
        case .venue: return BSLocalization.text("分享场馆档案")
        }
    }

    static func subtitle(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("总场次、艺人、城市和场馆偏好会汇总在同一张卡片。")
        case .artist: return BSLocalization.text("突出最常看的艺人，并展示艺人排行前三名。")
        case .city: return BSLocalization.text("突出你去过最多的城市，并展示城市排行前三名。")
        case .venue: return BSLocalization.text("突出最熟悉的场馆，并展示场馆排行前三名。")
        }
    }

    static func chip(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("总览")
        case .artist: return BSLocalization.text("艺人")
        case .city: return BSLocalization.text("城市")
        case .venue: return BSLocalization.text("场馆")
        }
    }

    static func kicker(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return "MY LIVE ARCHIVE"
        case .artist: return "ARTIST ARCHIVE"
        case .city: return "CITY ARCHIVE"
        case .venue: return "VENUE ARCHIVE"
        }
    }

    static func filename(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("我的完整现场档案")
        case .artist: return BSLocalization.text("我的艺人现场档案")
        case .city: return BSLocalization.text("我的城市现场档案")
        case .venue: return BSLocalization.text("我的场馆现场档案")
        }
    }

    static func subject(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("我的 BeforeShow 现场总览")
        case .artist: return BSLocalization.text("我的 BeforeShow 艺人档案")
        case .city: return BSLocalization.text("我的 BeforeShow 城市足迹")
        case .venue: return BSLocalization.text("我的 BeforeShow 场馆足迹")
        }
    }

    static func text(for category: FootprintCategory, archive: FootprintArchiveSnapshot) -> String {
        switch category {
        case .overview:
            var lines = [
                subject(for: category),
                BSLocalization.format("%lld 场现场 · %lld 位艺人 · %lld 座城市 · %lld 个场馆", archive.shows.count, archive.artists.count, archive.cities.count, archive.venues.count),
                BSLocalization.format("在现场待过 %@", ShowDurationFormatter.aggregate(totalMinutes: archive.totalDurationMinutes))
            ]
            if let top = archive.artists.first { lines.append(BSLocalization.format("最常看：%@ · %lld 场", top.name, top.count)) }
            if let first = archive.firstShow {
                lines.append(BSLocalization.format("第一场：%@ · %@", footprintMonthText(first.effectiveDate, calendar: first.timingCalendar()), first.name))
            }
            return lines.joined(separator: "\n")
        case .artist:
            return [
                subject(for: category),
                BSLocalization.format("一共看过 %lld 位艺人", archive.artists.count),
                leadingLine(BSLocalization.text("最常看"), from: archive.artists),
                rankingLine(BSLocalization.text("艺人排行"), items: archive.artists)
            ].joined(separator: "\n")
        case .city:
            return [
                subject(for: category),
                BSLocalization.format("现场足迹走过 %lld 座城市", archive.cities.count),
                leadingLine(BSLocalization.text("最常去"), from: archive.cities),
                rankingLine(BSLocalization.text("城市排行"), items: archive.cities)
            ].joined(separator: "\n")
        case .venue:
            return [
                subject(for: category),
                BSLocalization.format("一共到过 %lld 个场馆", archive.venues.count),
                leadingLine(BSLocalization.text("最熟悉"), from: archive.venues),
                rankingLine(BSLocalization.text("场馆排行"), items: archive.venues)
            ].joined(separator: "\n")
        }
    }

    private static func leadingLine(_ label: String, from items: [FootprintRankItem]) -> String {
        guard let first = items.first else { return BSLocalization.format("%@：还没有记录", label) }
        return BSLocalization.format("%@：%@ · %lld 场", label, first.name, first.count)
    }

    private static func rankingLine(_ label: String, items: [FootprintRankItem]) -> String {
        let ranking = items.prefix(3).map { BSLocalization.format("%@ %lld 场", $0.name, $0.count) }.joined(separator: "、")
        return BSLocalization.format("%@：%@", label, ranking.isEmpty ? BSLocalization.text("还没有记录") : ranking)
    }
}
