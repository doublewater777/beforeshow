import Foundation
import SwiftData

/// 给升级前写入的旧现场补上显式的创建来源（一次性，启动时执行）。
///
/// 为什么需要迁移而不是运行时兜底：升级前 `applyAcceptedSession` 在找不到匹配现场时
/// 会新建一条普通 `Show`，随后用 `applyCompanionSession(..., isOwner: false)` 标成
/// participant 侧。这类「纯导入」行与「用户自己添加、后来被邀请合并」的行，在旧数据里
/// 都只剩 `companionIsOwner == false`，无法再区分。
///
/// 旧数据无法区分，所以策略是保守的：一律标 `.user`（详见
/// `resolveUnresolvedOrigins`）。此后来源字段永远是显式值，合并邀请再改
/// `companionIsOwner` 也不会影响额度。
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
    /// 旧数据一律标 `.user`（保守策略）。`companionIsOwner == false` 在升级前就已经
    /// 是二义的：升级前的三条合并分支同样会把用户自己添加的现场标成 participant 侧，
    /// 所以「历史纯导入」和「历史自建后被合并」到达升级点时长得一模一样，没有其它
    /// 持久证据可以区分。
    ///
    /// 两种误判的代价不对称：把历史导入误算成占额度，最多让用户本月少添加一场；
    /// 把用户自己添加的现场误算成导入，会凭空退还已经用掉的额度，等于免费绕过限制。
    /// 所以宁可保守。升级后新建的现场都带显式来源，不受这条策略影响。
    @discardableResult
    static func resolveUnresolvedOrigins(in shows: [Show]) -> Bool {
        var didChange = false
        for show in shows where show.hasUnresolvedCreationOrigin {
            show.creationOrigin = .user
            didChange = true
        }
        return didChange
    }
}
