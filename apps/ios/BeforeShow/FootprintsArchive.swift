import SwiftData
import SwiftUI
import UIKit
import Photos

enum FootprintCategory: String, CaseIterable, Identifiable {
    case overview = "总览"
    case artist = "艺人"
    case city = "城市"
    case venue = "场馆"

    var id: String { rawValue }

    /// 展示用本地化标题(rawValue 是稳定标识,不直接上屏)。
    var title: String { BSLocalization.text(rawValue) }
}

struct FootprintRankItem: Identifiable, Equatable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

struct FootprintYearGroup: Identifiable {
    let year: Int
    let shows: [Show]
    var id: Int { year }
}

struct FootprintArchiveSnapshot {
    let shows: [Show]
    let artists: [FootprintRankItem]
    let cities: [FootprintRankItem]
    let venues: [FootprintRankItem]
    let years: [FootprintYearGroup]
    let currentYearCount: Int
    /// 全部归档现场的观看时长合计(分钟),动态计算不持久化。
    let totalDurationMinutes: Int

    var firstShow: Show? { shows.last }

    func ranking(for category: FootprintCategory) -> [FootprintRankItem] {
        switch category {
        case .overview: return []
        case .artist: return artists
        case .city: return cities
        case .venue: return venues
        }
    }
}

enum FootprintEmptyStateCopy {
    struct Content: Equatable {
        let title: String
        let message: String
        let actionTitle: String?
    }

    static func content(hasCurrentShow: Bool) -> Content {
        if hasCurrentShow {
            return Content(
                title: BSLocalization.text("这场结束后，会来到足迹"),
                message: BSLocalization.text("当前现场散场后会自动收进这里，\n场次、城市和回忆都会慢慢累积。"),
                actionTitle: nil
            )
        }

        return Content(
            title: BSLocalization.text("这里会长出你的足迹"),
            message: BSLocalization.text("补进第一场看过的现场，\n场次、城市和回忆都会慢慢累积。"),
            actionTitle: BSLocalization.text("添加第一场现场")
        )
    }
}

struct FootprintDetailDestination: Identifiable, Hashable {
    let show: Show

    var id: UUID { show.id }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum FootprintArchiveShareCopy {
    static func title(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("分享完整档案")
        case .artist: return BSLocalization.text("分享艺人档案")
        case .city: return BSLocalization.text("分享城市档案")
        case .venue: return BSLocalization.text("分享场馆档案")
        }
    }

    static func subtitle(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("总场次、艺人、城市和场馆偏好会汇总在同一张卡片。")
        case .artist: return BSLocalization.text("突出最常看的艺人，并展示艺人排行前三名。")
        case .city: return BSLocalization.text("突出你去过最多的城市，并展示城市排行前三名。")
        case .venue: return BSLocalization.text("突出最熟悉的场馆，并展示场馆排行前三名。")
        }
    }

    static func chip(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("总览")
        case .artist: return BSLocalization.text("艺人")
        case .city: return BSLocalization.text("城市")
        case .venue: return BSLocalization.text("场馆")
        }
    }

    static func kicker(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return "MY LIVE ARCHIVE"
        case .artist: return "ARTIST ARCHIVE"
        case .city: return "CITY ARCHIVE"
        case .venue: return "VENUE ARCHIVE"
        }
    }

    static func filename(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("我的完整现场档案")
        case .artist: return BSLocalization.text("我的艺人现场档案")
        case .city: return BSLocalization.text("我的城市现场档案")
        case .venue: return BSLocalization.text("我的场馆现场档案")
        }
    }

    static func subject(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("我的 BeforeShow 现场总览")
        case .artist: return BSLocalization.text("我的 BeforeShow 艺人档案")
        case .city: return BSLocalization.text("我的 BeforeShow 城市足迹")
        case .venue: return BSLocalization.text("我的 BeforeShow 场馆足迹")
        }
    }

    static func text(for category: FootprintCategory, archive: FootprintArchiveSnapshot) -> String {
        switch category {
        case .overview:
            var lines = [
                subject(for: category),
                BSLocalization.format("%lld 场现场 · %lld 位艺人 · %lld 座城市 · %lld 个场馆", archive.shows.count, archive.artists.count, archive.cities.count, archive.venues.count),
                BSLocalization.format("在现场待过 %@", ShowDurationFormatter.aggregate(totalMinutes: archive.totalDurationMinutes))
            ]
            if let top = archive.artists.first { lines.append(BSLocalization.format("最常看：%@ · %lld 场", top.name, top.count)) }
            if let first = archive.firstShow {
                lines.append(BSLocalization.format("第一场：%@ · %@", footprintMonthText(first.effectiveDate, calendar: first.timingCalendar()), first.name))
            }
            return lines.joined(separator: "\n")
        case .artist:
            return [
                subject(for: category),
                BSLocalization.format("一共看过 %lld 位艺人", archive.artists.count),
                leadingLine(BSLocalization.text("最常看"), from: archive.artists),
                rankingLine(BSLocalization.text("艺人排行"), items: archive.artists)
            ].joined(separator: "\n")
        case .city:
            return [
                subject(for: category),
                BSLocalization.format("现场足迹走过 %lld 座城市", archive.cities.count),
                leadingLine(BSLocalization.text("最常去"), from: archive.cities),
                rankingLine(BSLocalization.text("城市排行"), items: archive.cities)
            ].joined(separator: "\n")
        case .venue:
            return [
                subject(for: category),
                BSLocalization.format("一共到过 %lld 个场馆", archive.venues.count),
                leadingLine(BSLocalization.text("最熟悉"), from: archive.venues),
                rankingLine(BSLocalization.text("场馆排行"), items: archive.venues)
            ].joined(separator: "\n")
        }
    }

    private static func leadingLine(_ label: String, from items: [FootprintRankItem]) -> String {
        guard let first = items.first else { return BSLocalization.format("%@：还没有记录", label) }
        return BSLocalization.format("%@：%@ · %lld 场", label, first.name, first.count)
    }

    private static func rankingLine(_ label: String, items: [FootprintRankItem]) -> String {
        let ranking = items.prefix(3).map { BSLocalization.format("%@ %lld 场", $0.name, $0.count) }.joined(separator: "、")
        return BSLocalization.format("%@：%@", label, ranking.isEmpty ? BSLocalization.text("还没有记录") : ranking)
    }
}

enum FootprintPhotoSaveError: LocalizedError {
    case rendererFailed
    case authorizationDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .rendererFailed:
            return BSLocalization.text("足迹图片生成失败，请重试。")
        case .authorizationDenied:
            return BSLocalization.text("没有照片添加权限，请在系统设置中允许 BeforeShow 添加照片。")
        case .saveFailed:
            return BSLocalization.text("照片保存失败，请重试。")
        }
    }
}

enum FootprintPhotoLibrary {
    static func save(_ image: UIImage) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw FootprintPhotoSaveError.authorizationDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FootprintPhotoSaveError.saveFailed)
                }
            }
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

@MainActor
enum FootprintArchiveBuilder {
    static func make(
        shows: [Show],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FootprintArchiveSnapshot {
        let archived = shows
            .filter {
                guard $0.changeStatus != .canceled else { return false }
                let kind = CurrentShowTimeState(show: $0, calendar: calendar, now: now).kind
                return kind == .postShow || kind == .ended
            }
            .sorted { $0.effectiveDate > $1.effectiveDate }
        let grouped = Dictionary(grouping: archived) {
            $0.timingCalendar(fallback: calendar).component(.year, from: $0.effectiveDate)
        }
        let totalDurationMinutes = archived.reduce(0) { partial, show in
            let timeState = CurrentShowTimeState(show: show, calendar: calendar, now: now)
            guard let minutes = ShowDurationFormatter.minutes(for: show, timeState: timeState) else { return partial }
            return partial + minutes
        }

        return FootprintArchiveSnapshot(
            shows: archived,
            artists: rank(archived.flatMap { $0.artistNames }),
            cities: rank(archived.compactMap { normalized($0.city) }),
            venues: FootprintArchiveRankingBuilder.venues(in: archived).map(\.rankItem),
            years: grouped.keys.sorted(by: >).map {
                FootprintYearGroup(year: $0, shows: grouped[$0] ?? [])
            },
            currentYearCount: grouped[calendar.component(.year, from: now)]?.count ?? 0,
            totalDurationMinutes: totalDurationMinutes
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rank(_ values: [String]) -> [FootprintRankItem] {
        Dictionary(grouping: values, by: { $0 })
            .map { FootprintRankItem(name: $0.key, count: $0.value.count) }
            .sorted {
                $0.count == $1.count
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.count > $1.count
            }
    }
}

struct FootprintsView: View {
    var onArchiveVisibilityChange: (Bool) -> Void = { _ in }
    /// 外部 push 入口：仪式结束（散场卡生成/跳过 share）后由 RootView 写入，
    /// FootprintsView 在 onChange 时把它转成本地 `detailTarget` 触发 push。
    /// 双向但只读外部更安全 —— 内部源仍是本视图状态。
    var pendingDetailTarget: FootprintDetailDestination?
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var fragments: [MemoryFragment]
    @Query private var assets: [ShowAsset]
    @State private var isAddingShow = false
    @State private var detailTarget: FootprintDetailDestination?
    @State private var activeSheet: FootprintSheet?
    @State private var lastScreenshotPromptAt: Date?
    @State private var rankCategory: FootprintCategory = .artist
    @State private var toast: BSToastPayload?
    private let currentShowSession = CurrentShowSession()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: Date(), by: 60)) { context in
                timelineContent(
                    FootprintArchiveBuilder.make(shows: shows, now: context.date),
                    hasCurrentShow: currentShowSession.selectCurrentShow(
                        from: shows,
                        manualSelection: selections.first,
                        now: context.date
                    ) != nil
                )
            }
        }
        .onChange(of: pendingDetailTarget) { _, newValue in
            if let newValue, shows.contains(where: { $0.id == newValue.id }) {
                detailTarget = newValue
            }
        }
    }

    private func timelineContent(
        _ archive: FootprintArchiveSnapshot,
        hasCurrentShow: Bool
    ) -> some View {
        ZStack {
            FootprintBackground()
            if archive.shows.isEmpty {
                FootprintEmptyView(
                    content: FootprintEmptyStateCopy.content(hasCurrentShow: hasCurrentShow),
                    onAdd: { isAddingShow = true }
                )
            } else {
                content(archive)
            }
        }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailTarget) { target in
                FootprintDetailView(
                    show: target.show,
                    archive: archive,
                    onDetailVisibilityChange: onArchiveVisibilityChange
                )
            }
            .sheet(isPresented: $isAddingShow) {
                AddShowCoordinatorSheet(intent: .historicalBackfill) { _ in }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .search:
                    FootprintSearchSheet(
                        archive: archive,
                        covers: FootprintCoverResolver.resolve(
                            shows: archive.shows,
                            fragments: fragments,
                            assets: assets
                        )
                    ) { show in
                        activeSheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            detailTarget = .init(show: show)
                        }
                    }
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
                case .share:
                    let covers = FootprintCoverResolver.resolve(
                        shows: archive.shows,
                        fragments: fragments,
                        assets: assets
                    )
                    FootprintShareSheet(
                        archive: archive,
                        covers: covers,
                        onSaved: { presentToast(BSLocalization.text("足迹图片已保存")) }
                    )
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                handleScreenshot(archive: archive)
            }
            .bsToastOverlay(toast, bottomPadding: 100)
    }

    /// Screenshot-to-share: taking a screenshot on the footprint dashboard
    /// opens the full-page long-image share sheet (the system screenshot
    /// itself is untouched). Throttled so burst screenshots don't retrigger.
    private func handleScreenshot(archive: FootprintArchiveSnapshot) {
        guard detailTarget == nil, activeSheet == nil, !isAddingShow, !archive.shows.isEmpty else { return }
        let now = Date()
        if let lastScreenshotPromptAt, now.timeIntervalSince(lastScreenshotPromptAt) < 2 { return }
        lastScreenshotPromptAt = now
        activeSheet = .share
    }

    private func content(_ archive: FootprintArchiveSnapshot) -> some View {
        let covers = FootprintCoverResolver.resolve(
            shows: archive.shows,
            fragments: fragments,
            assets: assets
        )
        return FootprintDashboardView(
            archive: archive,
            covers: covers,
            onShowSelected: { detailTarget = FootprintDetailDestination(show: $0) },
            onAdd: { isAddingShow = true },
            onSearch: { activeSheet = .search },
            onShare: {
                activeSheet = .share
            },
            onArchiveVisibilityChange: onArchiveVisibilityChange
        )
    }

    private func header(_ archive: FootprintArchiveSnapshot) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(BSLocalization.text("足迹"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("走过的现场和个人档案"))
                    .font(BSFont.tag)
                    .foregroundColor(BSColor.Stage.dim)
            }
            Spacer()
            HStack(spacing: BSSpacing.sm) {
                Button { activeSheet = .search } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                        .background(Color.white.opacity(0.075), in: Circle())
                        .overlay(Circle().stroke(BSColor.Stage.border))
                }
                .accessibilityLabel(BSLocalization.text("搜索足迹"))
                Button { activeSheet = .share } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(Color.white.opacity(0.075), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
                }
                .accessibilityLabel(BSLocalization.text("分享足迹"))
            }
        }
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSLayout.pageHeaderTopPadding)
    }

    private func hero(_ archive: FootprintArchiveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: BSSpacing.roomy) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(archive.shows.count)")
                        .font(.system(size: archive.shows.count >= 100 ? 72 : 92, weight: .ultraLight))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(red: 0.96, green: 0.94, blue: 0.89), BSColor.Stage.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Text(BSLocalization.text("场")).font(.system(size: 20)).foregroundColor(BSColor.Stage.muted)
                }
                .layoutPriority(1)
                VStack(alignment: .leading, spacing: 8) {
                    heroMetric(archive.currentYearCount, BSLocalization.text("今年"))
                    heroMetric(archive.cities.count, BSLocalization.text("城市"))
                    heroMetric(archive.venues.count, BSLocalization.text("场馆"))
                    heroMetric(ShowDurationFormatter.aggregate(totalMinutes: archive.totalDurationMinutes), BSLocalization.text("现场时长"))
                }
                .padding(.bottom, 11)
            }
            if let first = archive.firstShow {
                Text(BSLocalization.format("第一场现场：%@ · %@", footprintMonthText(first.effectiveDate, calendar: first.timingCalendar()), first.name))
                    .font(BSFont.tag)
                    .foregroundColor(BSColor.Stage.dim)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, BSSpacing.roomy)
    }

    private func heroMetric(_ value: Int, _ label: String) -> some View {
        heroMetric("\(value)", label)
    }

    private func heroMetric(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(BSFont.tag).foregroundColor(BSColor.Stage.dim)
        }
    }

    private func metrics(_ archive: FootprintArchiveSnapshot) -> some View {
        HStack(spacing: BSSpacing.sm) {
            metric(archive.artists.count, BSLocalization.text("看过的艺人"), .artist, archive)
            metric(archive.cities.count, BSLocalization.text("去过的城市"), .city, archive)
            metric(archive.venues.count, BSLocalization.text("到过的场馆"), .venue, archive)
        }
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSSpacing.md)
    }

    private func metric(
        _ value: Int,
        _ label: String,
        _ category: FootprintCategory,
        _ archive: FootprintArchiveSnapshot
    ) -> some View {
        NavigationLink {
            FootprintArchiveDetailView(
                archive: archive,
                covers: FootprintCoverResolver.resolve(
                    shows: archive.shows,
                    fragments: fragments,
                    assets: assets
                ),
                initialCategory: category,
                onVisibilityChange: onArchiveVisibilityChange
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value)").font(.system(size: 18, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
                Text(label).font(.system(size: 11.5)).foregroundColor(BSColor.Stage.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 12)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
        }
        .buttonStyle(.plain)
    }

    private func discovery(_ archive: FootprintArchiveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(BSLocalization.text("档案发现"), BSLocalization.text("你的现场画像"))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(BSLocalization.text("最常留下的足迹")).font(.system(size: 10.5, weight: .semibold)).tracking(1.1).foregroundColor(BSColor.Stage.accent)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach([FootprintCategory.artist, .city, .venue]) { category in
                            Button(category.title) { rankCategory = category }
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(rankCategory == category ? BSColor.Stage.foreground : BSColor.Stage.dim)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(rankCategory == category ? BSColor.Stage.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(3)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                }
                let ranking = archive.ranking(for: rankCategory)
                if let top = ranking.first {
                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(rankSummaryLabel)
                                .font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
                            Text(top.name)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(BSColor.Stage.foreground)
                                .lineLimit(1)
                                Text(BSLocalization.format("共记录 %lld 次", top.count))
                                .font(.system(size: 11)).foregroundColor(BSColor.Stage.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(top.count)")
                                .font(.system(size: 31, weight: .ultraLight))
                                .foregroundColor(rankColor)
                            Text(BSLocalization.text("次"))
                                .font(.system(size: 10.5)).foregroundColor(BSColor.Stage.dim)
                        }
                    }
                    .padding(.vertical, 2)
                }
                ForEach(ranking.prefix(3)) { item in
                    rankBar(item, maximum: ranking.first?.count ?? 1)
                }
                Divider().overlay(BSColor.Stage.border)
                HStack {
                    Text(ranking.count > 3 ? BSLocalization.format("其余 %lld 项收进完整统计", ranking.count - 3) : BSLocalization.text("完整统计已经收好"))
                        .font(.system(size: 11.5)).foregroundColor(BSColor.Stage.dim)
                    Spacer()
                    NavigationLink(BSLocalization.text("查看完整档案 →")) {
                        FootprintArchiveDetailView(
                            archive: archive,
                            covers: FootprintCoverResolver.resolve(
                                shows: archive.shows,
                                fragments: fragments,
                                assets: assets
                            ),
                            onVisibilityChange: onArchiveVisibilityChange
                        )
                    }
                    .font(BSFont.tag).foregroundColor(BSColor.Stage.accent)
                }
            }
            .padding(15)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))
        }
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.top, BSSpacing.lg)
    }

    private func rankBar(_ item: FootprintRankItem, maximum: Int) -> some View {
        HStack(spacing: 10) {
            Text(item.name)
                .font(.system(size: 12.5))
                .foregroundColor(BSColor.Stage.muted)
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(Color.white.opacity(0.06))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(rankColor.opacity(0.9))
                            .frame(width: geometry.size.width * CGFloat(item.count) / CGFloat(max(maximum, 1)))
                    }
            }
            .frame(height: 5)
            Text("\(item.count)").font(BSFont.tag).foregroundColor(BSColor.Stage.muted).frame(width: 22, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var rankColor: Color {
        switch rankCategory {
        case .overview, .artist: return BSColor.Stage.accent
        case .city: return Color(red: 0.56, green: 0.69, blue: 0.91)
        case .venue: return Color(red: 0.70, green: 0.61, blue: 0.78)
        }
    }

    private var rankSummaryLabel: String {
        switch rankCategory {
        case .overview, .artist: return BSLocalization.text("你最常看的艺人")
        case .city: return BSLocalization.text("你去过最多的城市")
        case .venue: return BSLocalization.text("你最熟悉的场馆")
        }
    }

    private func seedCard(_ archive: FootprintArchiveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BSLocalization.text("档案起点")).font(.system(size: 10.5, weight: .semibold)).tracking(1.1).foregroundColor(Color(red: 0.60, green: 0.72, blue: 0.91))
            Text(BSLocalization.text("第一场已经留下来了")).font(.system(size: 15, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("随着记录增加，这里会逐渐出现你最常看的艺人、去过最多的城市和场馆。"))
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).lineSpacing(3)
            HStack(spacing: 8) {
                seedMetric(archive.artists.first?.name ?? "—", BSLocalization.text("第一位艺人"))
                seedMetric(archive.cities.first?.name ?? "—", BSLocalization.text("第一座城市"))
            }
        }
        .padding(16)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(BSColor.Stage.border))
        .padding(.horizontal, BSSpacing.roomy).padding(.top, 18)
    }

    private func seedMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
            Text(label).font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(BSColor.Stage.border))
    }

    private func insight(_ label: String, _ item: FootprintRankItem?) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).frame(width: 112, alignment: .leading)
            Text(item?.name ?? BSLocalization.text("还没有记录")).font(BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
            Spacer()
            if let item { Text(BSLocalization.format("%lld 场", item.count)).font(BSFont.tag).foregroundColor(BSColor.Stage.dim) }
        }
    }

    private var timelineToolbar: some View {
        HStack(spacing: 8) {
            Button { activeSheet = .search } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(BSLocalization.text("搜索艺人、城市或场馆"))
                    Spacer()
                }
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted)
                .padding(.horizontal, 13).frame(height: 42)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(BSColor.Stage.border))
            }
            Button(BSLocalization.text("筛选")) { activeSheet = .search }
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted)
                .padding(.horizontal, 13).frame(height: 42)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(BSColor.Stage.border))
        }
        .padding(.horizontal, BSSpacing.roomy).padding(.top, 11)
    }

    private func yearHeader(_ group: FootprintYearGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(String(group.year)).font(.system(size: 26, weight: .ultraLight)).foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.format("%lld 场", group.shows.count)).font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
            Rectangle().fill(BSColor.Stage.border).frame(height: 1)
        }
        .padding(.horizontal, 22).padding(.top, BSSpacing.roomy)
    }

    private func showRow(_ show: Show) -> some View {
        Button {
            detailTarget = .init(show: show)
        } label: {
            HStack(spacing: 11) {
                AsyncImage(url: URL(string: show.coverImageURL ?? "")) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else {
                        LinearGradient(colors: [BSColor.Stage.glowBlue, BSColor.Stage.prepare], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.72)))
                    }
                }
                .frame(width: 46, height: 60).clipShape(RoundedRectangle(cornerRadius: 10)).saturation(0.75)
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.name).font(.system(size: 13.5, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                    Text([show.city, show.venueName].compactMap { value in
                        guard let value, !value.isEmpty else { return nil }; return value
                    }.joined(separator: " · "))
                        .font(.system(size: 11.8)).foregroundColor(BSColor.Stage.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(footprintDayText(show.effectiveDate, calendar: show.timingCalendar()))
                        .font(.system(size: 11.5)).foregroundColor(BSColor.Stage.muted)
                    if let duration = showDurationText(show) {
                        Text(duration).font(.system(size: 10.5)).foregroundColor(BSColor.Stage.dim)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(BSFont.V3.caption.weight(.semibold))
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
        .padding(.horizontal, BSSpacing.roomy).padding(.top, BSSpacing.sm)
    }

    /// 列表行的单场观看时长:已确认散场用真实时刻,否则录入结束时间或默认估算。
    private func showDurationText(_ show: Show) -> String? {
        let timeState = CurrentShowTimeState(show: show, calendar: show.timingCalendar())
        guard let minutes = ShowDurationFormatter.minutes(for: show, timeState: timeState) else { return nil }
        return ShowDurationFormatter.single(totalMinutes: minutes)
    }

    private func presentToast(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }

}

private enum FootprintSheet: String, Identifiable {
    case search
    case share
    var id: String { rawValue }
}

private struct FootprintSearchSheet: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onSelect: (Show) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter: FootprintSearchFilter = .all

    private var chips: [FootprintSearchFilter] {
        var values: [FootprintSearchFilter] = [.all]
        values += archive.years.prefix(2).map { .year($0.year) }
        values += archive.cities.prefix(2).map { .city($0.name) }
        return values
    }

    private var results: [Show] {
        archive.shows.filter { show in
            let searchable = ([show.name] + show.artistNames
                + [show.city, show.venueName, String(show.timingCalendar().component(.year, from: show.effectiveDate))]
                    .compactMap { $0 })
                .joined(separator: " ")
            let matchesQuery = query.isEmpty || searchable.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case let .year(year):
                matchesFilter = show.timingCalendar().component(.year, from: show.effectiveDate) == year
            case let .city(city):
                matchesFilter = show.city?.trimmingCharacters(in: .whitespacesAndNewlines) == city
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BSLocalization.text("搜索与筛选")).font(.system(size: 21, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("从历史记录中快速找到某位艺人、城市、场馆或年份。"))
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).padding(.top, 6)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(BSColor.Stage.muted)
                TextField(BSLocalization.text("搜索足迹"), text: $query).foregroundColor(BSColor.Stage.foreground)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(BSColor.Stage.border))
            .padding(.top, 15)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip.label) { filter = chip }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(filter == chip ? BSColor.Stage.accent : BSColor.Stage.muted)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(filter == chip ? BSColor.Stage.accent.opacity(0.07) : Color.white.opacity(0.03), in: Capsule())
                            .overlay(Capsule().stroke(filter == chip ? BSColor.Stage.accent.opacity(0.28) : BSColor.Stage.border))
                    }
                }
            }
            .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { show in
                        Button { onSelect(show) } label: {
                            HStack(spacing: 10) {
                                FootprintMiniPoster(show: show, cover: covers[show.id]).frame(width: 40, height: 52).clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(show.name).font(BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                                    Text("\([show.city, show.venueName].compactMap { $0 }.joined(separator: " · ")) · \(footprintDayText(show.effectiveDate, calendar: show.timingCalendar()))")
                                        .font(.system(size: 11.5)).foregroundColor(BSColor.Stage.muted).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(BSColor.Stage.border)
                    }
                    if results.isEmpty {
                        Text(BSLocalization.text("没有找到匹配的现场")).font(BSFont.body).foregroundColor(BSColor.Stage.muted).padding(.top, 28)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .padding(.top, 8)

            Button(BSLocalization.text("完成")) { dismiss() }
                .font(BSFont.caption).foregroundColor(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity).frame(height: 45)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 33).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BSColor.Stage.background.ignoresSafeArea())
    }
}

private enum FootprintSearchFilter: Hashable {
    case all
    case year(Int)
    case city(String)

    var label: String {
        switch self {
        case .all: return BSLocalization.text("全部")
        case let .year(year): return String(year)
        case let .city(city): return city
        }
    }
}

/// Warms cover caches so a freshly-built export view tree can render covers
/// synchronously (ImageRenderer snapshots before view `.task` loads finish).
enum FootprintCoverExportWarmup {
    static func warm(covers: [UUID: FootprintCover]) async {
        await withTaskGroup(of: Void.self) { group in
            for cover in covers.values {
                guard case let .remote(url) = cover.source else { continue }
                group.addTask {
                    _ = await ShowCoverImageCache.shared.image(from: url)
                }
            }
        }
    }

    /// Warms artist artwork/avatar images so the export tree's synchronous
    /// disk-cache reads hit (its `.task`/AsyncImage loads never complete
    /// before the snapshot).
    static func warm(artists: [FootprintArtistArchiveItem]) async {
        await withTaskGroup(of: Void.self) { group in
            for item in artists {
                for url in [item.albumArtworkURL, item.artworkURL].compactMap({ $0 }) {
                    group.addTask {
                        _ = await ShowCoverImageCache.shared.image(from: url)
                    }
                }
            }
        }
    }
}

/// One share-image export path for both the overview card and archive cards.
/// Sheets only supply content + size; rendering + photo-library I/O live here.
enum FootprintShareImageExport {
    @MainActor
    static func render<Content: View>(
        _ content: Content,
        size: CGSize
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: content.frame(width: size.width, height: size.height)
        )
        renderer.scale = 1
        return renderer.uiImage
    }

    /// Renders content at a fixed width with its intrinsic (full) height —
    /// the "long screenshot" path for the whole dashboard. Height is measured
    /// via a hosting controller, then the image is rendered in vertical tiles
    /// and stitched: ImageRenderer renders fully black once the pixel height
    /// exceeds the ~8192px GPU texture cap, so each tile stays below it.
    @MainActor
    static func renderLong<Content: View>(
        _ content: Content,
        width: CGFloat,
        scale: CGFloat = 1
    ) -> UIImage? {
        let controller = UIHostingController(rootView: content)
        let size = controller.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        guard size.height > 0 else { return nil }
        let tileHeight = min(size.height, floor(7000 / scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let stitcher = UIGraphicsImageRenderer(size: size, format: format)
        return stitcher.image { _ in
            var offsetY: CGFloat = 0
            while offsetY < size.height {
                let height = min(tileHeight, size.height - offsetY)
                let tile = content
                    .frame(width: width, height: size.height, alignment: .top)
                    .offset(y: -offsetY)
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()
                let renderer = ImageRenderer(content: tile)
                renderer.scale = scale
                if let tileImage = renderer.uiImage {
                    tileImage.draw(in: CGRect(x: 0, y: offsetY, width: width, height: height))
                }
                offsetY += height
            }
        }
    }

    @MainActor
    static func save<Content: View>(
        _ content: Content,
        size: CGSize
    ) async throws {
        guard let image = render(content, size: size) else {
            throw FootprintPhotoSaveError.rendererFailed
        }
        try await FootprintPhotoLibrary.save(image)
    }

    @MainActor
    static func saveLong<Content: View>(
        _ content: Content,
        width: CGFloat,
        scale: CGFloat = 1
    ) async throws {
        guard let image = renderLong(content, width: width, scale: scale) else {
            throw FootprintPhotoSaveError.rendererFailed
        }
        try await FootprintPhotoLibrary.save(image)
    }
}

/// Shared chrome for footprint share sheets: preview, save, share, cancel.
private struct FootprintShareActionSheet<Preview: View, ExportContent: View>: View {
    let title: String
    let subtitle: String
    let previewHeight: CGFloat
    let exportSize: CGSize
    /// When true, export renders at `exportSize.width` with intrinsic height
    /// (long-screenshot mode) instead of the fixed `exportSize`.
    var usesIntrinsicHeight = false
    /// Pixel scale for long-screenshot export (ignored for fixed-size cards).
    var exportScale: CGFloat = 1
    /// Async hook (e.g. cover-cache warmup) run before every export render.
    var beforeExport: (() async -> Void)? = nil
    /// When true, the preview fills the sheet's remaining height instead of
    /// the fixed `previewHeight` (used with the .large detent).
    var flexiblePreviewHeight = false
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let exportContent: () -> ExportContent
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var isExporting = false
    @State private var toast: BSToastPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 21, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(subtitle)
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).padding(.top, 6)

            preview()
                .frame(height: flexiblePreviewHeight ? nil : previewHeight)
                .frame(maxHeight: flexiblePreviewHeight ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10)))
                .padding(.top, 15)

            HStack(spacing: 8) {
                Button(BSLocalization.text("保存图片")) { Task { await saveImage() } }
                    .footprintShareAction(primary: false)
                    .disabled(isSaving || isExporting)
                Button(BSLocalization.text("分享图片")) { Task { await shareImage() } }
                    .footprintShareAction(primary: true)
                    .disabled(isSaving || isExporting)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 33).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bsToastOverlay(toast, bottomPadding: 24)
    }

    @MainActor
    private func exportImage() -> UIImage? {
        if usesIntrinsicHeight {
            return FootprintShareImageExport.renderLong(exportContent(), width: exportSize.width, scale: exportScale)
        }
        return FootprintShareImageExport.render(exportContent(), size: exportSize)
    }

    @MainActor
    private func saveImage() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await beforeExport?()
        do {
            if usesIntrinsicHeight {
                try await FootprintShareImageExport.saveLong(exportContent(), width: exportSize.width, scale: exportScale)
            } else {
                try await FootprintShareImageExport.save(exportContent(), size: exportSize)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? BSLocalization.text("照片保存失败，请重试。")
            presentToast(.failure, message: message)
            return
        }
        dismiss()
        onSaved?()
    }

    @MainActor
    private func shareImage() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        await beforeExport?()
        guard let image = exportImage(),
              let data = image.pngData() else {
            presentToast(.failure, message: BSLocalization.text("分享图片生成失败，请重试"))
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShow-footprint-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            guard SystemPNGSharePresenter.present(url: url) else {
                try? FileManager.default.removeItem(at: url)
                presentToast(.failure, message: BSLocalization.text("系统分享面板暂时无法打开"))
                return
            }
        } catch {
            presentToast(.failure, message: BSLocalization.text("分享图片生成失败，请重试"))
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload { toast = nil }
        }
    }
}

struct FootprintShareSheet: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onSaved: () -> Void

    var body: some View {
        FootprintShareActionSheet(
            title: BSLocalization.text("分享完整足迹"),
            subtitle: BSLocalization.text("整张长图包含你的完整足迹档案，可直接保存或分享。"),
            previewHeight: 368,
            exportSize: CGSize(width: FootprintDashboardExportView.layoutWidth, height: 0),
            usesIntrinsicHeight: true,
            exportScale: FootprintDashboardExportView.exportScale,
            beforeExport: {
                await FootprintCoverExportWarmup.warm(covers: covers)
                await FootprintCoverExportWarmup.warm(artists: archive.artistArchiveItems)
                _ = await FootprintCityCoordinateResolver.shared.coordinates(
                    for: archive.cityArchiveItems.map(\.name)
                )
            },
            flexiblePreviewHeight: true,
            preview: { FootprintDashboardExportPreview(archive: archive, covers: covers) },
            exportContent: { FootprintDashboardExportView(archive: archive, covers: covers) },
            onSaved: onSaved
        )
    }
}

struct FootprintArchiveShareSheet: View {
    let archive: FootprintArchiveSnapshot
    let category: FootprintCategory
    let onSaved: () -> Void

    var body: some View {
        FootprintShareActionSheet(
            title: FootprintArchiveShareCopy.title(for: category),
            subtitle: FootprintArchiveShareCopy.subtitle(for: category),
            previewHeight: 368,
            exportSize: CGSize(width: 1080, height: 1100),
            preview: { FootprintArchiveSharePreview(archive: archive, category: category) },
            exportContent: { FootprintArchiveSharePreview(archive: archive, category: category) },
            onSaved: onSaved
        )
    }
}

struct FootprintYearShareSheet: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let year: Int
    let onSaved: () -> Void

    var body: some View {
        FootprintShareActionSheet(
            title: BSLocalization.text("分享年度档案"),
            subtitle: BSLocalization.text("这一年的场次、月度节拍和年度之夜会汇总在同一张卡片。"),
            previewHeight: 368,
            exportSize: CGSize(width: 1080, height: 1100),
            beforeExport: {
                await FootprintCoverExportWarmup.warm(covers: covers)
            },
            preview: { FootprintYearSharePreview(archive: archive, covers: covers, year: year) },
            exportContent: { FootprintYearSharePreview(archive: archive, covers: covers, year: year) },
            onSaved: onSaved
        )
    }
}

/// 年度档案分享卡片:年份大数字 + 月度节拍柱状图 + 年度之夜,风格对齐 FootprintArchiveSharePreview。
private struct FootprintYearSharePreview: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let year: Int

    private var summary: FootprintYearArchiveSummary? { archive.yearArchiveSummary(for: year) }
    private var activity: FootprintYearActivity? { archive.yearActivity(for: year) }
    private var highlight: Show? { archive.yearHighlightShow(for: year, covers: covers) }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 361
            ZStack {
                Color(red: 0.035, green: 0.047, blue: 0.078)
                RadialGradient(colors: [BSColor.Stage.accent.opacity(0.24), .clear], center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.85)
                RadialGradient(colors: [BSColor.Stage.accent.opacity(0.08), .clear], center: .topLeading, startRadius: 0, endRadius: geometry.size.width * 0.72)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("BEFORESHOW · LIVE ARCHIVE")
                            .font(.system(size: 9.5 * scale, weight: .medium)).tracking(1.65 * scale).foregroundColor(BSColor.Stage.accent)
                        Spacer()
                        Text(String(year))
                            .font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.muted)
                            .padding(.horizontal, 8 * scale).padding(.vertical, 5 * scale)
                            .background(Color.white.opacity(0.045), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.10)))
                    }

                    Text("LIVE TRAIL")
                        .font(.system(size: 10 * scale, weight: .semibold)).tracking(1.2 * scale).foregroundColor(BSColor.Stage.accent)
                        .padding(.top, 14 * scale)

                    if let summary {
                        yearContent(summary: summary, scale: scale)
                    } else {
                        Text(BSLocalization.text("这一年还没有现场记录"))
                            .font(.system(size: 12 * scale)).foregroundColor(BSColor.Stage.muted)
                            .padding(.top, 12 * scale)
                    }

                    Spacer(minLength: 0)
                    HStack {
                        Text(BSLocalization.text("开场前"))
                        Spacer()
                        Text(footprintFullDateText(Date(), calendar: Calendar.current))
                    }
                    .font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.dim)
                }
                .padding(20 * scale)
            }
        }
    }

    @ViewBuilder
    private func yearContent(summary: FootprintYearArchiveSummary, scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
            Text(String(year))
                .font(.system(size: 38 * scale, weight: .ultraLight))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.89), BSColor.Stage.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(BSLocalization.format("%lld 场现场", summary.showCount))
                    .font(.system(size: 12 * scale, weight: .medium)).foregroundColor(BSColor.Stage.foreground)
                Text(ShowDurationFormatter.aggregate(totalMinutes: summary.durationMinutes))
                    .font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.muted)
            }
        }
        .padding(.top, 2 * scale)

        if let activity {
            yearRhythm(activity, scale: scale)
                .padding(.top, 12 * scale)
        }

        if let highlight {
            yearHighlightRow(highlight, scale: scale)
                .padding(.top, 10 * scale)
        }
    }

    private func yearRhythm(_ activity: FootprintYearActivity, scale: CGFloat) -> some View {
        let maxCount = max(1, activity.months.map(\.showCount).max() ?? 1)
        return VStack(alignment: .leading, spacing: 7 * scale) {
            Text(BSLocalization.text("年度节拍"))
                .font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.dim)
            Text(footprintYearPeakText(activity))
                .font(.system(size: 8.5 * scale)).foregroundColor(BSColor.Stage.muted)
            HStack(alignment: .bottom, spacing: 5 * scale) {
                ForEach(activity.months) { month in
                    VStack(spacing: 4 * scale) {
                        RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                            .fill(month.showCount == maxCount && month.showCount > 0 ? BSColor.Stage.accent : BSColor.Stage.accent.opacity(0.46))
                            .frame(height: max(3 * scale, CGFloat(month.showCount) / CGFloat(maxCount) * 52 * scale))
                        Text(monthLabel(month.month))
                            .font(.system(size: 6 * scale))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 68 * scale, alignment: .bottom)
        }
        .padding(11 * scale)
        .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 13 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13 * scale, style: .continuous).stroke(Color.white.opacity(0.075)))
    }

    private func yearHighlightRow(_ show: Show, scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                .frame(width: 50 * scale, height: 58 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous))
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(BSLocalization.text("THE NIGHT OF THE YEAR"))
                    .font(.system(size: 7.5 * scale, weight: .semibold))
                    .tracking(1.1 * scale)
                    .foregroundColor(BSColor.Stage.accent)
                Text(show.name)
                    .font(.system(size: 11.5 * scale, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text([footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()), FootprintTextNormalizer.nonEmptyTrimmed(show.city)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 8.5 * scale))
                    .foregroundColor(BSColor.Stage.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(9 * scale)
        .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 13 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13 * scale, style: .continuous).stroke(Color.white.opacity(0.075)))
    }

    private func monthLabel(_ month: Int) -> String {
        guard Calendar.current.shortMonthSymbols.indices.contains(month - 1) else { return "—" }
        return Calendar.current.shortMonthSymbols[month - 1].uppercased()
    }
}

private struct FootprintArchiveSharePreview: View {
    let archive: FootprintArchiveSnapshot
    let category: FootprintCategory

    private var accent: Color {
        switch category {
        case .overview, .artist: return BSColor.Stage.accent
        case .city: return Color(red: 0.60, green: 0.72, blue: 0.91)
        case .venue: return Color(red: 0.72, green: 0.64, blue: 0.79)
        }
    }

    private var rankings: [FootprintRankItem] { archive.ranking(for: category) }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 361
            ZStack {
                Color(red: 0.035, green: 0.047, blue: 0.078)
                RadialGradient(colors: [accent.opacity(0.24), .clear], center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.85)
                RadialGradient(colors: [accent.opacity(0.08), .clear], center: .topLeading, startRadius: 0, endRadius: geometry.size.width * 0.72)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("BEFORESHOW · LIVE ARCHIVE")
                            .font(.system(size: 9.5 * scale, weight: .medium)).tracking(1.65 * scale).foregroundColor(accent)
                        Spacer()
                        Text(FootprintArchiveShareCopy.chip(for: category))
                            .font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.muted)
                            .padding(.horizontal, 8 * scale).padding(.vertical, 5 * scale)
                            .background(Color.white.opacity(0.045), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.10)))
                    }

                    Text(FootprintArchiveShareCopy.kicker(for: category))
                        .font(.system(size: 10 * scale, weight: .semibold)).tracking(1.2 * scale).foregroundColor(accent)
                        .padding(.top, 23 * scale)

                    if category == .overview {
                        overviewContent(scale: scale)
                    } else {
                        categoryContent(scale: scale)
                    }

                    Spacer(minLength: 0)
                    HStack {
                        Text(BSLocalization.text("开场前"))
                        Spacer()
                        Text(footprintFullDateText(Date(), calendar: Calendar.current))
                    }
                    .font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.dim)
                }
                .padding(20 * scale)
            }
        }
    }

    @ViewBuilder
    private func overviewContent(scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
            Text("\(archive.shows.count)")
                .font(.system(size: 61 * scale, weight: .ultraLight))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.89), accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(BSLocalization.text("场现场")).font(.system(size: 14 * scale)).foregroundColor(BSColor.Stage.muted)
        }
        .padding(.top, 6 * scale)

        Text(BSLocalization.format("走过 %lld 座城市，留下 %lld 位艺人的现场记忆", archive.cities.count, archive.artists.count))
            .font(.system(size: 11 * scale)).foregroundColor(BSColor.Stage.muted).lineSpacing(1.55 * scale)
            .padding(.top, 7 * scale)

        HStack(spacing: 7 * scale) {
            shareMetric(archive.artists.count, BSLocalization.text("艺人"), scale: scale)
            shareMetric(archive.cities.count, BSLocalization.text("城市"), scale: scale)
            shareMetric(archive.venues.count, BSLocalization.text("场馆"), scale: scale)
            shareMetric(ShowDurationFormatter.aggregate(totalMinutes: archive.totalDurationMinutes), BSLocalization.text("现场时长"), scale: scale)
        }
        .padding(.top, 14 * scale)

        VStack(spacing: 7 * scale) {
            shareFocus(BSLocalization.text("最常看"), item: archive.artists.first, scale: scale)
            shareFocus(BSLocalization.text("最多去"), item: archive.cities.first, scale: scale)
            shareFocus(BSLocalization.text("最熟悉"), item: archive.venues.first, scale: scale)
        }
        .padding(.top, 13 * scale)
    }

    private func categoryContent(scale: CGFloat) -> some View {
        let top = rankings.first
        let label: String
        let count: Int
        let unit: String
        switch category {
        case .artist:
            label = BSLocalization.text("你最常看的艺人"); count = archive.artists.count; unit = BSLocalization.text("位艺人")
        case .city:
            label = BSLocalization.text("你去过最多的城市"); count = archive.cities.count; unit = BSLocalization.text("座城市")
        case .venue:
            label = BSLocalization.text("你最熟悉的场馆"); count = archive.venues.count; unit = BSLocalization.text("个场馆")
        case .overview:
            label = ""; count = 0; unit = ""
        }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 12 * scale) {
            VStack(alignment: .leading, spacing: 5 * scale) {
                Text(label).font(.system(size: 10 * scale)).foregroundColor(BSColor.Stage.dim)
                Text(top?.name ?? BSLocalization.text("还没有记录"))
                    .font(.system(size: 24 * scale, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let top {
                HStack(alignment: .lastTextBaseline, spacing: 4 * scale) {
                    Text("\(top.count)").font(.system(size: 42 * scale, weight: .ultraLight)).foregroundColor(accent)
                    Text(BSLocalization.text("场")).font(.system(size: 10 * scale)).foregroundColor(BSColor.Stage.muted)
                }
            }
        }
        .padding(.top, 6 * scale)

        VStack(spacing: 10 * scale) {
            ForEach(Array(rankings.prefix(3).enumerated()), id: \.element.id) { index, item in
                shareRank(index: index, item: item, maximum: rankings.first?.count ?? 1, scale: scale)
            }
        }
        .padding(.top, 18 * scale)

        HStack {
            Text(BSLocalization.format("共记录 %lld %@", count, unit))
            Spacer()
            Text(BSLocalization.format("%lld 场现场", archive.shows.count))
        }
        .font(.system(size: 10 * scale)).foregroundColor(BSColor.Stage.dim)
        .padding(.top, 16 * scale).padding(.bottom, 12 * scale)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.075)).frame(height: 1) }
        }
    }

    private func shareMetric(_ value: Int, _ label: String, scale: CGFloat) -> some View {
        shareMetric("\(value)", label, scale: scale)
    }

    private func shareMetric(_ value: String, _ label: String, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(value).font(.system(size: 15 * scale, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9 * scale)
        .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 12 * scale))
        .overlay(RoundedRectangle(cornerRadius: 12 * scale).stroke(Color.white.opacity(0.075)))
    }

    private func shareFocus(_ label: String, item: FootprintRankItem?, scale: CGFloat) -> some View {
        HStack(spacing: 9 * scale) {
            Text(label).font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.dim).frame(width: 45 * scale, alignment: .leading)
            Text(item?.name ?? BSLocalization.text("还没有记录")).font(.system(size: 11.5 * scale, weight: .medium)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
            Spacer(minLength: 0)
            if let item { Text(BSLocalization.format("%lld 场", item.count)).font(.system(size: 10.5 * scale)).foregroundColor(BSColor.Stage.muted) }
        }
    }

   private func shareRank(index: Int, item: FootprintRankItem, maximum: Int, scale: CGFloat) -> some View {
       HStack(spacing: 8 * scale) {
            Text("\(index + 1)").font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.dim).frame(width: 17 * scale, alignment: .leading)
           VStack(alignment: .leading, spacing: 6 * scale) {
               HStack {
                    Text(item.name).font(.system(size: 11.5 * scale, weight: .medium)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(BSLocalization.format("%lld 场", item.count)).font(.system(size: 10 * scale)).foregroundColor(BSColor.Stage.muted)
                }
                GeometryReader { geometry in
                    Capsule().fill(Color.white.opacity(0.065)).overlay(alignment: .leading) {
                        Capsule().fill(accent.opacity(0.86)).frame(width: geometry.size.width * CGFloat(item.count) / CGFloat(max(maximum, 1)))
                    }
                }
                .frame(height: 3 * scale)
            }
        }
    }
}

private struct FootprintMiniPoster: View {
    let show: Show
    let cover: FootprintCover?

    var body: some View {
        FootprintResolvedCoverImage(show: show, cover: cover)
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private extension View {
    func footprintShareAction(primary: Bool) -> some View {
        self
            .font(BSFont.caption)
            .foregroundColor(primary ? BSColor.Stage.background : BSColor.Stage.foreground)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(primary ? BSColor.Stage.foreground : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(primary ? Color.clear : BSColor.Stage.border))
    }
}

private struct FootprintBackground: View {
    var body: some View {
        ZStack {
            BSColor.Stage.background
            RadialGradient(colors: [BSColor.Stage.glowBlue.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 330)
            RadialGradient(colors: [BSColor.Stage.accent.opacity(0.09), .clear], center: .topTrailing, startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct FootprintEmptyView: View {
    let content: FootprintEmptyStateCopy.Content
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer()

            Image(systemName: "flag")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.045), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border))

            Text(content.title)
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundColor(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)

            Text(content.message)
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)

            if let actionTitle = content.actionTitle {
                Button(actionTitle, action: onAdd)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.background)
                    .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                    .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, BSSpacing.sm)
            }

            Spacer()
        }
        .padding(.horizontal, BSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Text(BSLocalization.text("足迹"))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, BSLayout.pageHeaderTopPadding)
        }
    }
}

private struct FootprintArchiveDetailView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onVisibilityChange: (Bool) -> Void
    @State private var category: FootprintCategory
    @State private var isShowingShare = false
    @State private var toast: BSToastPayload?
    /// 年度柱状图入场:柱子从 0 高度长到目标高度,逐根错开。
    @State private var barsGrown = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        archive: FootprintArchiveSnapshot,
        covers: [UUID: FootprintCover],
        initialCategory: FootprintCategory = .overview,
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.archive = archive
        self.covers = covers
        self.onVisibilityChange = onVisibilityChange
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        ZStack {
            FootprintBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Text("YOUR LIVE ARCHIVE").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundColor(BSColor.Stage.accent)
                    archiveHero
                    Section {
                        if category == .overview { overview } else { ranking }
                    } header: {
                        categoryTabs
                            .padding(.vertical, 8)
                            .background(BSColor.Stage.background.opacity(0.96))
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            archiveNavigation
        }
        .onAppear { onVisibilityChange(true) }
        .onDisappear { onVisibilityChange(false) }
        .sheet(isPresented: $isShowingShare) {
            FootprintArchiveShareSheet(
                archive: archive,
                category: category,
                onSaved: { presentToast(BSLocalization.text("足迹图片已保存")) }
            )
            .presentationDetents([.height(620)])
            .presentationCornerRadius(26)
            .presentationDragIndicator(.visible)
        }
        .bsToastOverlay(toast, bottomPadding: 100)
    }

    private func presentToast(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }

    private var archiveNavigation: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
                    .frame(width: 42, height: 42).background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(BSLocalization.text("完整档案")).font(.system(size: 17, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.format("统计截至 %@", footprintFullDateText(Date())))
                    .font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
            }
            Spacer()
            Button { isShowingShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
                    .frame(width: 42, height: 42).background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
            }
            .accessibilityLabel(BSLocalization.format("分享%@档案", category.title))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(BSColor.Stage.background.opacity(0.96))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1) }
    }

    private var archiveHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(archive.shows.count)")
                    .font(.system(size: archive.shows.count >= 100 ? 57 : 66, weight: .ultraLight))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.89), BSColor.Stage.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(BSLocalization.text("场现场")).font(.system(size: 15)).foregroundColor(BSColor.Stage.muted)
            }
            Text(BSLocalization.text("这里不管理下一场，只记录你已经走过的现场和留下的偏好。"))
                .font(.system(size: 12)).foregroundColor(BSColor.Stage.muted).lineSpacing(3).frame(maxWidth: 250, alignment: .leading).padding(.top, 8)
            HStack(spacing: 7) {
                archiveMetric(archive.artists.count, BSLocalization.text("艺人"))
                archiveMetric(archive.cities.count, BSLocalization.text("城市"))
                archiveMetric(archive.venues.count, BSLocalization.text("场馆"))
                archiveMetric(ShowDurationFormatter.aggregate(totalMinutes: archive.totalDurationMinutes), BSLocalization.text("现场时长"))
            }
            .padding(.top, 15)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [BSColor.Stage.accent.opacity(0.075), BSColor.Stage.surface], startPoint: .topLeading, endPoint: .center),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.10)))
    }

    private func archiveMetric(_ value: Int, _ label: String) -> some View {
        archiveMetric("\(value)", label)
    }

    private func archiveMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(BSFont.tag).foregroundColor(BSColor.Stage.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(Color.white.opacity(0.027), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.07)))
    }

    private var categoryTabs: some View {
        HStack(spacing: 2) {
            ForEach(FootprintCategory.allCases) { item in
                Button(item.title) { category = item }
                    .font(BSFont.tag).foregroundColor(category == item ? BSColor.Stage.foreground : BSColor.Stage.dim)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(category == item ? BSColor.Stage.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(3).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(BSLocalization.text("档案发现"), BSLocalization.text("从你的记录里长出来"))
            archiveInsight(BSLocalization.text("最常看的艺人"), archive.artists.first, .artist)
            archiveInsight(BSLocalization.text("去过最多的城市"), archive.cities.first, .city)
            archiveInsight(BSLocalization.text("最熟悉的场馆"), archive.venues.first, .venue)
            sectionTitle(BSLocalization.text("年度节拍"), BSLocalization.text("你的现场频率")).padding(.top, 10)
            yearRhythm
            if let first = archive.firstShow {
                sectionTitle(BSLocalization.text("档案起点"), BSLocalization.text("第一场现场")).padding(.top, 10)
                HStack(spacing: 12) {
                    FootprintMiniPoster(show: first, cover: covers[first.id]).frame(width: 47, height: 62).clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(footprintMonthText(first.effectiveDate, calendar: first.timingCalendar())).font(.system(size: 10.5)).foregroundColor(BSColor.Stage.dim)
                        Text(first.name).font(.system(size: 13, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(2)
                        Text(BSLocalization.text("这是整份现场档案开始生长的地方")).font(.system(size: 11)).foregroundColor(BSColor.Stage.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
                }
                .padding(12).background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(BSColor.Stage.border))
            }
        }
    }

    private func archiveInsight(_ title: String, _ item: FootprintRankItem?, _ target: FootprintCategory) -> some View {
        Button { category = target } label: {
            HStack(spacing: 12) {
                Text(insightMark(target))
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(insightColor(target))
                    .frame(width: 42, height: 42).background(insightColor(target).opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 11.5)).foregroundColor(BSColor.Stage.dim)
                    Text(item?.name ?? BSLocalization.text("还没有记录")).font(BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                }
                Spacer()
                if let item { Text(BSLocalization.format("%lld 场", item.count)).font(BSFont.caption).foregroundColor(BSColor.Stage.muted) }
            }
            .padding(12).background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
        }.buttonStyle(.plain)
    }

    private func insightColor(_ category: FootprintCategory) -> Color {
        switch category {
        case .overview, .artist: return BSColor.Stage.accent
        case .city: return Color(red: 0.60, green: 0.72, blue: 0.91)
        case .venue: return Color(red: 0.72, green: 0.64, blue: 0.79)
        }
    }

    private func insightMark(_ category: FootprintCategory) -> String {
        switch category {
        case .overview: return BSLocalization.text("档")
        case .artist: return BSLocalization.text("艺")
        case .city: return BSLocalization.text("城")
        case .venue: return BSLocalization.text("馆")
        }
    }

    private var yearRhythm: some View {
        let maximum = archive.years.map { $0.shows.count }.max() ?? 1
        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(Array(archive.years.reversed().enumerated()), id: \.element.id) { index, group in
                let targetHeight = max(9, 74 * CGFloat(group.shows.count) / CGFloat(max(maximum, 1)))
                VStack(spacing: 6) {
                    Text(BSLocalization.format("%lld 场 · %@", group.shows.count, yearDurationText(group)))
                        .font(.system(size: 10)).foregroundColor(BSColor.Stage.dim)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .opacity(barsGrown ? 1 : 0)
                    RoundedRectangle(cornerRadius: 5).fill(index.isMultiple(of: 2) ? BSColor.Stage.accent.opacity(0.72) : BSColor.Stage.glowBlue.opacity(0.72))
                        .frame(height: barsGrown ? targetHeight : 0)
                    Text(String(group.year)).font(.system(size: 10.5)).foregroundColor(BSColor.Stage.muted)
                }.frame(maxWidth: .infinity)
                // 每根柱子延后 55ms,读起来像波浪依次长出而不是整块弹起。
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(response: 0.5, dampingFraction: 0.78)
                            .delay(Double(index) * 0.055),
                    value: barsGrown
                )
            }
        }
        .frame(height: 112, alignment: .bottom).padding(16)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
        .onAppear { barsGrown = true }
    }

    /// 某一年的累计观看时长。
    private func yearDurationText(_ group: FootprintYearGroup) -> String {
        let minutes = group.shows.reduce(0) { partial, show in
            let timeState = CurrentShowTimeState(show: show, calendar: show.timingCalendar())
            return partial + (ShowDurationFormatter.minutes(for: show, timeState: timeState) ?? 0)
        }
        return ShowDurationFormatter.aggregate(totalMinutes: minutes)
    }

    private var ranking: some View {
        let values = archive.ranking(for: category)
        return VStack(alignment: .leading, spacing: 12) {
            if let top = archive.ranking(for: category).first {
                ZStack(alignment: .bottomTrailing) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(BSLocalization.format("%@排行", category.title)).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundColor(BSColor.Stage.accent)
                        Text(top.name).font(.system(size: 21, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(2)
                        Text(categorySubtitle).font(.system(size: 11.5)).foregroundColor(BSColor.Stage.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(top.count)").font(.system(size: 48, weight: .ultraLight)).foregroundColor(BSColor.Stage.accent.opacity(0.20))
                }
                .padding(15).background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(BSColor.Stage.accent.opacity(0.17)))
            }
            sectionTitle(BSLocalization.text("完整排行"), BSLocalization.format("%lld 条记录", values.count))
            let maximum = archive.ranking(for: category).first?.count ?? 1
            ForEach(Array(values.enumerated()), id: \.element.id) { index, item in
               let isFirst = index == 0
               let accent = insightColor(category)
               HStack(alignment: .top, spacing: 11) {
                    Text("\(index + 1)")
                       .font(isFirst ? .system(size: 12, weight: .bold) : BSFont.tag)
                       .foregroundColor(isFirst ? accent : BSColor.Stage.dim)
                       .frame(width: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if isFirst {
                                Text(BSLocalization.text("第一名"))
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.45)
                                    .foregroundColor(accent)
                            }
                            Text(item.name)
                                .font(isFirst ? .system(size: 13.5, weight: .semibold) : BSFont.caption)
                                .foregroundColor(BSColor.Stage.foreground)
                                .lineLimit(1)
                            Spacer()
                            Text(BSLocalization.format("%lld 场", item.count)).font(BSFont.tag).foregroundColor(isFirst ? accent : BSColor.Stage.foreground)
                        }
                        Text(rankContext(item)).font(.system(size: 10.8)).foregroundColor(BSColor.Stage.dim).lineLimit(1)
                        GeometryReader { geometry in
                            Capsule().fill(Color.white.opacity(0.055)).overlay(alignment: .leading) {
                                Capsule().fill(accent).frame(width: geometry.size.width * CGFloat(item.count) / CGFloat(max(maximum, 1)))
                            }
                        }.frame(height: isFirst ? 5 : 4)
                    }
                }
                .padding(.vertical, 12)
                Divider().overlay(BSColor.Stage.border)
            }
        }
    }

    private var categorySubtitle: String {
        switch category {
        case .overview: return ""
        case .artist: return BSLocalization.format("你反复回到谁的现场 · 共 %lld 位艺人", archive.artists.count)
        case .city: return BSLocalization.format("你的现场移动轨迹 · 共 %lld 座城市", archive.cities.count)
        case .venue: return BSLocalization.format("最熟悉的灯光与座位 · 共 %lld 个场馆", archive.venues.count)
        }
    }

    private func rankContext(_ item: FootprintRankItem) -> String {
        let related = archive.shows.filter { show in
            switch category {
            case .overview: return false
            case .artist: return show.artistNames.contains { $0.localizedCaseInsensitiveContains(item.name) }
            case .city: return show.city?.trimmingCharacters(in: .whitespacesAndNewlines) == item.name
            case .venue: return show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines) == item.name
            }
        }
        switch category {
        case .artist:
            let cities = Set(related.compactMap(\.city)).prefix(2).joined(separator: "、")
            return BSLocalization.format("%@ · 最近 %@", cities.isEmpty ? BSLocalization.text("现场记录") : cities, related.first.map { footprintMonthText($0.effectiveDate, calendar: $0.timingCalendar()) } ?? "—")
        case .city:
            return BSLocalization.format("%lld 个场馆 · 最近 %@", Set(related.compactMap(\.venueName)).count, related.first.map { footprintMonthText($0.effectiveDate, calendar: $0.timingCalendar()) } ?? "—")
        case .venue:
            return BSLocalization.format("%@ · 最近 %@", related.first?.city ?? BSLocalization.text("现场"), related.first.map { footprintMonthText($0.effectiveDate, calendar: $0.timingCalendar()) } ?? "—")
        case .overview: return ""
        }
    }

}

private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundColor(BSColor.Stage.muted)
        Text(subtitle).font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
    }
}

private func footprintMonthText(_ date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d.%02d", components.year ?? 0, components.month ?? 0)
}

private func footprintDayText(_ date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.month, .day], from: date)
    return String(format: "%02d.%02d", components.month ?? 0, components.day ?? 0)
}

func footprintFullDateText(_ date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d.%02d.%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
}
