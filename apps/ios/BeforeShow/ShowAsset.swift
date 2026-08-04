import Foundation
import SwiftData

enum ShowAssetKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case ticket
    case timetable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ticket: return "票根"
        case .timetable: return "时刻表"
        }
    }

    var viewerTitle: String {
        switch self {
        case .ticket: return "我的票根"
        case .timetable: return "时刻表"
        }
    }

    var emptySubtitle: String { "未添加" }
    var savedSubtitle: String { "已保存" }

    var addTitle: String { "添加\(title)" }

    var addDescription: String {
        switch self {
        case .ticket:
            return "选择一张电子票截图或实体票照片，保存到这场现场。只作现场记录，不替代官方票务凭证。"
        case .timetable:
            return "选择一张演出流程、阵容安排或时间图片，保存到这场现场。"
        }
    }

    var choosePrompt: String {
        switch self {
        case .ticket: return "电子票截图或实体票照片"
        case .timetable: return "演出流程、阵容安排或时间图片"
        }
    }

    var iconName: String {
        switch self {
        case .ticket: return "ticket"
        case .timetable: return "list.bullet.rectangle"
        }
    }

    var directoryName: String { rawValue }
}

enum ShowAssetValidationError: Error, Equatable {
    case emptyImage
    case unsupportedImage
}

/// One local image asset bound to a show (ticket stub or timetable).
/// Uniqueness is enforced in save paths: each show keeps at most one asset per kind.
@Model
final class ShowAsset {
    var id: UUID
    var showID: UUID
    var kindRawValue: String
    /// Composite uniqueness key: "showID|kind". Enforced by SwiftData unique attribute.
    @Attribute(.unique)
    var uniqueKey: String
    var relativePath: String
    var createdAt: Date
    var updatedAt: Date

    /// Cascade boundary with `Show`. `showID` remains a denormalized key for file paths
    /// and fetch predicates; the relationship makes show deletion reclaim asset records.
    var show: Show?

    var kind: ShowAssetKind {
        get { ShowAssetKind(rawValue: kindRawValue) ?? .ticket }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        kind: ShowAssetKind,
        relativePath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.kindRawValue = kind.rawValue
        self.uniqueKey = Self.makeUniqueKey(showID: showID, kind: kind)
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func makeUniqueKey(showID: UUID, kind: ShowAssetKind) -> String {
        "\(showID.uuidString)|\(kind.rawValue)"
    }

    func replaceImage(relativePath: String) {
        self.relativePath = relativePath
        updatedAt = Date()
    }
}
