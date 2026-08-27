#if DEBUG
import SwiftData
import Foundation
import UIKit

@MainActor
enum FootprintDebugSeeder {
    static func seedIfRequested(in modelContext: ModelContext) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--seed-footprints-samples")
                || arguments.contains("--seed-footprint-detail-v41")
                || arguments.contains("--seed-dispersal-live")
                || arguments.contains("--seed-companion-group") else { return }

        do {
            let existing = try modelContext.fetch(FetchDescriptor<Show>())
            let existingNames = Set(existing.map(\.name))
           if arguments.contains("--seed-footprints-samples") {
               var firstSeeded: Show?
               for sample in samples where !existingNames.contains(sample.name) {
                   let s = try sample.makeShow()
                   modelContext.insert(s)
                   if firstSeeded == nil { firstSeeded = s }
               }
               if firstSeeded == nil, let target = existing.first {
                   firstSeeded = target
               }
               if let firstSeeded {
                   try addMemorySamples(to: firstSeeded, in: modelContext)
               }
               try refreshDebugArtistArtwork(in: modelContext)
           }
            if arguments.contains("--seed-footprint-detail-v41"),
               !existingNames.contains(detailSampleName) {
                try seedDetailSamples(in: modelContext)
            }
            if arguments.contains("--seed-companion-group") {
                try seedCompanionGroup(in: modelContext, existingNames: existingNames)
            }
            if arguments.contains("--seed-dispersal-live") {
                let liveName = "草东没有派对 · 散场仪式 DEMO"
                if !existingNames.contains(liveName) {
                    let draft = sample(
                        liveName, 2026, 8, 15,
                        "上海", "梅赛德斯-奔驰文化中心",
                        [ArtistSlot(name: "草东没有派对", avatarURL: nil)]
                    )
                    let live = try draft.makeShow()
                    // 截图验证用：直接把评价写进 show，仪式 sheet 打开时
                    // 评分步默认选中、文字步字段预填，可以只验证后续流程。
                    if arguments.contains("--seed-dispersal-ritual") {
                        try live.setClosingRitual(
                            rating: 5,
                            note: "最后一首歌结束的时候，灯亮得特别慢，舍不得走。"
                        )
                    }
                    modelContext.insert(live)
                }
            }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed footprint samples: \(error)")
        }
    }

    private static let detailSampleName = "落日飞车 · 夏夜回忆现场"

    // 与 AppleMusicArtistSearchService 现有 iTunes Search 结果同源的演示头像。
    // 仅用于 DEBUG 足迹样例，避免影响真实用户数据。
    private static let debugArtistAvatarURL = "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/3c/a2/21/3ca22123-14d6-57f4-9e52-aa4573a05b07/mzm.clkcarof.jpg/240x240bb.jpg"
    private static let debugArtistAppleMusicURL = "https://music.apple.com/cn/artist/%E9%99%88%E7%BB%AE%E8%B4%9E/462564117?uo=4"

    private static func refreshDebugArtistArtwork(in modelContext: ModelContext) throws {
        let sampleNames = Set(samples.map(\.name))
        let shows = try modelContext.fetch(FetchDescriptor<Show>())
        for show in shows where sampleNames.contains(show.name) {
            show.artists = show.artists.map { slot in
                guard slot.name == "陈绮贞" else { return slot }
                var updated = slot
                updated.avatarURL = debugArtistAvatarURL
                updated.appleMusicURL = debugArtistAppleMusicURL
                return updated
            }
        }
    }

    private static func seedDetailSamples(in modelContext: ModelContext) throws {
        let earlier = try sample(
            "落日飞车 · 第一次同行",
            2025, 9, 6,
            "杭州", "MAO Livehouse", [ArtistSlot(name: "落日飞车")]
        ).makeShow()
        earlier.markEnded(at: date(2025, 9, 6, 22, 10))
        try earlier.markCompanionInvitationSent(name: "林嘉")
        try earlier.markCompanionConfirmed(name: earlier.companionName)

        let full = try sample(
            detailSampleName,
            2026, 7, 12,
            "杭州", "杭州奥体中心体育馆", [ArtistSlot(name: "落日飞车")]
        ).makeShow()
        full.markEnded(at: date(2026, 7, 12, 22, 20))
        full.applyCompanionState(status: .pending, names: ["林嘉", "王宁"])
        full.applyCompanionState(status: .confirmed, names: ["林嘉", "王宁"])
        try full.setClosingRitual(
            rating: 5,
            note: "最后一首歌结束的时候，灯亮得特别慢。"
        )

        let empty = try sample(
            "安静的一夜 · 空记忆样本",
            2026, 6, 20,
            "台北", "Legacy Taipei", [ArtistSlot(name: "陈绮贞")]
        ).makeShow()
        empty.markEnded(at: date(2026, 6, 20, 22, 0))

        modelContext.insert(earlier)
        modelContext.insert(full)
        modelContext.insert(empty)
        try addMemorySamples(to: full, in: modelContext)
        try addAssetSample(to: full, kind: .ticket, title: "SUMMER TOUR\nTICKET", in: modelContext)
        try addAssetSample(to: full, kind: .timetable, title: "19:30 DOORS\n20:00 LIVE", in: modelContext)
    }

    private static let companionGroupSampleName = "陈绮贞 · 同行群组 DEMO"

    private static func seedCompanionGroup(
        in modelContext: ModelContext,
        existingNames: Set<String>
    ) throws {
        guard !existingNames.contains(companionGroupSampleName) else { return }
        let show = try sample(
            companionGroupSampleName,
            2026, 9, 20,
            "杭州", "杭州奥体中心体育馆",
            [ArtistSlot(name: "陈绮贞")]
        ).makeShow()
        show.applyCompanionState(status: .pending, names: ["林嘉", "王宁"])
        show.applyCompanionState(status: .confirmed, names: ["林嘉", "王宁"])
        show.companionIsOwner = true
        modelContext.insert(show)
    }

    private static func addMemorySamples(to show: Show, in modelContext: ModelContext) throws {
        let photoFragment = try MemoryFragment(
            showID: show.id,
            text: "灯亮起来时，整片人群像海浪一样向前。",
            createdAt: date(2026, 7, 12, 20, 18),
            updatedAt: date(2026, 7, 12, 20, 18),
            phase: .live
        )
        photoFragment.show = show
        try appendSampleMedia(
            to: photoFragment,
            showID: show.id,
            kind: .photo,
            title: "GOLDEN HOUR",
            accent: UIColor(red: 0.88, green: 0.55, blue: 0.28, alpha: 1),
            createdAt: date(2026, 7, 12, 20, 18)
        )
        try appendSampleMedia(
            to: photoFragment,
            showID: show.id,
            kind: .photo,
            title: "ENCORE",
            accent: UIColor(red: 0.33, green: 0.47, blue: 0.78, alpha: 1),
            createdAt: date(2026, 7, 12, 21, 42)
        )
        modelContext.insert(photoFragment)

        let textFragment = try MemoryFragment(
            showID: show.id,
            text: "最后一首歌结束以后，大家都没有马上离开。",
            createdAt: date(2026, 7, 12, 21, 56),
            updatedAt: date(2026, 7, 12, 21, 56),
            phase: .after
        )
        textFragment.show = show
        modelContext.insert(textFragment)

        let videoFragment = try MemoryFragment(
            showID: show.id,
            text: "返场的那一分钟。",
            createdAt: date(2026, 7, 12, 22, 4),
            updatedAt: date(2026, 7, 12, 22, 4),
            phase: .after
        )
        videoFragment.show = show
        try appendSampleMedia(
            to: videoFragment,
            showID: show.id,
            kind: .video,
            title: "00:24\nENCORE",
            accent: UIColor(red: 0.38, green: 0.28, blue: 0.55, alpha: 1),
            createdAt: date(2026, 7, 12, 22, 4),
            duration: 24
        )
        modelContext.insert(videoFragment)
    }

    private static func appendSampleMedia(
        to fragment: MemoryFragment,
        showID: UUID,
        kind: MemoryMediaKind,
        title: String,
        accent: UIColor,
        createdAt: Date,
        duration: TimeInterval? = nil
    ) throws {
        let mediaID = UUID()
        let directory = "\(showID.uuidString)/\(fragment.id.uuidString)"
        let thumbnailPath = "\(directory)/\(mediaID.uuidString)-thumbnail.jpg"
        let originalPath = kind == .video
            ? "\(directory)/\(mediaID.uuidString).mp4"
            : "\(directory)/\(mediaID.uuidString).jpg"
        let location = MemoryMediaLocation.applicationSupport()
        let thumbnailURL = location.url(for: thumbnailPath)
        try FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = sampleImageData(title: title, accent: accent)
        try data.write(to: thumbnailURL, options: .atomic)
        if kind == .video {
            try Data().write(to: location.url(for: originalPath), options: .atomic)
        } else {
            try data.write(to: location.url(for: originalPath), options: .atomic)
        }
        try fragment.appendMedia(MemoryMediaItem(
            id: mediaID,
            kind: kind,
            relativePath: originalPath,
            thumbnailRelativePath: thumbnailPath,
            contentTypeIdentifier: kind == .video ? "public.mpeg-4" : "public.jpeg",
            videoDuration: duration,
            sortOrder: fragment.mediaItems.count,
            createdAt: createdAt
        ))
    }

    private static func addAssetSample(
        to show: Show,
        kind: ShowAssetKind,
        title: String,
        in modelContext: ModelContext
    ) throws {
        let assetID = UUID()
        let relativePath = "\(show.id.uuidString)/\(kind.directoryName)/\(assetID.uuidString)-sample.jpg"
        let location = try ShowAssetMediaLocation.applicationSupport()
        let url = location.rootDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let accent = kind == .ticket
            ? UIColor(red: 0.76, green: 0.43, blue: 0.30, alpha: 1)
            : UIColor(red: 0.24, green: 0.43, blue: 0.65, alpha: 1)
        try sampleImageData(title: title, accent: accent).write(to: url, options: .atomic)
        let asset = ShowAsset(
            id: assetID,
            showID: show.id,
            kind: kind,
            relativePath: relativePath,
            createdAt: date(2026, 7, 12, 18, kind == .ticket ? 30 : 35),
            updatedAt: date(2026, 7, 12, 18, kind == .ticket ? 30 : 35)
        )
        asset.show = show
        modelContext.insert(asset)
    }

    private static func sampleImageData(title: String, accent: UIColor) -> Data {
        let size = CGSize(width: 900, height: 1125)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            accent.withAlphaComponent(0.78).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 420))
            accent.withAlphaComponent(0.32).setFill()
            context.fill(CGRect(x: 0, y: 760, width: size.width, height: 365))

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 68, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style
            ]
            NSString(string: title).draw(
                in: CGRect(x: 70, y: 470, width: 760, height: 220),
                withAttributes: attributes
            )
            NSString(string: "BEFORESHOW · 2026.07.12").draw(
                in: CGRect(x: 70, y: 1010, width: 760, height: 40),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 25, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.64),
                    .paragraphStyle: style
                ]
            )
        }
        return image.jpegData(compressionQuality: 0.88) ?? Data()
    }

    private static var samples: [ShowDraft] {
        [
            sample("陈绮贞「漫漫长夜 Cheer20」", 2026, 7, 12, "杭州", "杭州奥体中心体育馆", [ArtistSlot(name: "陈绮贞", avatarURL: debugArtistAvatarURL, appleMusicURL: debugArtistAppleMusicURL)]),
            sample("万能青年旅店 · 冀西南林路行", 2026, 5, 18, "北京", "国家奥林匹克体育中心", [ArtistSlot(name: "万能青年旅店", avatarURL: nil)], coverImageURL: debugArtistAvatarURL),
            sample("草东没有派对 · 如常", 2026, 4, 9, "上海", "梅赛德斯-奔驰文化中心", [ArtistSlot(name: "草东没有派对", avatarURL: nil)]),
            sample("落日飞车 · Q Tour", 2026, 2, 21, "上海", "MAO Livehouse", [ArtistSlot(name: "落日飞车", avatarURL: nil)]),
            sample("新裤子 · 北海怪兽", 2025, 11, 15, "南京", "南京奥体中心体育场", [ArtistSlot(name: "新裤子", avatarURL: nil)]),
            sample("落日飞车「夕阳无限好听」", 2025, 9, 6, "杭州", "MAO Livehouse", [ArtistSlot(name: "落日飞车", avatarURL: nil)]),
            sample("陈绮贞 · 房间里的音乐会", 2025, 5, 24, "上海", "梅赛德斯-奔驰文化中心", [ArtistSlot(name: "陈绮贞", avatarURL: debugArtistAvatarURL, appleMusicURL: debugArtistAppleMusicURL)]),
            sample("落日飞车 · Soft Storm", 2024, 8, 17, "南京", "南京奥体中心体育场", [ArtistSlot(name: "落日飞车", avatarURL: nil)])
        ]
    }

    private static func sample(
        _ name: String,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ city: String,
        _ venue: String,
        _ artist: [ArtistSlot],
        coverImageURL: String = ""
    ) -> ShowDraft {
        ShowDraft(
            name: name,
            date: date(year, month, day),
            startTime: date(year, month, day, 19, 30),
            endTime: date(year, month, day, 22, 0),
            city: city,
            venueName: venue,
            artists: artist,
            coverImageURL: coverImageURL,
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
