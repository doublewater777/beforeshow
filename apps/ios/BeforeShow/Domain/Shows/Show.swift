import Foundation
import SwiftData

enum ShowValidationError: Error, Equatable {
    case emptyName
    case missingStartTime
    case invalidEndTime
    case ratingOutOfRange
    case closingNoteTooLong
}

enum ShowCompanionStatus: String, CaseIterable, Codable {
    case none
    case pending
    case confirmed
    case canceled
}

/// 这场现场为什么会存在于本机：免费额度只算用户自己添加的场次。
///
/// 必须是不可变的来源标记，不能从 `companionIsOwner` 之类的关系状态推导：
/// 接受同行邀请时会把邀请合并进用户已有的现场（按 cloud record / showID /
/// 名称+日期+场馆 匹配），那条路径同样会把 `companionIsOwner` 置为 false，
/// 于是用户自己添加、已经占用额度的现场会被「退还」额度。
enum ShowCreationOrigin: String, Codable {
    /// 用户在本机添加（手动 / 链接 / 截图）。
    case user
    /// 仅因为接受同行邀请而新建的 participant 侧现场。
    case companionImport
}

enum ShowCompanionMutationError: Error, Equatable {
    case invalidTransition(from: ShowCompanionStatus, to: ShowCompanionStatus)
}

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

@Model
final class Show {
    var id: UUID
    var name: String
    var date: Date
    var startTime: Date
    var endDate: Date?
    var endTime: Date?
    var timeZoneSecondsFromGMT: Int?
    var endTimeZoneSecondsFromGMT: Int?
    var timeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var city: String?
    var venueName: String?
    var venueAddress: String?
    var coverImageURL: String?
    /// 多个艺名按用户填入顺序存放,空 / 纯空白会被 `init` / `apply` 过滤掉。
    /// 每行带自己的头像 URL(`nil` 表示未识别),省去并行数组的对齐逻辑。
    var artists: [ArtistSlot] = []
    var createdAt: Date
    var updatedAt: Date
    var postponedDate: Date?
    /// 用户确认的真实散场时刻。存在时高于录入的结束时间与默认时长估算。
    var endedAt: Date?
    /// 明确历史现场直接收进足迹时的生命周期事实。与 `endedAt` 分开，
    /// 因为这类录入没有用户提供的真实散场时刻，不能伪造一个结束时间。
    /// Optional keeps the property lightweight-migration safe for existing rows.
    var wasAddedAsHistorical: Bool?
    /// 「散场仪式」五档情绪评分，nil = 未评分或主动跳过。
    var rating: Int? = nil
    /// 散场后留下的私人感受，nil = 未填写或主动跳过。trim 后的纯空白视为未填。
    var closingNote: String? = nil

    private var companionStatusRawValue: String?
    private(set) var companionNames: [String] = []

    var companionName: String? {
        CompanionNameList.joined(companionNames)
    }
    /// CloudKit `CompanionSession` record name; local cache of the shared session.
    var companionCloudRecordName: String?
    /// CloudKit zone for the companion session (custom private zone required for sharing).
    var companionCloudZoneName: String?
    /// CloudKit zone owner for the companion session (current user token or share owner).
    var companionCloudOwnerName: String?
    /// CloudKit `CKShare` record name for re-presenting the system share UI.
    var companionShareRecordName: String?
    /// CloudKit zone for the share record.
    var companionShareZoneName: String?
    /// CloudKit zone owner for the share record.
    var companionShareOwnerName: String?
    /// `true` when this device created the share (owner); `false` when accepted as participant.
    var companionIsOwner: Bool?

    /// 现场的创建来源。`nil` = 本次升级前写入的旧数据，尚未标记来源。
    ///
    /// 旧数据不能靠运行时兜底猜测：升级前 `applyAcceptedSession` 在没有匹配现场时
    /// 会新建一条普通 Show 再标成 participant 侧，这类行没有来源值；但用户自己添加、
    /// 后来才被邀请合并的现场同样没有来源值。二者只靠 `companionIsOwner` 区分不开，
    /// 所以由 `ShowCreationOriginMigration` 在启动时一次性落库（见其说明），
    /// 之后这个字段始终是显式值。
    private var creationOriginRawValue: String?

    /// 尚未迁移的旧数据按 `.user` 读取：额度宁可算得保守，也不凭空退还。
    var creationOrigin: ShowCreationOrigin {
        get { creationOriginRawValue.flatMap(ShowCreationOrigin.init(rawValue:)) ?? .user }
        set { creationOriginRawValue = newValue.rawValue }
    }

    /// 是否还没有显式的创建来源（迁移用）。
    var hasUnresolvedCreationOrigin: Bool {
        creationOriginRawValue == nil
    }

    /// 免费现场容量只算用户自己添加且仍保留的现场。仅因接受同行邀请而新建的
    /// participant 侧现场不占容量；把邀请合并进用户已有现场时来源不变。
    var countsTowardFreeShowCapacity: Bool {
        creationOrigin == .user
    }

    /// Fragments bound to this show. Deleting a `Show` cascades to its fragments
    /// (and their media items) so no orphan fragment records can survive a show
    /// deletion. Disk files are reclaimed by memory-media reconciliation.
    @Relationship(deleteRule: .cascade, inverse: \MemoryFragment.show)
    var memoryFragments: [MemoryFragment] = []

    /// Ticket stub / timetable images bound to this show. Deleting a `Show` cascades
    /// to its assets; disk files are reclaimed by asset-media reconciliation.
    @Relationship(deleteRule: .cascade, inverse: \ShowAsset.show)
    var assets: [ShowAsset] = []

    /// Optional local video used as the dynamic side of this show's cover.
    /// Deleting a `Show` cascades to this record; disk files are reclaimed by
    /// dynamic-cover reconciliation.
    @Relationship(deleteRule: .cascade, inverse: \DynamicCover.show)
    var dynamicCover: DynamicCover?

    private var changeStatusRawValue: String

    var companionStatus: ShowCompanionStatus {
        companionStatusRawValue.flatMap(ShowCompanionStatus.init(rawValue:)) ?? .none
    }

    var changeStatus: ShowChangeStatus {
        get { ShowChangeStatus(rawValue: changeStatusRawValue) ?? .scheduled }
        set {
            changeStatusRawValue = newValue.rawValue
            touch()
        }
    }

    /// 已识别艺人头像(任意 slot 非空)对应的 URL,列表行 / 详情页用。
    /// 多艺人时取第一个;form 头像按 slot 自己的字段渲染。
    var firstRecognizedArtistAvatarURL: String? {
        artists.compactMap { $0.avatarURL?.isEmpty == false ? $0.avatarURL : nil }.first
    }

    /// 仅艺人姓名的便捷视图,首页阵容条 / 搜索索引用。
    var artistNames: [String] { artists.map(\.name) }

    var effectiveDate: Date {
        postponedDate ?? date
    }

    func timingCalendar(fallback: Calendar = .current) -> Calendar {
        Self.timingCalendar(
            timeZoneIdentifier: timeZoneIdentifier,
            timeZoneSecondsFromGMT: timeZoneSecondsFromGMT,
            fallback: fallback
        )
    }

    func endTimingCalendar(fallback: Calendar = .current) -> Calendar {
        Self.timingCalendar(
            timeZoneIdentifier: endTimeZoneIdentifier ?? timeZoneIdentifier,
            timeZoneSecondsFromGMT: endTimeZoneSecondsFromGMT ?? timeZoneSecondsFromGMT,
            fallback: fallback
        )
    }

    init(
        id: UUID = UUID(),
        name: String,
        date: Date,
        startTime: Date,
        endDate: Date? = nil,
        endTime: Date? = nil,
        timeZoneSecondsFromGMT: Int? = nil,
        endTimeZoneSecondsFromGMT: Int? = nil,
        timeZoneIdentifier: String? = nil,
        endTimeZoneIdentifier: String? = nil,
        city: String? = nil,
        venueName: String? = nil,
        venueAddress: String? = nil,
        artists: [ArtistSlot] = [],
        coverImageURL: String? = nil,
        changeStatus: ShowChangeStatus = .scheduled,
        endedAt: Date? = nil,
        wasAddedAsHistorical: Bool = false,
        companionStatus: ShowCompanionStatus = .none,
        companionName: String? = nil,
        companionNames: [String] = [],
        companionCloudRecordName: String? = nil,
        companionCloudZoneName: String? = nil,
        companionCloudOwnerName: String? = nil,
        companionShareRecordName: String? = nil,
        companionShareZoneName: String? = nil,
        companionShareOwnerName: String? = nil,
        companionIsOwner: Bool? = nil,
        /// `nil` 只用来重建「升级前写入、尚未标记来源」的旧数据（迁移测试）；
        /// 正常创建路径都会显式带上来源。
        creationOrigin: ShowCreationOrigin? = .user,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ShowValidationError.emptyName
        }
        guard Self.hasValidEndTime(
            date: date,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime,
            calendar: Self.timingCalendar(
                timeZoneIdentifier: timeZoneIdentifier,
                timeZoneSecondsFromGMT: timeZoneSecondsFromGMT
            ),
            endCalendar: Self.timingCalendar(
                timeZoneIdentifier: endTimeZoneIdentifier ?? timeZoneIdentifier,
                timeZoneSecondsFromGMT: endTimeZoneSecondsFromGMT ?? timeZoneSecondsFromGMT
            )
        ) else {
            throw ShowValidationError.invalidEndTime
        }

        self.id = id
        self.name = trimmedName
        self.date = date
        self.startTime = startTime
        self.endDate = endDate
        self.endTime = endTime
        self.timeZoneSecondsFromGMT = timeZoneSecondsFromGMT
        self.endTimeZoneSecondsFromGMT = endTimeZoneSecondsFromGMT
        self.timeZoneIdentifier = timeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
        self.city = city
        self.venueName = venueName
        self.venueAddress = venueAddress
        self.artists = Self.normalizedArtistSlots(artists)
        self.coverImageURL = coverImageURL
        self.changeStatusRawValue = changeStatus.rawValue
        self.endedAt = endedAt
        self.wasAddedAsHistorical = wasAddedAsHistorical
        self.companionStatusRawValue = companionStatus.rawValue
        self.companionNames = CompanionNameList.normalized(
            companionNames.isEmpty ? [companionName].compactMap { $0 } : companionNames
        )
        self.companionCloudRecordName = companionCloudRecordName
        self.companionCloudZoneName = companionCloudZoneName
        self.companionCloudOwnerName = companionCloudOwnerName
        self.companionShareRecordName = companionShareRecordName
        self.companionShareZoneName = companionShareZoneName
        self.companionShareOwnerName = companionShareOwnerName
        self.companionIsOwner = companionIsOwner
        self.creationOriginRawValue = creationOrigin?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func markPostponed(newDate: Date?) {
        postponedDate = newDate
        changeStatus = .postponed
        endedAt = nil
        touch()
    }

    func markCanceled() {
        changeStatus = .canceled
        endedAt = nil
        touch()
    }

    func markScheduled() {
        postponedDate = nil
        changeStatus = .scheduled
        discardConfirmedEndBeforeEffectiveStart()
        touch()
    }

    func markEnded(at date: Date = Date()) {
        endedAt = date
        wasAddedAsHistorical = false
        touch()
    }

    func markAddedAsHistorical() {
        wasAddedAsHistorical = true
        touch()
    }

    func clearEnded() {
        endedAt = nil
        wasAddedAsHistorical = false
        touch()
    }

    /// 写「散场仪式」评分与散场文字。`endedAt` 与生命期状态不受影响 ——
    /// 仪式步骤与结束现场完全解耦,任一字段抛错都不会回滚已结束的现场。
    ///
    /// - rating: 1...5,`nil` = 清除或保持未评分
    /// - note: 经 `normalizeClosingNote` trim + 长度校验,空字符串视为 `nil`
    /// - 同值写入为幂等,不会更新 `updatedAt`
    func setClosingRitual(rating: Int?, note: String?) throws {
        if let rating, !(1...5).contains(rating) {
            throw ShowValidationError.ratingOutOfRange
        }
        let normalized = try Self.normalizeClosingNote(note)
        if self.rating == rating, self.closingNote == normalized { return }
        self.rating = rating
        self.closingNote = normalized
        touch()
    }

    static func normalizeClosingNote(_ text: String?) throws -> String? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized.count <= 500 else {
            throw ShowValidationError.closingNoteTooLong
        }
        return normalized
    }

    /// Valid transitions: `.none` / `.canceled` → `.pending`.
    func markCompanionInvitationSent(name: String?) throws {
        let from = companionStatus
        guard from == .none || from == .canceled else {
            throw ShowCompanionMutationError.invalidTransition(from: from, to: .pending)
        }
        applyCompanionState(status: .pending, name: name)
    }

    /// Valid transition: `.pending` → `.confirmed`.
    func markCompanionConfirmed(name: String?) throws {
        let from = companionStatus
        guard from == .pending else {
            throw ShowCompanionMutationError.invalidTransition(from: from, to: .confirmed)
        }
        applyCompanionState(status: .confirmed, name: name)
    }

    /// Valid transitions: `.pending` / `.confirmed` → `.canceled`.
    func cancelCompanion() throws {
        let from = companionStatus
        guard from == .pending || from == .confirmed else {
            throw ShowCompanionMutationError.invalidTransition(from: from, to: .canceled)
        }
        companionNames = []
        companionStatusRawValue = ShowCompanionStatus.canceled.rawValue
        touch()
    }

    /// Snapshot used to restore state when the user cancels the system share sheet.
    func companionStateSnapshot() -> (status: ShowCompanionStatus, names: [String]) {
        (companionStatus, companionNames)
    }

    /// Force-restore a previous companion snapshot after a failed CloudKit invite.
    func restoreCompanionState(status: ShowCompanionStatus, names: [String]) {
        applyCompanionState(status: status, names: names)
    }

    func restoreCompanionState(status: ShowCompanionStatus, name: String?) {
        applyCompanionState(status: status, name: name)
    }

    func applyCompanionState(status: ShowCompanionStatus, name: String?) {
        applyCompanionState(
            status: status,
            names: CompanionNameList.normalized([name].compactMap { $0 })
        )
    }

    func applyCompanionState(status: ShowCompanionStatus, names: [String]) {
        companionNames = CompanionNameList.normalized(names)
        companionStatusRawValue = status.rawValue
        touch()
    }

    /// Single draft → 现场 mutation seam (create uses `ShowDraft.makeShow`, edit uses this).
    ///
    /// Deletion test: removing this method re-scatters trim/validate/field mapping across
    /// home edit, detail edit, and debug seeder. Does not touch
    /// `changeStatus` / `postponedDate` — those stay on mark* paths.
    func apply(_ draft: ShowDraft) throws {
        let prepared = try Self.prepared(from: draft)
        // 按 index 比对,只清发生变化的 slot 的识别产物:换名后该 slot 让 form 重新识别,
        // 未变 slot 的头像保留,新增 slot 的 avatar 仍由 draft 携带。
        let oldSlots = self.artists
        var newSlots = prepared.artists
        let common = min(oldSlots.count, newSlots.count)
        for index in 0..<common where oldSlots[index].name != newSlots[index].name {
            newSlots[index].avatarURL = nil
            newSlots[index].appleMusicURL = nil
            newSlots[index].appleMusicArtistID = nil
            newSlots[index].albumArtworkURL = nil
        }
        name = prepared.name
        date = prepared.date
        startTime = prepared.startTime
        endDate = prepared.endDate
        endTime = prepared.endTime
        timeZoneSecondsFromGMT = prepared.timeZoneSecondsFromGMT
        endTimeZoneSecondsFromGMT = prepared.endTimeZoneSecondsFromGMT
        timeZoneIdentifier = prepared.timeZoneIdentifier
        endTimeZoneIdentifier = prepared.endTimeZoneIdentifier
        city = prepared.city
        venueName = prepared.venueName
        venueAddress = prepared.venueAddress
        artists = newSlots
        coverImageURL = prepared.coverImageURL
        discardConfirmedEndBeforeEffectiveStart()
        touch()
    }

    /// A confirmed curtain time must never precede the show's effective start.
    /// Status changes that mean the show did not happen clear it explicitly;
    /// edits preserve a still-valid confirmation and discard only stale values.
    private func discardConfirmedEndBeforeEffectiveStart(calendar: Calendar = .current) {
        guard let endedAt else { return }
        let minimumConfirmableEnd = CurrentShowTimeState.minimumConfirmableEnd(for: self, calendar: calendar)
        if endedAt < minimumConfirmableEnd {
            self.endedAt = nil
        }
    }

    /// Normalize + validate draft fields once for create and edit.
    static func prepared(from draft: ShowDraft) throws -> PreparedShowDraft {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ShowValidationError.emptyName
        }
        guard let startTime = draft.startTime else {
            throw ShowValidationError.missingStartTime
        }
        guard hasValidEndTime(
            date: draft.date,
            startTime: startTime,
            endDate: draft.endDate,
            endTime: draft.endTime,
            calendar: draft.timingCalendar(),
            endCalendar: draft.endTimingCalendar()
        ) else {
            throw ShowValidationError.invalidEndTime
        }

        return PreparedShowDraft(
            name: trimmedName,
            date: draft.date,
            startTime: startTime,
            endDate: draft.endDate,
            endTime: draft.endTime,
            timeZoneSecondsFromGMT: draft.timeZoneSecondsFromGMT,
            endTimeZoneSecondsFromGMT: draft.endTimeZoneSecondsFromGMT,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            endTimeZoneIdentifier: draft.endTimeZoneIdentifier,
            city: trimmedOptional(draft.city),
            venueName: trimmedOptional(draft.venueName),
            venueAddress: trimmedOptional(draft.venueAddress),
            artists: Self.normalizedArtistSlots(draft.artists),
            coverImageURL: trimmedOptional(draft.coverImageURL)
        )
    }

    private func touch() {
        updatedAt = Date()
    }

    /// 入口处统一 trim+filter:丢掉空名,头像若是纯空白视为未识别(`nil`)。
    static func normalizedArtistSlots(_ slots: [ArtistSlot]) -> [ArtistSlot] {
        slots.compactMap { slot in
            let name = slot.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let trimmedURL = slot.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let avatar = (trimmedURL?.isEmpty ?? true) ? nil : trimmedURL
            return ArtistSlot(
                name: name,
                avatarURL: avatar,
                appleMusicURL: slot.appleMusicURL,
                appleMusicArtistID: slot.appleMusicArtistID,
                albumArtworkURL: slot.albumArtworkURL
            )
        }
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func timingCalendar(
        timeZoneIdentifier: String? = nil,
        timeZoneSecondsFromGMT: Int?,
        fallback: Calendar = .current
    ) -> Calendar {
        if let timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            var calendar = fallback
            calendar.timeZone = timeZone
            return calendar
        }
        guard let timeZoneSecondsFromGMT,
              let timeZone = TimeZone(secondsFromGMT: timeZoneSecondsFromGMT) else {
            return fallback
        }
        var calendar = fallback
        calendar.timeZone = timeZone
        return calendar
    }

    static func hasValidEndTime(
        date: Date,
        startTime: Date,
        endDate: Date?,
        endTime: Date?,
        calendar: Calendar = .current,
        endCalendar: Calendar? = nil
    ) -> Bool {
        let endCalendar = endCalendar ?? calendar
        if let endDate,
           calendar.startOfDay(for: endDate) < calendar.startOfDay(for: date) {
            return false
        }

        guard let endTime else {
            return true
        }

        let startDay = calendar.startOfDay(for: date)
        let endDay = endCalendar.startOfDay(for: endDate ?? date)
        let endComponents = endCalendar.dateComponents([.hour, .minute, .second], from: endTime)
        guard let effectiveEnd = endCalendar.date(
            bySettingHour: endComponents.hour ?? 0,
            minute: endComponents.minute ?? 0,
            second: endComponents.second ?? 0,
            of: endDay
        ) else {
            return false
        }

        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startTime)
        guard let effectiveStart = calendar.date(
            bySettingHour: startComponents.hour ?? 0,
            minute: startComponents.minute ?? 0,
            second: startComponents.second ?? 0,
            of: startDay
        ) else {
            return false
        }

        if endDate == nil,
           effectiveEnd <= effectiveStart {
            return true
        }

        return effectiveEnd > effectiveStart
    }
}

/// Normalized draft fields ready to write onto a `Show` (create or edit).
struct PreparedShowDraft: Equatable {
    let name: String
    let date: Date
    let startTime: Date
    let endDate: Date?
    let endTime: Date?
    let timeZoneSecondsFromGMT: Int?
    let endTimeZoneSecondsFromGMT: Int?
    let timeZoneIdentifier: String?
    let endTimeZoneIdentifier: String?
    let city: String?
    let venueName: String?
    let venueAddress: String?
    let artists: [ArtistSlot]
    let coverImageURL: String?
}
