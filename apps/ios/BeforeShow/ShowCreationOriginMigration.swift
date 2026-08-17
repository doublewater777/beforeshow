import Foundation
import SwiftData

/// 给升级前写入的旧现场补上显式的创建来源（一次性，启动时执行）。
///
/// 为什么需要迁移而不是运行时兜底：升级前 `applyAcceptedSession` 在找不到匹配现场时
/// 会新建一条普通 `Show`，随后用 `applyCompanionSession(..., isOwner: false)` 标成
/// participant 侧。这类「纯导入」行与「用户自己添加、后来被邀请合并」的行，在旧数据里
/// 都只剩 `companionIsOwner == false`，无法再区分。
///
/// 迁移策略：只在这一次、只对没有来源值的旧数据，用 `companionIsOwner == false`
/// 判定为 participant 侧导入并标记 `.companionImport`，其余标记 `.user`。此后来源字段
/// 永远是显式值，合并邀请再改 `companionIsOwner` 也不会影响额度。
///
/// 时序很关键：必须在任何新的邀请接受把已有现场翻成 participant 侧之前跑完，
/// 否则用户自己添加的现场会被迁移误判成导入。
enum ShowCreationOriginMigration {
    static func migrateIfNeeded(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }

        var didChange = false
        for show in shows where show.hasUnresolvedCreationOrigin {
            show.creationOrigin = show.companionIsOwner == false ? .companionImport : .user
            didChange = true
        }

        guard didChange else { return }
        try? modelContext.save()
    }
}
