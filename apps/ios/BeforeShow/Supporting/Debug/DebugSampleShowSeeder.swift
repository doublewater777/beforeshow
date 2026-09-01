import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

#if DEBUG
@MainActor
enum DebugSampleShowSeeder {
    static func seedIfRequested(in modelContext: ModelContext) {
        if ProcessInfo.processInfo.arguments.contains("--seed-app-store-screenshots") {
            seedAppStoreScreenshots(in: modelContext)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-current-management-live") {
            seedCurrentManagementLive(in: modelContext)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-opening-memory-window") {
            seedCurrentManagementLive(in: modelContext, startedAgo: 12 * 60)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-upcoming-near") {
            seedUpcomingNear(in: modelContext)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-upcoming-soon") {
            seedUpcomingNear(in: modelContext, offset: 42 * 60 + 17)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-no-cover") {
            seedUpcomingNear(in: modelContext, offset: 42 * 60 + 17, withCover: false)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-upcoming-far") {
            seedUpcomingNear(in: modelContext, offset: 57 * 86_400)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-awaiting-end-confirmation") {
            seedPostEstimatedEnd(in: modelContext, confirmEnd: false)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--seed-confirmed-ended") {
            seedPostEstimatedEnd(in: modelContext, confirmEnd: true)
            return
        }

        guard ProcessInfo.processInfo.arguments.contains("--seed-add-show-samples") else {
            return
        }

        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            var showsByName = Dictionary(uniqueKeysWithValues: existingShows.map { ($0.name, $0) })
            var seededShows: [Show] = []

            for draft in sampleDrafts {
                if let show = showsByName[draft.name] {
                    apply(draft, to: show)
                    seededShows.append(show)
                } else {
                    let show = try draft.makeShow()
                    modelContext.insert(show)
                    showsByName[show.name] = show
                    seededShows.append(show)
                }
            }

            if let firstShow = seededShows.first {
                let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
                if let selection = selections.first {
                    selection.select(showID: firstShow.id)
                } else {
                    modelContext.insert(CurrentShowSelection(selectedShowID: firstShow.id))
                }
            }

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed add-show samples: \(error)")
        }
    }

    /// App Store 截屏演示包：当前「夜航」+ 两场未来现场 + 记忆碎片。
    /// 封面用自有 `default_cover`，避免真实艺人海报版权风险。
    /// Upsert by name — 不要删掉当前现场，否则已打开的 sheet 会绑到被 cascade 清掉的旧对象。
    static func seedAppStoreScreenshots(in modelContext: ModelContext) {
        let coverURL = installDefaultCoverURL() ?? ""
        let primary = appStorePrimaryDraft(coverURL: coverURL)
        let now = Date()
        let secondaryDrafts: [ShowDraft] = [
            ShowDraft(
                name: "潮汐 Livehouse · 杭州站",
                date: now.addingTimeInterval(18 * 86_400),
                startTime: appStoreWallTime(on: now.addingTimeInterval(18 * 86_400)),
                city: "杭州",
                venueName: "酒球会",
                artists: [ArtistSlot(name: "潮汐", avatarURL: nil)],
                coverImageURL: coverURL,
                source: .manual
            ),
            ShowDraft(
                name: "山海音乐节 · 成都",
                date: now.addingTimeInterval(42 * 86_400),
                startTime: appStoreWallTime(on: now.addingTimeInterval(42 * 86_400)),
                city: "成都",
                venueName: "露天音乐公园",
                artists: [ArtistSlot(name: "山海", avatarURL: nil)],
                coverImageURL: coverURL,
                source: .manual
            )
        ]
        // 足迹页需要已结束现场；全部虚构，避免真实艺人海报/名称风险。
        let endedDrafts: [(ShowDraft, TimeInterval, Int?)] = [
            (
                ShowDraft(
                    name: "南风 Live · 厦门站",
                    date: now.addingTimeInterval(-40 * 86_400),
                    startTime: appStoreWallTime(on: now.addingTimeInterval(-40 * 86_400)),
                    city: "厦门",
                    venueName: "岸边音乐空间",
                    artists: [ArtistSlot(name: "南风", avatarURL: nil)],
                    coverImageURL: coverURL,
                    source: .manual
                ),
                2.5 * 3_600,
                5
            ),
            (
                ShowDraft(
                    name: "极光音乐节 · 昆明",
                    date: now.addingTimeInterval(-120 * 86_400),
                    startTime: appStoreWallTime(on: now.addingTimeInterval(-120 * 86_400)),
                    city: "昆明",
                    venueName: "滇池草坪",
                    artists: [
                        ArtistSlot(name: "极光", avatarURL: nil),
                        ArtistSlot(name: "夜航", avatarURL: nil)
                    ],
                    coverImageURL: coverURL,
                    source: .manual
                ),
                5 * 3_600,
                4
            ),
            (
                ShowDraft(
                    name: "回声巡演 · 南京站",
                    date: now.addingTimeInterval(-220 * 86_400),
                    startTime: appStoreWallTime(on: now.addingTimeInterval(-220 * 86_400)),
                    city: "南京",
                    venueName: "奥体中心体育馆",
                    artists: [ArtistSlot(name: "回声", avatarURL: nil)],
                    coverImageURL: coverURL,
                    source: .manual
                ),
                2.5 * 3_600,
                5
            ),
            (
                ShowDraft(
                    name: "潮汐 Livehouse · 上海站",
                    date: now.addingTimeInterval(-300 * 86_400),
                    startTime: appStoreWallTime(on: now.addingTimeInterval(-300 * 86_400)),
                    city: "上海",
                    venueName: "育音堂",
                    artists: [ArtistSlot(name: "潮汐", avatarURL: nil)],
                    coverImageURL: coverURL,
                    source: .manual
                ),
                2 * 3_600,
                3
            )
        ]

        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            let keepNames = Set(
                [primary.name]
                    + secondaryDrafts.map(\.name)
                    + endedDrafts.map(\.0.name)
            )

            let current: Show
            if let existing = existingShows.first(where: { $0.name == primary.name }) {
                try existing.apply(primary)
                existing.markScheduled()
                existing.clearEnded()
                current = existing
            } else {
                current = try primary.makeShow()
                modelContext.insert(current)
            }

            for draft in secondaryDrafts {
                if let existing = existingShows.first(where: { $0.name == draft.name }) {
                    try existing.apply(draft)
                    existing.markScheduled()
                    existing.clearEnded()
                } else {
                    modelContext.insert(try draft.makeShow())
                }
            }

            for (draft, duration, rating) in endedDrafts {
                let show: Show
                if let existing = existingShows.first(where: { $0.name == draft.name }) {
                    try existing.apply(draft)
                    show = existing
                } else {
                    show = try draft.makeShow()
                    modelContext.insert(show)
                }
                let endAt = (draft.startTime ?? draft.date).addingTimeInterval(duration)
                show.markEnded(at: endAt)
                if let rating {
                    try? show.setClosingRitual(rating: rating, note: nil)
                }
            }

            for show in existingShows where !keepNames.contains(show.name) {
                modelContext.delete(show)
            }

            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: current.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: current.id))
            }

            // 截屏包每次刷新记忆，保证带上图片素材（upsert 场景下旧纯文字碎片会被替换）。
            for fragment in current.memoryFragments {
                modelContext.delete(fragment)
            }
            try seedAppStoreMemoryFragments(for: current, now: now, in: modelContext)

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed app store screenshots: \(error)")
        }
    }

    private static func seedAppStoreMemoryFragments(
        for show: Show,
        now: Date,
        in modelContext: ModelContext
    ) throws {
        let before = try MemoryFragment(
            showID: show.id,
            text: "候场的风有点凉，票根捏在手里才觉得真的要开始了。",
            createdAt: now.addingTimeInterval(-3 * 86_400),
            phase: .before
        )
        before.show = show
        try attachDefaultCoverPhoto(to: before, showID: show.id)
        modelContext.insert(before)

        let live = try MemoryFragment(
            showID: show.id,
            text: "灯暗下来的一刻，整个场馆都安静了。",
            createdAt: now.addingTimeInterval(-2 * 86_400),
            phase: .live
        )
        live.show = show
        try attachDefaultCoverPhoto(to: live, showID: show.id)
        modelContext.insert(live)

        let after = try MemoryFragment(
            showID: show.id,
            text: "散场后还不想离开，想把这一晚多留一会儿。",
            createdAt: now.addingTimeInterval(-86_400),
            phase: .after
        )
        after.show = show
        try attachDefaultCoverPhoto(to: after, showID: show.id)
        modelContext.insert(after)
    }

    private static func attachDefaultCoverPhoto(to fragment: MemoryFragment, showID: UUID) throws {
        guard let image = UIImage(named: "default_cover"),
              let data = image.jpegData(compressionQuality: 0.88) else { return }
        let mediaID = UUID()
        let directory = "\(showID.uuidString)/\(fragment.id.uuidString)"
        let relativePath = "\(directory)/\(mediaID.uuidString).jpg"
        let thumbnailPath = "\(directory)/\(mediaID.uuidString)-thumbnail.jpg"
        let location = MemoryMediaLocation.applicationSupport()
        let originalURL = location.url(for: relativePath)
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: originalURL, options: .atomic)
        try data.write(to: location.url(for: thumbnailPath), options: .atomic)
        try fragment.appendMedia(MemoryMediaItem(
            id: mediaID,
            kind: .photo,
            relativePath: relativePath,
            thumbnailRelativePath: thumbnailPath,
            contentTypeIdentifier: UTType.jpeg.identifier,
            videoDuration: nil,
            sortOrder: 0
        ))
    }

    static func appStoreReviewDraft() -> ShowDraft {
        appStorePrimaryDraft(coverURL: installDefaultCoverURL() ?? "")
    }

    private static func appStorePrimaryDraft(coverURL: String) -> ShowDraft {
        let start = appStorePrimaryStartDate()
        return ShowDraft(
            name: "「夜航」巡演 · 上海站",
            date: start,
            startTime: start,
            city: "上海",
            venueName: "回声剧场",
            artists: [ArtistSlot(name: "夜航", avatarURL: nil)],
            coverImageURL: coverURL,
            source: .link,
            recognizedFields: [.name, .date, .startTime, .city, .venueName, .artist]
        )
    }

    private static func appStorePrimaryStartDate() -> Date {
        appStoreWallTime(on: Date().addingTimeInterval(56 * 86_400))
    }

    private static func appStoreWallTime(on day: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return calendar.date(
            from: DateComponents(
                year: parts.year,
                month: parts.month,
                day: parts.day,
                hour: 19,
                minute: 30
            )
        ) ?? day
    }

    private static func installDefaultCoverURL() -> String? {
        guard let image = UIImage(named: "default_cover"),
              let data = image.jpegData(compressionQuality: 0.92) else {
            return nil
        }
        do {
            let directory = try ShowCoverLocalImageStore.directory()
            let url = directory.appendingPathComponent("app-store-yehang-cover.jpg")
            try data.write(to: url, options: .atomic)
            return url.absoluteString
        } catch {
            return nil
        }
    }

    private static func seedUpcomingNear(in modelContext: ModelContext, offset: TimeInterval = 3 * 3_600 + 21 * 60 + 18, withCover: Bool = true) {
        let name = "夏夜音乐会"
        let now = Date()
        let start = now.addingTimeInterval(offset)
        let draft = ShowDraft(
            name: name,
            date: start,
            startTime: start,
            city: "南京",
            venueName: "南京奥体中心体育场",
            artists: [ArtistSlot(name: "夏夜乐队", avatarURL: nil)],
            coverImageURL: withCover ? "https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?auto=format&fit=crop&w=1200&q=85" : "",
            source: .manual
        )
        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            let show: Show
            if let existing = existingShows.first(where: { $0.name == name }) {
                try existing.apply(draft)
                existing.markScheduled()
                existing.clearEnded()
                show = existing
            } else {
                show = try draft.makeShow()
                modelContext.insert(show)
            }
            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: show.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: show.id))
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed upcoming-near sample: \(error)")
        }
    }

    /// 越过估算散场边界(start+默认 4h)的现场:confirmEnd=false → 首页「待确认」;
    /// confirmEnd=true → 用户已确认散场,进入停留期。
    private static func seedPostEstimatedEnd(in modelContext: ModelContext, confirmEnd: Bool) {
        let name = "夏夜音乐会"
        let now = Date()
        let start = now.addingTimeInterval(-5 * 3_600)
        let draft = ShowDraft(
            name: name,
            date: start,
            startTime: start,
            city: "台北",
            venueName: "台北流行音乐中心",
            artists: [ArtistSlot(name: "夏夜乐队", avatarURL: nil)],
            coverImageURL: "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=900&q=85",
            source: .manual
        )
        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            let show: Show
            if let existing = existingShows.first(where: { $0.name == name }) {
                try existing.apply(draft)
                existing.markScheduled()
                existing.clearEnded()
                show = existing
            } else {
                show = try draft.makeShow()
                modelContext.insert(show)
            }
            if confirmEnd {
                show.markEnded(at: start.addingTimeInterval(2 * 3_600 + 17 * 60))
            }
            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: show.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: show.id))
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed post-estimated-end sample: \(error)")
        }
    }

    private static func seedCurrentManagementLive(in modelContext: ModelContext, startedAgo: TimeInterval = 84 * 60) {
        let name = "夏夜音乐会"
        let now = Date()
        let start = now.addingTimeInterval(-startedAgo)
        let draft = ShowDraft(
            name: name,
            date: start,
            startTime: start,
            city: "台北",
            venueName: "台北流行音乐中心",
            venueAddress: "台北市信义区松寿路 20 号",
            artists: [ArtistSlot(name: "夏夜乐队", avatarURL: nil)],
            coverImageURL: "https://images.unsplash.com/photo-1501386761578-eac5c94b800a?auto=format&fit=crop&w=900&q=85",
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

            let verificationDrafts = [
                ShowDraft(name: "海风音乐祭", date: now.addingTimeInterval(5 * 86_400), startTime: now.addingTimeInterval(5 * 86_400), city: "新北", venueName: "Zepp New Taipei", artists: [ArtistSlot(name: "海岸线", avatarURL: nil)], source: .manual),
                ShowDraft(name: "城市声浪", date: now.addingTimeInterval(18 * 86_400), startTime: now.addingTimeInterval(18 * 86_400), city: "台中", venueName: "台中 Legacy", artists: [ArtistSlot(name: "午夜电台", avatarURL: nil)], source: .manual),
                ShowDraft(name: "南方夏夜", date: now.addingTimeInterval(42 * 86_400), startTime: now.addingTimeInterval(42 * 86_400), city: "高雄", venueName: "LIVE WAREHOUSE", artists: [ArtistSlot(name: "落日之后", avatarURL: nil)], source: .manual)
            ]
            for draft in verificationDrafts {
                if let existing = existingShows.first(where: { $0.name == draft.name }) {
                    try existing.apply(draft)
                    existing.markScheduled()
                    existing.clearEnded()
                } else {
                    modelContext.insert(try draft.makeShow())
                }
            }

            let endedDraft = ShowDraft(name: "冬日回声", date: now.addingTimeInterval(-10 * 86_400), startTime: now.addingTimeInterval(-10 * 86_400), city: "台北", venueName: "The Wall", artists: [ArtistSlot(name: "微光乐团", avatarURL: nil)], source: .manual)
            if let existing = existingShows.first(where: { $0.name == endedDraft.name }) {
                try existing.apply(endedDraft)
                existing.markEnded(at: now.addingTimeInterval(-10 * 86_400 + 7_200))
            } else {
                let ended = try endedDraft.makeShow()
                ended.markEnded(at: now.addingTimeInterval(-10 * 86_400 + 7_200))
                modelContext.insert(ended)
            }

            let canceledDraft = ShowDraft(name: "雨季来信", date: now.addingTimeInterval(28 * 86_400), startTime: now.addingTimeInterval(28 * 86_400), city: "台南", venueName: "漂丿白鹭", artists: [ArtistSlot(name: "海岸信号", avatarURL: nil)], source: .manual)
            if let existing = existingShows.first(where: { $0.name == canceledDraft.name }) {
                try existing.apply(canceledDraft)
                existing.markCanceled()
            } else {
                let canceled = try canceledDraft.makeShow()
                canceled.markCanceled()
                modelContext.insert(canceled)
            }

            let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
            if let selection = selections.first {
                selection.select(showID: show.id)
            } else {
                modelContext.insert(CurrentShowSelection(selectedShowID: show.id))
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-memory-fragments"),
               show.memoryFragments.isEmpty {
                let samples: [(String, MemoryFragmentPhase, TimeInterval)] = [
                    ("终于到了，外面已经排了很长的队。", .before, -62 * 60),
                    ("灯暗下来的一刻，整个场馆都安静了。", .live, -24 * 60),
                    ("散场后还不想离开，想把这一刻多留一会儿。", .after, 18 * 60)
                ]
                for sample in samples {
                    let fragment = try MemoryFragment(
                        showID: show.id,
                        text: sample.0,
                        createdAt: now.addingTimeInterval(sample.2),
                        phase: sample.1
                    )
                    fragment.show = show
                    modelContext.insert(fragment)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--seed-memory-media"),
               !show.memoryFragments.contains(where: { !$0.mediaItems.isEmpty }) {
                let fragmentID = UUID()
                let relativeDirectory = "\(show.id.uuidString)/\(fragmentID.uuidString)"
                let relativePath = "\(relativeDirectory)/sample.jpg"
                let destination = MemoryMediaLocation.applicationSupport().url(for: relativePath)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { context in
                    UIColor(red: 0.18, green: 0.25, blue: 0.48, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
                }
                guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                try data.write(to: destination, options: .atomic)
                let fragment = try MemoryFragment(
                    id: fragmentID,
                    showID: show.id,
                    text: BSLocalization.text("灯亮以后随手留下的一段画面。"),
                    createdAt: now.addingTimeInterval(-8 * 60),
                    phase: .live
                )
                fragment.show = show
                try fragment.appendMedia(MemoryMediaItem(
                    id: UUID(),
                    kind: .photo,
                    relativePath: relativePath,
                    thumbnailRelativePath: nil,
                    contentTypeIdentifier: UTType.jpeg.identifier,
                    videoDuration: nil,
                    sortOrder: 0
                ))
                modelContext.insert(fragment)
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed current management live state: \(error)")
        }
    }

    private static var sampleDrafts: [ShowDraft] {
        [
            ShowDraft(
                name: "周杰伦嘉年华世界巡回演唱会 · 南京站",
                date: date(2026, 9, 24),
                startTime: time(2026, 9, 24, 19, 30),
                city: "南京",
                venueName: "南京奥体中心体育场",
                artists: [ArtistSlot(name: "周杰伦", avatarURL: nil)],
                coverImageURL: "https://img.alicdn.com/bao/uploaded/https://img.alicdn.com/imgextra/i2/2251059038/O1CN01nWPQm82GdSnG5tWAW_!!2251059038.jpg_q60.jpg_.webp",
                source: .link
            ),
            ShowDraft(
                name: "绿洲音乐节2.0·湖州吴兴站",
                date: date(2026, 6, 27),
                startTime: time(2026, 6, 27, 14, 0),
                city: "湖州",
                venueName: "吴乐湾音乐广场",
                artists: ["刘雨昕", "姚琛", "二手玫瑰", "DOUDOU", "椿乐队", "裁缝铺", "麻园诗人", "梅卡德尔", "石岩", "声音碎片", "声音玩具"]
                    .map { ArtistSlot(name: $0, avatarURL: nil) },
                source: .link
            )
        ]
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func time(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func apply(_ draft: ShowDraft, to show: Show) {
        try? show.apply(draft)
        show.markScheduled()
    }
}
#endif
