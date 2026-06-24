import Foundation
import SwiftData

enum ShowVideoCategory: String, CaseIterable, Codable, Equatable {
    case starter
    case preShow
    case highEnergy
    case deepDive

    var title: String {
        switch self {
        case .starter: "入门先看"
        case .preShow: "演前必看"
        case .highEnergy: "名场面 / 高能现场"
        case .deepDive: "深入补课"
        }
    }
}

enum ShowVideoValidationError: Error, Equatable {
    case emptyTitle
    case nonBilibiliURL
}

@Model
final class ShowVideo {
    var id: UUID
    var showID: UUID
    var title: String
    var sourceName: String
    var bilibiliURLString: String
    var durationText: String
    var reason: String
    var thumbnailURL: String?
    var sortOrder: Int
    var createdAt: Date

    private var categoryRawValue: String

    var category: ShowVideoCategory {
        get { ShowVideoCategory(rawValue: categoryRawValue) ?? .starter }
        set { categoryRawValue = newValue.rawValue }
    }

    var bilibiliURL: URL {
        URL(string: bilibiliURLString)!
    }

    var usesPlaceholderThumbnail: Bool {
        (thumbnailURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        category: ShowVideoCategory,
        title: String,
        sourceName: String,
        bilibiliURL: URL,
        durationText: String,
        reason: String,
        thumbnailURL: String? = nil,
        sortOrder: Int,
        createdAt: Date = Date()
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ShowVideoValidationError.emptyTitle
        }
        guard bilibiliURL.host()?.localizedCaseInsensitiveContains("bilibili.com") == true else {
            throw ShowVideoValidationError.nonBilibiliURL
        }

        self.id = id
        self.showID = showID
        self.categoryRawValue = category.rawValue
        self.title = trimmedTitle
        self.sourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bilibiliURLString = bilibiliURL.absoluteString
        self.durationText = durationText
        self.reason = reason
        self.thumbnailURL = thumbnailURL
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

struct ShowVideoSection: Equatable {
    let category: ShowVideoCategory
    let videos: [ShowVideo]
}

struct ShowVideoLibraryService {
    func sections(for showID: UUID, videos: [ShowVideo]) -> [ShowVideoSection] {
        ShowVideoCategory.allCases.map { category in
            let categoryVideos = videos
                .filter { $0.showID == showID && $0.category == category }
                .sorted { first, second in
                    if first.sortOrder == second.sortOrder {
                        return first.createdAt < second.createdAt
                    }
                    return first.sortOrder < second.sortOrder
                }

            return ShowVideoSection(category: category, videos: categoryVideos)
        }
    }
}

struct ShowVideoCardPresentation: Equatable {
    let title: String
    let sourceText: String
    let reason: String
    let durationText: String
    let usesPlaceholderThumbnail: Bool

    init(video: ShowVideo) {
        title = video.title
        sourceText = "B站 · \(video.sourceName)"
        reason = video.reason
        durationText = video.durationText
        usesPlaceholderThumbnail = video.usesPlaceholderThumbnail
    }

    var visibleTexts: [String] {
        [
            title,
            sourceText,
            reason,
            durationText
        ]
    }
}

struct ShowVideoWebViewNavigator {
    private(set) var presentedVideo: ShowVideo?

    var presentedURL: URL? {
        presentedVideo?.bilibiliURL
    }

    var navigationTitle: String? {
        presentedVideo?.title
    }

    mutating func open(_ video: ShowVideo) {
        presentedVideo = video
    }

    mutating func close() {
        presentedVideo = nil
    }
}

enum ShowVideoFixture {
    static func show() -> Show {
        try! Show(
            id: UUID(uuidString: "B0C56C08-3C52-4E67-8E1D-4F6F55A6C100")!,
            name: "上海演唱会",
            date: Date(timeIntervalSince1970: 1_790_928_000),
            startTime: Date(timeIntervalSince1970: 1_790_989_200),
            city: "上海",
            venueName: "上海体育场",
            artist: "五月天",
            type: .concert
        )
    }

    static func videos(for showID: UUID) -> [ShowVideo] {
        [
            makeVideo(showID: showID, category: .starter, order: 0, title: "第一次看五月天现场，从这场完整 Live 开始", sourceName: "五月天官方现场", duration: "12:46", reason: "旋律、互动和大合唱都很完整，适合先建立对现场气质的第一印象。"),
            makeVideo(showID: showID, category: .starter, order: 1, title: "最容易入坑的代表性现场片段", sourceName: "B站音乐现场", duration: "08:21", reason: "几首代表作连在一起，能快速感受到乐队和观众之间的连接。", thumbnailURL: ""),
            makeVideo(showID: showID, category: .starter, order: 2, title: "往届体育场现场氛围速看", sourceName: "演唱会记录", duration: "06:18", reason: "灯光、万人合唱和舞台规模都很直观，适合第一次了解。"),

            makeVideo(showID: showID, category: .preShow, order: 0, title: "本轮巡演常见开场段落", sourceName: "巡演饭拍合集", duration: "09:32", reason: "如果马上要去这场，建议先看这一版现场进入状态。"),
            makeVideo(showID: showID, category: .preShow, order: 1, title: "近期 Live 必唱曲现场版", sourceName: "B站演出现场", duration: "05:44", reason: "覆盖近期歌单里的高频曲目，演前预习效率很高。"),
            makeVideo(showID: showID, category: .preShow, order: 2, title: "演前适合补的一组副歌大合唱", sourceName: "现场剪辑", duration: "07:09", reason: "提前熟悉副歌和互动点，现场会更容易跟上。"),

            makeVideo(showID: showID, category: .highEnergy, order: 0, title: "万人合唱爆发瞬间合集", sourceName: "高能现场", duration: "04:57", reason: "这段适合提前感受现场的爆发力和全场一起唱的情绪。"),
            makeVideo(showID: showID, category: .highEnergy, order: 1, title: "安可段落：全场灯海和返场互动", sourceName: "演唱会饭拍", duration: "06:35", reason: "能看到现场最有记忆点的返场氛围。"),
            makeVideo(showID: showID, category: .highEnergy, order: 2, title: "经典互动片段：主唱带全场唱", sourceName: "B站现场片段", duration: "03:48", reason: "短，但情绪密度很高，适合出发前快速热身。"),

            makeVideo(showID: showID, category: .deepDive, order: 0, title: "早期经典现场：听懂乐队一路来的变化", sourceName: "老现场档案", duration: "10:24", reason: "想更理解五月天为什么是五月天，可以补这场。"),
            makeVideo(showID: showID, category: .deepDive, order: 1, title: "不同时期巡演舞台编排对比", sourceName: "巡演考古", duration: "11:08", reason: "能看出编曲、舞台和表达方式的阶段变化。"),
            makeVideo(showID: showID, category: .deepDive, order: 2, title: "纪念场特别编制 Live", sourceName: "现场补课", duration: "13:19", reason: "适合已经感兴趣、想多了解一点的人继续往深处看。")
        ]
    }

    private static func makeVideo(
        showID: UUID,
        category: ShowVideoCategory,
        order: Int,
        title: String,
        sourceName: String,
        duration: String,
        reason: String,
        thumbnailURL: String? = nil
    ) -> ShowVideo {
        try! ShowVideo(
            showID: showID,
            category: category,
            title: title,
            sourceName: sourceName,
            bilibiliURL: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD?p=\(order + 1)")!,
            durationText: duration,
            reason: reason,
            thumbnailURL: thumbnailURL,
            sortOrder: order,
            createdAt: Date(timeIntervalSince1970: TimeInterval(order))
        )
    }
}
