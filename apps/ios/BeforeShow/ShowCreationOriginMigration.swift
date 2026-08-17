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
/// 时序不能靠启动顺序保证：`noteDependenciesReady()` 会立刻起一个 Task 去
/// flush 待处理邀请，可能先于启动任务里的迁移执行。所以除了启动时调用一次，
/// `applyAcceptedSession` 在合并/新建之前也会先调用 `resolveUnresolvedOrigins`，
/// 把旧数据的来源定格下来 —— 无论谁先跑，用户自己添加的现场都不会被误判成导入。
enum ShowCreationOriginMigration {
    static func migrateIfNeeded(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Show>()
        guard let shows = try? modelContext.fetch(descriptor) else { return }

        guard resolveUnresolvedOrigins(in: shows) else { return }
        try? modelContext.save()
    }

    /// 给还没有来源值的现场落一个显式来源。返回是否有改动。
    ///
    /// 判定依据 `companionIsOwner`：在这条现场第一次被邀请合并之前，它仍然
    /// 忠实反映「这条记录是不是纯 participant 侧导入」。定格之后来源不再变化。
    @discardableResult
    static func resolveUnresolvedOrigins(in shows: [Show]) -> Bool {
        var didChange = false
        for show in shows where show.hasUnresolvedCreationOrigin {
            show.creationOrigin = show.companionIsOwner == false ? .companionImport : .user
            didChange = true
        }
        return didChange
    }
}
