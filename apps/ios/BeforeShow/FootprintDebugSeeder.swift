#if DEBUG
import SwiftData
import Foundation

@MainActor
enum FootprintDebugSeeder {
    static func seedIfRequested(in modelContext: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("--seed-footprints-samples") else { return }

        do {
            let existing = try modelContext.fetch(FetchDescriptor<Show>())
            let existingNames = Set(existing.map(\.name))
            for sample in samples where !existingNames.contains(sample.name) {
                modelContext.insert(try sample.makeShow())
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed footprint samples: \(error)")
        }
    }

    private static var samples: [ShowDraft] {
        [
            sample("陈绮贞「漫漫长夜 Cheer20」", 2026, 7, 12, "杭州", "杭州奥体中心体育馆", "陈绮贞"),
            sample("万能青年旅店 · 冀西南林路行", 2026, 5, 18, "北京", "国家奥林匹克体育中心", "万能青年旅店"),
            sample("草东没有派对 · 如常", 2026, 4, 9, "上海", "梅赛德斯-奔驰文化中心", "草东没有派对"),
            sample("落日飞车 · Q Tour", 2026, 2, 21, "上海", "MAO Livehouse", "落日飞车"),
            sample("新裤子 · 北海怪兽", 2025, 11, 15, "南京", "南京奥体中心体育场", "新裤子"),
            sample("落日飞车「夕阳无限好听」", 2025, 9, 6, "杭州", "MAO Livehouse", "落日飞车"),
            sample("陈绮贞 · 房间里的音乐会", 2025, 5, 24, "上海", "梅赛德斯-奔驰文化中心", "陈绮贞"),
            sample("落日飞车 · Soft Storm", 2024, 8, 17, "南京", "南京奥体中心体育场", "落日飞车")
        ]
    }

    private static func sample(
        _ name: String,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ city: String,
        _ venue: String,
        _ artist: String
    ) -> ShowDraft {
        ShowDraft(
            name: name,
            date: date(year, month, day),
            startTime: date(year, month, day, 19, 30),
            endTime: date(year, month, day, 22, 0),
            city: city,
            venueName: venue,
            artist: artist,
            source: .manual
        )
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
#endif
