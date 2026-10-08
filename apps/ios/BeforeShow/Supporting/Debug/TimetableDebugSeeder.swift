import Foundation
import SwiftData
import SwiftUI

#if DEBUG
@MainActor
enum TimetableDebugSeeder {
    static func seedIfRequested(in modelContext: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("--seed-timetable-live") else {
            return
        }

        // `--seed-demo-names` swaps in a made-up festival and lineup for marketing captures.
        let demo = ProcessInfo.processInfo.arguments.contains("--seed-demo-names")
        func n(_ real: String, _ fake: String) -> String { demo ? fake : real }
        let name = n("草莓音乐节 2026 · 上海站", "夏末音浪 2026 · 上海站")
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        // Anchored 6h back so seeding just after midnight still lands on the same festival day.
        let today = calendar.startOfDay(for: now.addingTimeInterval(-6 * 3600))

        // Day 1 (Today). `--seed-timetable-phase=between|upcoming|dayEnded` shifts
        // the sets so the home card can be captured in each live-mode state.
        let phase = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--seed-timetable-phase=") }?
            .split(separator: "=").last.map(String.init) ?? "live"
        // `--seed-timetable-days=N` (default 2) and `--seed-timetable-gap=N` (rest days
        // after day 1) cover longer festivals and festivals that skip days.
        func intArgument(_ name: String) -> Int? {
            ProcessInfo.processInfo.arguments.first { $0.hasPrefix(name + "=") }
                .flatMap { $0.split(separator: "=").last.flatMap { Int($0) } }
        }
        let dayCount = max(2, intArgument("--seed-timetable-days") ?? 2)
        let gap = max(0, intArgument("--seed-timetable-gap") ?? 0)
        let span = dayCount + gap
        let offsets: [(Double, Double)]
        switch phase {
        case "between": offsets = [(-90, -30), (-60, -10), (20, 80), (20, 80), (100, 160)]
        case "upcoming": offsets = [(120, 180), (135, 185), (200, 260), (210, 270), (280, 340)]
        case "dayEnded": offsets = [(-300, -240), (-280, -230), (-200, -140), (-190, -130), (-120, -60)]
        case "final": offsets = [(-300, -240), (-280, -230), (-200, -140), (-190, -130), (-120, -60)].map { ($0.0 - Double(span) * 1440, $0.1 - Double(span) * 1440) }
        default: offsets = [(-30, 45), (-15, 35), (50, 110), (60, 120), (140, 200)]
        }
        func set(_ name: String, _ index: Int, interested: Bool) -> TimetablePerformance {
            let p = try! TimetablePerformance(
                artistName: name,
                startsAt: now.addingTimeInterval(offsets[index].0 * 60),
                endsAt: now.addingTimeInterval(offsets[index].1 * 60)
            )
            p.isInterested = interested
            return p
        }
        let p1 = set(n("落日飞车 Sunset Rollercoaster", "落日漫游 Sunset Drift"), 0, interested: false)
        let p2 = set(n("King Gizzard & The Lizard Wizard", "Neon Tides"), 1, interested: true)
        let p3 = set(n("万能青年旅店 Omnipotent Youth Society", "白昼信号 Daylight Signal"), 2, interested: true)
        let p4 = set(n("NewJeans", "MOONA"), 3, interested: true)
        let p5 = set(n("草东没有派对 No Party For Cao Dong", "海风合唱团"), 4, interested: false)

        let stage1 = try! TimetableStage(name: n("草莓舞台", "主舞台"), sortOrder: 0, performances: [p1, p3, p5])
        let stage2 = try! TimetableStage(name: n("爱舞台", "星光舞台"), sortOrder: 1, performances: [p2, p4])
        // `final` moves both days into the past so the whole festival has ended.
        let day1Date = calendar.date(byAdding: .day, value: phase == "final" ? -span : 0, to: today)!
        let day1 = try! TimetableDay(date: day1Date, stages: [stage1, stage2])

        // Day 2 (Tomorrow)
        let tomorrow = calendar.date(byAdding: .day, value: 1 + gap, to: day1Date)!
        func d2(_ artist: String, _ start: (Int, Int), _ end: (Int, Int), interested: Bool = false) -> TimetablePerformance {
            let p = try! TimetablePerformance(
                artistName: artist,
                startsAt: calendar.date(bySettingHour: start.0, minute: start.1, second: 0, of: tomorrow)!,
                endsAt: calendar.date(bySettingHour: end.0, minute: end.1, second: 0, of: tomorrow)!
            )
            p.isInterested = interested
            return p
        }
        let d2stage = try! TimetableStage(name: n("草莓舞台", "主舞台"), sortOrder: 0, performances: [
            d2(n("Massive Attack", "Paper Lanterns"), (18, 30), (19, 45), interested: true),
            d2(n("新裤子 New Pants", "旧城新事"), (20, 15), (21, 15), interested: true),
            d2(n("Phoenix", "夜航船 Night Ferry"), (21, 45), (23, 0), interested: true)
        ])
        let d2stage2 = try! TimetableStage(name: n("爱舞台", "星光舞台"), sortOrder: 1, performances: [
            d2(n("Hyukoh", "Echo Bloom"), (19, 0), (20, 0), interested: true),
            d2(n("椅子乐团 The Chairs", "回声计划"), (20, 30), (21, 30), interested: true)
        ])
        let day2 = try! TimetableDay(date: tomorrow, stages: [d2stage, d2stage2])

        let pool = ["Paper Lanterns", "Echo Bloom", "旧城新事", "回声计划", "海风合唱团", "Neon Tides"]
        let laterDays: [TimetableDay] = (3...max(3, dayCount)).compactMap { number in
            guard number <= dayCount else { return nil }
            let date = calendar.date(byAdding: .day, value: number - 1 + gap, to: day1Date)!
            func later(_ index: Int, _ hour: Int, interested: Bool = false) -> TimetablePerformance {
                let p = try! TimetablePerformance(
                    artistName: pool[(number + index) % pool.count],
                    startsAt: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!,
                    endsAt: calendar.date(bySettingHour: hour + 1, minute: 0, second: 0, of: date)!
                )
                p.isInterested = interested
                return p
            }
            return try! TimetableDay(date: date, stages: [
                TimetableStage(name: n("草莓舞台", "主舞台"), sortOrder: 0, performances: [later(0, 18, interested: true), later(1, 20)]),
                TimetableStage(name: n("爱舞台", "星光舞台"), sortOrder: 1, performances: [later(2, 19), later(3, 21, interested: true)])
            ])
        }
        let timetable = try! Timetable(timeZoneIdentifier: "Asia/Shanghai", days: [day1, day2] + laterDays)

        let draft = ShowDraft(
            name: name,
            date: today,
            startTime: now.addingTimeInterval(-30 * 60),
            city: "上海",
            venueName: n("世博公园", "滨江草坪"),
            artists: [
                ArtistSlot(name: n("落日飞车", "落日漫游"), avatarURL: nil),
                ArtistSlot(name: n("万能青年旅店", "白昼信号"), avatarURL: nil)
            ],
            coverImageURL: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=900&q=85",
            source: .manual
        )

        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            let show: Show
            if let existing = existingShows.first(where: { $0.name == name }) {
                try existing.apply(draft)
                existing.clearEnded()
                show = existing
            } else {
                show = try draft.makeShow()
                modelContext.insert(show)
            }
            show.timetable = timetable
            timetable.show = show

            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: show.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: show.id))
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed timetable live sample: \(error)")
        }
    }
}
#endif
