import Foundation

/// 艺名 + 头像 URL 的最小单元。`avatarURL == nil` 表示该 slot 未识别。
/// SwiftData 直接把 `[ArtistSlot]` 存进 `Show.artists`,`ShowDraft` 也用同一形态。
struct ArtistSlot: Codable, Hashable, Equatable {
    var name: String
    var avatarURL: String?
    /// 识别到的 Apple Music 艺人页链接,详情页点阵容头像直接跳转;未识别为 nil。
    var appleMusicURL: String? = nil
    /// 稳定的 Apple Music catalog artist ID；旧数据由轻量 migration 从 URL 回填。
    var appleMusicArtistID: String? = nil
    /// 足迹 #01 卡片背景用的代表专辑封面,由 ArtistAlbumArtworkResolver 解析后写回;未解析为 nil。
    var albumArtworkURL: String? = nil
}
