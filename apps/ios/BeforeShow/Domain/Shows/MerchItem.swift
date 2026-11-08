import Foundation
import SwiftData

enum MerchKind: String, Codable, CaseIterable, Identifiable {
    case tee
    case wristband
    case pin
    case lightStick
    case tote
    case poster
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tee: return BSLocalization.text("T 恤")
        case .wristband: return BSLocalization.text("手环")
        case .pin: return BSLocalization.text("徽章")
        case .lightStick: return BSLocalization.text("荧光棒")
        case .tote: return BSLocalization.text("帆布袋")
        case .poster: return BSLocalization.text("海报")
        case .other: return BSLocalization.text("其他")
        }
    }
}

/// 一件带回来的周边：一张照片（可选抠图）挂在某场现场上。
/// 照片和 `ShowAsset` 共用 `ShowAssetMediaStore` 根目录，路径为 `<showID>/merch/<file>`。
@Model
final class MerchItem {
    static let directoryName = "merch"

    private(set) var id: UUID = UUID()
    private(set) var showID: UUID = UUID()
    private var kindRawValue: String = MerchKind.other.rawValue
    var name: String = ""
    var relativePath: String = ""
    /// Vision 前景抠图（PNG）；抠图失败时为 nil，展示原图。
    var cutoutRelativePath: String?
    var createdAt: Date = Date()

    var show: Show?

    var kind: MerchKind {
        get { MerchKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.title : trimmed
    }

    var storedRelativePaths: [String] {
        [relativePath] + (cutoutRelativePath.map { [$0] } ?? [])
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        kind: MerchKind = .other,
        name: String = "",
        relativePath: String,
        cutoutRelativePath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.kindRawValue = kind.rawValue
        self.name = name
        self.relativePath = relativePath
        self.cutoutRelativePath = cutoutRelativePath
        self.createdAt = createdAt
    }

    func edit(kind: MerchKind, name: String) {
        self.kind = kind
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidRelativePath(_ relativePath: String, showID: UUID) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return components.count == 3
            && components[0] == showID.uuidString
            && components[1] == directoryName
            && !components[2].isEmpty
            && !components.contains(where: { $0 == "." || $0 == ".." })
    }
}
