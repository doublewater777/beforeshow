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

        let name = "草莓音乐节 2026 · 上海站"
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.startOfDay(for: now)

        // Day 1 (Today)
        let p1 = try! TimetablePerformance(
            artistName: "落日飞车 Sunset Rollercoaster",
            startsAt: now.addingTimeInterval(-30 * 60),
            endsAt: now.addingTimeInterval(45 * 60)
        )
        p1.isInterested = false

        let p2 = try! TimetablePerformance(
            artistName: "King Gizzard & The Lizard Wizard",
            startsAt: now.addingTimeInterval(-15 * 60),
            endsAt: now.addingTimeInterval(35 * 60)
        )
        p2.isInterested = true // Interested parallel set!

        let p3 = try! TimetablePerformance(
            artistName: "万能青年旅店 Omnipotent Youth Society",
            startsAt: now.addingTimeInterval(50 * 60),
            endsAt: now.addingTimeInterval(110 * 60)
        )
        p3.isInterested = true // Starting soon!

        let p4 = try! TimetablePerformance(
            artistName: "NewJeans",
            startsAt: now.addingTimeInterval(60 * 60),
            endsAt: now.addingTimeInterval(120 * 60)
        )
        p4.isInterested = true // Clashes with p3!

        let p5 = try! TimetablePerformance(
            artistName: "草东没有派对 No Party For Cao Dong",
            startsAt: now.addingTimeInterval(140 * 60),
            endsAt: now.addingTimeInterval(200 * 60)
        )
        p5.isInterested = false

        let stage1 = try! TimetableStage(name: "草莓舞台", sortOrder: 0, performances: [p1, p3, p5])
        let stage2 = try! TimetableStage(name: "爱舞台", sortOrder: 1, performances: [p2, p4])
        let day1 = try! TimetableDay(date: today, stages: [stage1, stage2])

        // Day 2 (Tomorrow)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let d2p1 = try! TimetablePerformance(
            artistName: "Massive Attack",
            startsAt: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrow)!,
            endsAt: calendar.date(bySettingHour: 16, minute: 30, second: 0, of: tomorrow)!
        )
        let d2stage = try! TimetableStage(name: "草莓舞台", performances: [d2p1])
        let day2 = try! TimetableDay(date: tomorrow, stages: [d2stage])

        let timetable = try! Timetable(timeZoneIdentifier: "Asia/Shanghai", days: [day1, day2])

        let draft = ShowDraft(
            name: name,
            date: today,
            startTime: now.addingTimeInterval(-30 * 60),
            city: "上海",
            venueName: "世博公园",
            artists: [
                ArtistSlot(name: "落日飞车", avatarURL: nil),
                ArtistSlot(name: "万能青年旅店", avatarURL: nil)
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
