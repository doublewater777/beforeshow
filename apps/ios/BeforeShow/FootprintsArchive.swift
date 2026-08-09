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

private struct FootprintActionAnchorKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct FootprintArchiveSnapshot {
    let shows: [Show]
    let artists: [FootprintRankItem]
    let cities: [FootprintRankItem]
    let venues: [FootprintRankItem]
    let years: [FootprintYearGroup]
    let currentYearCount: Int

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
                title: "这场结束后，会来到足迹",
                message: "当前现场散场后会自动收进这里，\n场次、城市和回忆都会慢慢累积。",
                actionTitle: nil
            )
        }

        return Content(
            title: "这里会长出你的足迹",
            message: "补进第一场看过的现场，\n场次、城市和回忆都会慢慢累积。",
            actionTitle: "添加第一场现场"
        )
    }
}

private struct FootprintDetailDestination: Identifiable, Hashable {
    let show: Show
    let startsEditing: Bool

    var id: String { "\(show.id.uuidString)-\(startsEditing)" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum FootprintArchiveShareCopy {
    static func title(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return "分享完整档案"
        case .artist: return "分享艺人档案"
        case .city: return "分享城市档案"
        case .venue: return "分享场馆档案"
        }
    }

    static func subtitle(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return "总场次、艺人、城市和场馆偏好会汇总在同一张卡片。"
        case .artist: return "突出最常看的艺人，并展示艺人排行前三名。"
        case .city: return "突出你去过最多的城市，并展示城市排行前三名。"
        case .venue: return "突出最熟悉的场馆，并展示场馆排行前三名。"
        }
    }

    static func chip(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return "总览"
        case .artist: return "艺人"
        case .city: return "城市"
        case .venue: return "场馆"
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
        case .overview: return "我的完整现场档案"
        case .artist: return "我的艺人现场档案"
        case .city: return "我的城市现场档案"
        case .venue: return "我的场馆现场档案"
        }
    }

    static func subject(for category: FootprintCategory) -> String {
        switch category {
        case .overview: return "我的 BeforeShow 现场总览"
        case .artist: return "我的 BeforeShow 艺人档案"
        case .city: return "我的 BeforeShow 城市足迹"
        case .venue: return "我的 BeforeShow 场馆足迹"
        }
    }

    static func text(for category: FootprintCategory, archive: FootprintArchiveSnapshot) -> String {
        switch category {
        case .overview:
            var lines = [
                subject(for: category),
                "\(archive.shows.count) 场现场 · \(archive.artists.count) 位艺人 · \(archive.cities.count) 座城市 · \(archive.venues.count) 个场馆"
            ]
            if let top = archive.artists.first { lines.append("最常看：\(top.name) · \(top.count) 场") }
            if let first = archive.firstShow { lines.append("第一场：\(footprintMonthText(first.effectiveDate)) · \(first.name)") }
            return lines.joined(separator: "\n")
        case .artist:
            return [
                subject(for: category),
                "一共看过 \(archive.artists.count) 位艺人",
                leadingLine("最常看", from: archive.artists),
                rankingLine("艺人排行", items: archive.artists)
            ].joined(separator: "\n")
        case .city:
            return [
                subject(for: category),
                "现场足迹走过 \(archive.cities.count) 座城市",
                leadingLine("最常去", from: archive.cities),
                rankingLine("城市排行", items: archive.cities)
            ].joined(separator: "\n")
        case .venue:
            return [
                subject(for: category),
                "一共到过 \(archive.venues.count) 个场馆",
                leadingLine("最熟悉", from: archive.venues),
                rankingLine("场馆排行", items: archive.venues)
            ].joined(separator: "\n")
        }
    }

    private static func leadingLine(_ label: String, from items: [FootprintRankItem]) -> String {
        guard let first = items.first else { return "\(label)：还没有记录" }
        return "\(label)：\(first.name) · \(first.count) 场"
    }

    private static func rankingLine(_ label: String, items: [FootprintRankItem]) -> String {
        let ranking = items.prefix(3).map { "\($0.name) \($0.count) 场" }.joined(separator: "、")
        return "\(label)：\(ranking.isEmpty ? "还没有记录" : ranking)"
    }
}

enum FootprintPhotoSaveError: LocalizedError {
    case rendererFailed
    case authorizationDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .rendererFailed:
            return "足迹图片生成失败，请重试。"
        case .authorizationDenied:
            return "没有照片添加权限，请在系统设置中允许 BeforeShow 添加照片。"
        case .saveFailed:
            return "照片保存失败，请重试。"
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
            calendar.component(.year, from: $0.effectiveDate)
        }

        return FootprintArchiveSnapshot(
            shows: archived,
            artists: rank(archived.flatMap { splitArtists($0.artist) }),
            cities: rank(archived.compactMap { normalized($0.city) }),
            venues: rank(archived.compactMap { normalized($0.venueName) }),
            years: grouped.keys.sorted(by: >).map {
                FootprintYearGroup(year: $0, shows: grouped[$0] ?? [])
            },
            currentYearCount: grouped[calendar.component(.year, from: now)]?.count ?? 0
        )
    }

    private static func splitArtists(_ value: String?) -> [String] {
        guard let value else { return [] }
        var seen = Set<String>()
        let commaParts = value.components(separatedBy: CharacterSet(charactersIn: ",，、"))
        return commaParts
            .flatMap { part in
                // A slash is only a multi-artist separator when it is written as
                // a spaced delimiter. Names such as AC/DC remain intact.
                part.components(separatedBy: " / ")
            }
            .compactMap(normalized)
            .filter { seen.insert($0).inserted }
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @State private var isAddingShow = false
    @State private var detailTarget: FootprintDetailDestination?
    @State private var activeSheet: FootprintSheet?
    @State private var rankCategory: FootprintCategory = .artist
    @State private var toast: BSToastPayload?
    @State private var deleteTarget: Show?
    @State private var actionTarget: Show?
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
                ShowDetailView(
                    show: target.show,
                    startsEditing: target.startsEditing,
                    onDetailVisibilityChange: onArchiveVisibilityChange
                )
            }
            .sheet(isPresented: $isAddingShow) {
                AddShowCoordinatorSheet(intent: .historicalBackfill) {}
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .search:
                    FootprintSearchSheet(archive: archive) { show in
                        activeSheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            detailTarget = .init(show: show, startsEditing: false)
                        }
                    }
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(BSColor.Stage.surfaceRaised)
                case .share:
                    FootprintShareSheet(
                        archive: archive,
                        shareText: shareText(archive),
                        onCopied: { presentToast("已复制足迹文案") },
                        onSaved: { presentToast("足迹图片已保存") }
                    )
                    .presentationDetents([.height(555)])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(BSColor.Stage.surfaceRaised)
                }
            }
            .bsToastOverlay(toast, bottomPadding: 100)
            .alert("删除这场现场？", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ), presenting: deleteTarget) { show in
                Button("删除记录", role: .destructive) { delete(show) }
                Button("取消", role: .cancel) { deleteTarget = nil }
            } message: { _ in
                Text("删除后将无法恢复，这场现场也会从足迹统计中移除。")
            }
    }

    private func content(_ archive: FootprintArchiveSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(archive)
                hero(archive)
                metrics(archive)
                if archive.shows.count == 1 {
                    seedCard(archive)
                } else {
                    discovery(archive)
                }
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle("现场记录", "按年份收纳")
                    Spacer()
                    Button("补录历史") { isAddingShow = true }
                        .font(BSFont.tag)
                        .foregroundColor(BSColor.Stage.accent)
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.lg)

                timelineToolbar

                ForEach(archive.years) { group in
                    yearHeader(group)
                    ForEach(group.shows) { show in
                        showRow(show)
                    }
                }
            }
            .padding(.bottom, BSLayout.tabBarContentInset)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .overlayPreferenceValue(FootprintActionAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let show = actionTarget, let anchor = anchors[show.id] {
                    let buttonFrame = proxy[anchor]
                    let popupSize = CGSize(width: 188, height: 126)
                    let below = buttonFrame.maxY + 6
                    let popupTop = below + popupSize.height <= proxy.size.height - 16
                        ? below
                        : buttonFrame.minY - popupSize.height - 6
                    let centerX = min(
                        proxy.size.width - popupSize.width / 2 - 16,
                        max(popupSize.width / 2 + 16, buttonFrame.maxX - popupSize.width / 2)
                    )

                    FootprintRowActions(
                        onView: { actionTarget = nil; detailTarget = .init(show: show, startsEditing: false) },
                        onEdit: { actionTarget = nil; detailTarget = .init(show: show, startsEditing: true) },
                        onDelete: { actionTarget = nil; deleteTarget = show }
                    )
                    .position(x: centerX, y: popupTop + popupSize.height / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            }
            .animation(.easeOut(duration: 0.16), value: actionTarget?.id)
        }
    }

    private func header(_ archive: FootprintArchiveSnapshot) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("足迹")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text("走过的现场和个人档案")
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
                .accessibilityLabel("搜索足迹")
                Button { activeSheet = .share } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(Color.white.opacity(0.075), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
                }
                .accessibilityLabel("分享足迹")
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
                    Text("场").font(.system(size: 20)).foregroundColor(BSColor.Stage.muted)
                }
                .layoutPriority(1)
                VStack(alignment: .leading, spacing: 8) {
                    heroMetric(archive.currentYearCount, "今年")
                    heroMetric(archive.cities.count, "城市")
                    heroMetric(archive.venues.count, "场馆")
                }
                .padding(.bottom, 11)
            }
            if let first = archive.firstShow {
                Text("第一场现场：\(footprintMonthText(first.effectiveDate)) · \(first.name)")
                    .font(BSFont.tag)
                    .foregroundColor(BSColor.Stage.dim)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, BSSpacing.roomy)
    }

    private func heroMetric(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(value)").font(.system(size: 17, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(BSFont.tag).foregroundColor(BSColor.Stage.dim)
        }
    }

    private func metrics(_ archive: FootprintArchiveSnapshot) -> some View {
        HStack(spacing: BSSpacing.sm) {
            metric(archive.artists.count, "看过的艺人", .artist, archive)
            metric(archive.cities.count, "去过的城市", .city, archive)
            metric(archive.venues.count, "到过的场馆", .venue, archive)
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
            sectionTitle("档案发现", "你的现场画像")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("最常留下的足迹").font(.system(size: 10.5, weight: .semibold)).tracking(1.1).foregroundColor(BSColor.Stage.accent)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach([FootprintCategory.artist, .city, .venue]) { category in
                            Button(category.rawValue) { rankCategory = category }
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
                                Text("共记录 \(top.count) 次")
                                .font(.system(size: 11)).foregroundColor(BSColor.Stage.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(top.count)")
                                .font(.system(size: 31, weight: .ultraLight))
                                .foregroundColor(rankColor)
                            Text("次")
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
                    Text(ranking.count > 3 ? "其余 \(ranking.count - 3) 项收进完整统计" : "完整统计已经收好")
                        .font(.system(size: 11.5)).foregroundColor(BSColor.Stage.dim)
                    Spacer()
                    NavigationLink("查看完整档案 →") {
                        FootprintArchiveDetailView(
                            archive: archive,
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
        case .overview, .artist: return "你最常看的艺人"
        case .city: return "你去过最多的城市"
        case .venue: return "你最熟悉的场馆"
        }
    }

    private func seedCard(_ archive: FootprintArchiveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("档案起点").font(.system(size: 10.5, weight: .semibold)).tracking(1.1).foregroundColor(Color(red: 0.60, green: 0.72, blue: 0.91))
            Text("第一场已经留下来了").font(.system(size: 15, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text("随着记录增加，这里会逐渐出现你最常看的艺人、去过最多的城市和场馆。")
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).lineSpacing(3)
            HStack(spacing: 8) {
                seedMetric(archive.artists.first?.name ?? "—", "第一位艺人")
                seedMetric(archive.cities.first?.name ?? "—", "第一座城市")
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
            Text(item?.name ?? "还没有记录").font(BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
            Spacer()
            if let item { Text("\(item.count) 场").font(BSFont.tag).foregroundColor(BSColor.Stage.dim) }
        }
    }

    private var timelineToolbar: some View {
        HStack(spacing: 8) {
            Button { activeSheet = .search } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("搜索艺人、城市或场馆")
                    Spacer()
                }
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted)
                .padding(.horizontal, 13).frame(height: 42)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(BSColor.Stage.border))
            }
            Button("筛选") { activeSheet = .search }
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
            Text("\(group.shows.count) 场").font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
            Rectangle().fill(BSColor.Stage.border).frame(height: 1)
        }
        .padding(.horizontal, 22).padding(.top, BSSpacing.roomy)
    }

    private func showRow(_ show: Show) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 11) {
                Button {
                    actionTarget = nil
                    detailTarget = .init(show: show, startsEditing: false)
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
                }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(footprintDayText(show.effectiveDate))
                        .font(.system(size: 11.5)).foregroundColor(BSColor.Stage.muted)
                    Button {
                        actionTarget = actionTarget?.id == show.id ? nil : show
                    } label: {
                        VStack(spacing: 3) {
                            Circle().frame(width: 3, height: 3)
                            Circle().frame(width: 3, height: 3)
                            Circle().frame(width: 3, height: 3)
                        }
                            .foregroundColor(BSColor.Stage.dim)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("更多操作")
                    .anchorPreference(key: FootprintActionAnchorKey.self, value: .bounds) {
                        [show.id: $0]
                    }
                }
            }
        }
        .padding(10)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
        .padding(.horizontal, BSSpacing.roomy).padding(.top, BSSpacing.sm)
    }

    private func shareText(_ archive: FootprintArchiveSnapshot) -> String {
        var lines = ["我的 BeforeShow 现场足迹：\(archive.shows.count) 场现场", "去过 \(archive.cities.count) 座城市、\(archive.venues.count) 个场馆"]
        if let top = archive.artists.first { lines.append("最常看的艺人：\(top.name)（\(top.count) 场）") }
        return lines.joined(separator: "\n")
    }

    private func presentToast(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }

    private func delete(_ show: Show) {
        deleteTarget = nil
        Task { @MainActor in
            do {
                let result = try await ShowDeletionCoordinator.delete(
                    show,
                    from: shows,
                    selections: selections,
                    notificationStates: notificationStates,
                    in: modelContext
                )
                presentToast(
                    result == .mediaCleanupPending
                        ? "足迹记录已删除，部分本地副本将在下次启动继续清理"
                        : "已删除足迹记录"
                )
            } catch {
                modelContext.rollback()
                let payload = BSToastPayload(tone: .failure, message: "删除失败，请重试")
                toast = payload
            }
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
            let searchable = [show.name, show.artist, show.city, show.venueName, String(Calendar.current.component(.year, from: show.effectiveDate))]
                .compactMap { $0 }.joined(separator: " ")
            let matchesQuery = query.isEmpty || searchable.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case let .year(year):
                matchesFilter = Calendar.current.component(.year, from: show.effectiveDate) == year
            case let .city(city):
                matchesFilter = show.city?.trimmingCharacters(in: .whitespacesAndNewlines) == city
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color.white.opacity(0.18)).frame(width: 38, height: 4).frame(maxWidth: .infinity).padding(.bottom, 18)
            Text("搜索与筛选").font(.system(size: 21, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text("从历史记录中快速找到某位艺人、城市、场馆或年份。")
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).padding(.top, 6)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(BSColor.Stage.muted)
                TextField("搜索足迹", text: $query).foregroundColor(BSColor.Stage.foreground)
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
                                FootprintMiniPoster(show: show).frame(width: 40, height: 52).clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(show.name).font(BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                                    Text("\([show.city, show.venueName].compactMap { $0 }.joined(separator: " · ")) · \(footprintDayText(show.effectiveDate))")
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
                        Text("没有找到匹配的现场").font(BSFont.body).foregroundColor(BSColor.Stage.muted).padding(.top, 28)
                    }
                }
            }
            .padding(.top, 8)

            Button("完成") { dismiss() }
                .font(BSFont.caption).foregroundColor(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity).frame(height: 45)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BSColor.Stage.surfaceRaised.ignoresSafeArea())
    }
}

private enum FootprintSearchFilter: Hashable {
    case all
    case year(Int)
    case city(String)

    var label: String {
        switch self {
        case .all: return "全部"
        case let .year(year): return String(year)
        case let .city(city): return city
        }
    }
}

/// One share-image export path for both the overview card and archive cards.
/// Sheets only supply content + size; rendering + photo-library I/O live here.
enum FootprintShareImageExport {
    @MainActor
    static func save<Content: View>(
        _ content: Content,
        size: CGSize
    ) async throws {
        let renderer = ImageRenderer(
            content: content.frame(width: size.width, height: size.height)
        )
        renderer.scale = 1
        guard let image = renderer.uiImage else {
            throw FootprintPhotoSaveError.rendererFailed
        }
        try await FootprintPhotoLibrary.save(image)
    }
}

/// Shared chrome for footprint share sheets: preview, copy, save, cancel.
private struct FootprintShareActionSheet<Preview: View>: View {
    let title: String
    let subtitle: String
    let previewHeight: CGFloat
    let shareText: String
    let exportSize: CGSize
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let exportContent: () -> Preview
    var onCopied: (() -> Void)? = nil
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color.white.opacity(0.18)).frame(width: 38, height: 4).frame(maxWidth: .infinity).padding(.bottom, 18)
            Text(title).font(.system(size: 21, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(subtitle)
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).padding(.top, 6)

            preview()
                .frame(height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10)))
                .padding(.top, 15)

            HStack(spacing: 8) {
                Button("复制文案") {
                    UIPasteboard.general.string = shareText
                    dismiss()
                    onCopied?()
                }
                .footprintShareAction(primary: false)
                Button("保存图片") { Task { await saveImage() } }
                    .footprintShareAction(primary: true)
                    .disabled(isSaving)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BSColor.Stage.surfaceRaised.ignoresSafeArea())
        .alert("无法保存图片", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "请重试。")
        }
    }

    @MainActor
    private func saveImage() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await FootprintShareImageExport.save(exportContent(), size: exportSize)
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "照片保存失败，请重试。"
            return
        }
        dismiss()
        onSaved?()
    }
}

private struct FootprintShareSheet: View {
    let archive: FootprintArchiveSnapshot
    let shareText: String
    let onCopied: () -> Void
    let onSaved: () -> Void

    var body: some View {
        FootprintShareActionSheet(
            title: "分享我的足迹",
            subtitle: "默认隐藏具体日期和详细行程，只分享你选择的档案信息。",
            previewHeight: 330,
            shareText: shareText,
            exportSize: CGSize(width: 1080, height: 1350),
            preview: { FootprintSharePreview(archive: archive) },
            exportContent: { FootprintSharePreview(archive: archive) },
            onCopied: onCopied,
            onSaved: onSaved
        )
    }
}

private struct FootprintSharePreview: View {
    let archive: FootprintArchiveSnapshot

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 361
            ZStack {
                Color(red: 0.035, green: 0.047, blue: 0.078)
                RadialGradient(colors: [BSColor.Stage.accent.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.75)
                RadialGradient(colors: [BSColor.Stage.glowBlue.opacity(0.20), .clear], center: .topLeading, startRadius: 0, endRadius: geometry.size.width * 0.72)
                VStack(alignment: .leading, spacing: 0) {
                    Text("BEFORESHOW · 我的现场足迹")
                        .font(.system(size: 11 * scale, weight: .medium)).tracking(2 * scale).foregroundColor(BSColor.Stage.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                        Text("\(archive.shows.count)").font(.system(size: 82 * scale, weight: .ultraLight)).foregroundColor(BSColor.Stage.foreground)
                        Text("场现场").font(.system(size: 17 * scale)).foregroundColor(BSColor.Stage.muted)
                    }
                    .padding(.top, 28 * scale)
                    Text("\(archive.cities.count) 座城市 · \(archive.venues.count) 个场馆")
                        .font(.system(size: 17 * scale, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
                    Text("最常看：\(archive.artists.first?.name ?? "—")\n第一场：\(archive.firstShow.map { footprintMonthText($0.effectiveDate) } ?? "—")")
                        .font(.system(size: 12 * scale)).foregroundColor(BSColor.Stage.muted).lineSpacing(5 * scale).padding(.top, 7 * scale)
                    Spacer()
                    HStack {
                        Text("开场前")
                        Spacer()
                        Text(String(Calendar.current.component(.year, from: Date())))
                    }
                    .font(.system(size: 10.5 * scale)).foregroundColor(BSColor.Stage.dim)
                }
                .padding(24 * scale)
            }
        }
    }
}

private struct FootprintArchiveShareSheet: View {
    let archive: FootprintArchiveSnapshot
    let category: FootprintCategory

    var body: some View {
        FootprintShareActionSheet(
            title: FootprintArchiveShareCopy.title(for: category),
            subtitle: FootprintArchiveShareCopy.subtitle(for: category),
            previewHeight: 368,
            shareText: FootprintArchiveShareCopy.text(for: category, archive: archive),
            exportSize: CGSize(width: 1080, height: 1100),
            preview: { FootprintArchiveSharePreview(archive: archive, category: category) },
            exportContent: { FootprintArchiveSharePreview(archive: archive, category: category) }
        )
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
                        Text("开场前")
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
            Text("场现场").font(.system(size: 14 * scale)).foregroundColor(BSColor.Stage.muted)
        }
        .padding(.top, 6 * scale)

        Text("走过 \(archive.cities.count) 座城市，留下 \(archive.artists.count) 位艺人的现场记忆")
            .font(.system(size: 11 * scale)).foregroundColor(BSColor.Stage.muted).lineSpacing(1.55 * scale)
            .padding(.top, 7 * scale)

        HStack(spacing: 7 * scale) {
            shareMetric(archive.artists.count, "艺人", scale: scale)
            shareMetric(archive.cities.count, "城市", scale: scale)
            shareMetric(archive.venues.count, "场馆", scale: scale)
        }
        .padding(.top, 14 * scale)

        VStack(spacing: 7 * scale) {
            shareFocus("最常看", item: archive.artists.first, scale: scale)
            shareFocus("最多去", item: archive.cities.first, scale: scale)
            shareFocus("最熟悉", item: archive.venues.first, scale: scale)
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
            label = "你最常看的艺人"; count = archive.artists.count; unit = "位艺人"
        case .city:
            label = "你去过最多的城市"; count = archive.cities.count; unit = "座城市"
        case .venue:
            label = "你最熟悉的场馆"; count = archive.venues.count; unit = "个场馆"
        case .overview:
            label = ""; count = 0; unit = ""
        }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 12 * scale) {
            VStack(alignment: .leading, spacing: 5 * scale) {
                Text(label).font(.system(size: 10 * scale)).foregroundColor(BSColor.Stage.dim)
                Text(top?.name ?? "还没有记录")
                    .font(.system(size: 24 * scale, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let top {
                HStack(alignment: .lastTextBaseline, spacing: 4 * scale) {
                    Text("\(top.count)").font(.system(size: 42 * scale, weight: .ultraLight)).foregroundColor(accent)
                    Text("场").font(.system(size: 10 * scale)).foregroundColor(BSColor.Stage.muted)
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
            Text("共记录 \(count) \(unit)")
            Spacer()
            Text("\(archive.shows.count) 场现场")
        }
        .font(.system(size: 10 * scale)).foregroundColor(BSColor.Stage.dim)
        .padding(.top, 16 * scale).padding(.bottom, 12 * scale)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.075)).frame(height: 1) }
        }
    }

    private func shareMetric(_ value: Int, _ label: String, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text("\(value)").font(.system(size: 15 * scale, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
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
            Text(item?.name ?? "还没有记录").font(.system(size: 11.5 * scale, weight: .medium)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
            Spacer(minLength: 0)
            if let item { Text("\(item.count) 场").font(.system(size: 10.5 * scale)).foregroundColor(BSColor.Stage.muted) }
        }
    }

    private func shareRank(index: Int, item: FootprintRankItem, maximum: Int, scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            Text(String(format: "%02d", index + 1)).font(.system(size: 9.5 * scale)).foregroundColor(BSColor.Stage.dim).frame(width: 17 * scale, alignment: .leading)
            VStack(alignment: .leading, spacing: 6 * scale) {
                HStack {
                    Text(item.name).font(.system(size: 11.5 * scale, weight: .medium)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(item.count) 场").font(.system(size: 10 * scale)).foregroundColor(BSColor.Stage.muted)
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
    var body: some View {
        AsyncImage(url: URL(string: show.coverImageURL ?? "")) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else {
                LinearGradient(colors: [BSColor.Stage.glowBlue, BSColor.Stage.prepare], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.72)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct FootprintRowActions: View {
    let onView: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            action("查看详情", icon: "eye", color: BSColor.Stage.accent, highlighted: true, onView)
            action("编辑记录", icon: "pencil", onEdit)
            action("删除记录", icon: "trash", color: BSColor.Stage.danger, onDelete)
        }
        .padding(6)
        .frame(width: 188)
        .background(BSColor.Stage.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 19, y: 10)
    }

    private func action(
        _ title: String,
        icon: String,
        color: Color = BSColor.Stage.foreground,
        highlighted: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 17)
                Text(title).font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
                .foregroundColor(color)
                .padding(.horizontal, 11).frame(height: 38)
                .background(highlighted ? BSColor.Stage.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
            Text("足迹")
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
    let onVisibilityChange: (Bool) -> Void
    @State private var category: FootprintCategory
    @State private var isShowingShare = false

    @Environment(\.dismiss) private var dismiss

    init(
        archive: FootprintArchiveSnapshot,
        initialCategory: FootprintCategory = .overview,
        onVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.archive = archive
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
            FootprintArchiveShareSheet(archive: archive, category: category)
                .presentationDetents([.height(620)])
                .presentationCornerRadius(26)
                .presentationDragIndicator(.hidden)
                .presentationBackground(BSColor.Stage.surfaceRaised)
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
                Text("完整档案").font(.system(size: 17, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
                Text("统计截至 \(footprintFullDateText(Date()))")
                    .font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
            }
            Spacer()
            Button { isShowingShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
                    .frame(width: 42, height: 42).background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
            }
            .accessibilityLabel("分享\(category.rawValue)档案")
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
                Text("场现场").font(.system(size: 15)).foregroundColor(BSColor.Stage.muted)
            }
            Text("这里不管理下一场，只记录你已经走过的现场和留下的偏好。")
                .font(.system(size: 12)).foregroundColor(BSColor.Stage.muted).lineSpacing(3).frame(maxWidth: 250, alignment: .leading).padding(.top, 8)
            HStack(spacing: 7) {
                archiveMetric(archive.artists.count, "艺人")
                archiveMetric(archive.cities.count, "城市")
                archiveMetric(archive.venues.count, "场馆")
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
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)").font(.system(size: 16, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(BSFont.tag).foregroundColor(BSColor.Stage.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(Color.white.opacity(0.027), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.07)))
    }

    private var categoryTabs: some View {
        HStack(spacing: 2) {
            ForEach(FootprintCategory.allCases) { item in
                Button(item.rawValue) { category = item }
                    .font(BSFont.tag).foregroundColor(category == item ? BSColor.Stage.foreground : BSColor.Stage.dim)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(category == item ? BSColor.Stage.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(3).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("档案发现", "从你的记录里长出来")
            archiveInsight("最常看的艺人", archive.artists.first, .artist)
            archiveInsight("去过最多的城市", archive.cities.first, .city)
            archiveInsight("最熟悉的场馆", archive.venues.first, .venue)
            sectionTitle("年度节拍", "你的现场频率").padding(.top, 10)
            yearRhythm
            if let first = archive.firstShow {
                sectionTitle("档案起点", "第一场现场").padding(.top, 10)
                HStack(spacing: 12) {
                    FootprintMiniPoster(show: first).frame(width: 47, height: 62).clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(footprintMonthText(first.effectiveDate)).font(.system(size: 10.5)).foregroundColor(BSColor.Stage.dim)
                        Text(first.name).font(.system(size: 13, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(2)
                        Text("这是整份现场档案开始生长的地方").font(.system(size: 11)).foregroundColor(BSColor.Stage.muted)
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
                    Text(item?.name ?? "还没有记录").font(BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                }
                Spacer()
                if let item { Text("\(item.count) 场").font(BSFont.caption).foregroundColor(BSColor.Stage.muted) }
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
        case .overview: return "档"
        case .artist: return "艺"
        case .city: return "城"
        case .venue: return "馆"
        }
    }

    private var yearRhythm: some View {
        let maximum = archive.years.map { $0.shows.count }.max() ?? 1
        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(Array(archive.years.reversed().enumerated()), id: \.element.id) { index, group in
                VStack(spacing: 6) {
                    Text("\(group.shows.count) 场").font(.system(size: 10)).foregroundColor(BSColor.Stage.dim)
                    RoundedRectangle(cornerRadius: 5).fill(index.isMultiple(of: 2) ? BSColor.Stage.accent.opacity(0.72) : BSColor.Stage.glowBlue.opacity(0.72))
                        .frame(height: max(9, 74 * CGFloat(group.shows.count) / CGFloat(max(maximum, 1))))
                    Text(String(group.year)).font(.system(size: 10.5)).foregroundColor(BSColor.Stage.muted)
                }.frame(maxWidth: .infinity)
            }
        }
        .frame(height: 112, alignment: .bottom).padding(16)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var ranking: some View {
        let values = archive.ranking(for: category)
        return VStack(alignment: .leading, spacing: 12) {
            if let top = archive.ranking(for: category).first {
                ZStack(alignment: .bottomTrailing) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(category.rawValue)排行").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundColor(BSColor.Stage.accent)
                        Text(top.name).font(.system(size: 21, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(2)
                        Text(categorySubtitle).font(.system(size: 11.5)).foregroundColor(BSColor.Stage.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(top.count)").font(.system(size: 48, weight: .ultraLight)).foregroundColor(BSColor.Stage.accent.opacity(0.20))
                }
                .padding(15).background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(BSColor.Stage.accent.opacity(0.17)))
            }
            sectionTitle("完整排行", "\(values.count) 条记录")
            let maximum = archive.ranking(for: category).first?.count ?? 1
            ForEach(Array(values.enumerated()), id: \.element.id) { index, item in
                let isFirst = index == 0
                let accent = insightColor(category)
                HStack(alignment: .top, spacing: 11) {
                    Text(String(format: "%02d", index + 1))
                        .font(isFirst ? .system(size: 12, weight: .bold) : BSFont.tag)
                        .foregroundColor(isFirst ? accent : BSColor.Stage.dim)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if isFirst {
                                Text("第一名")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.45)
                                    .foregroundColor(accent)
                            }
                            Text(item.name)
                                .font(isFirst ? .system(size: 13.5, weight: .semibold) : BSFont.caption)
                                .foregroundColor(BSColor.Stage.foreground)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.count) 场").font(BSFont.tag).foregroundColor(isFirst ? accent : BSColor.Stage.foreground)
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
        case .artist: return "你反复回到谁的现场 · 共 \(archive.artists.count) 位艺人"
        case .city: return "你的现场移动轨迹 · 共 \(archive.cities.count) 座城市"
        case .venue: return "最熟悉的灯光与座位 · 共 \(archive.venues.count) 个场馆"
        }
    }

    private func rankContext(_ item: FootprintRankItem) -> String {
        let related = archive.shows.filter { show in
            switch category {
            case .overview: return false
            case .artist: return show.artist?.localizedCaseInsensitiveContains(item.name) == true
            case .city: return show.city?.trimmingCharacters(in: .whitespacesAndNewlines) == item.name
            case .venue: return show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines) == item.name
            }
        }
        switch category {
        case .artist:
            let cities = Set(related.compactMap(\.city)).prefix(2).joined(separator: "、")
            return "\(cities.isEmpty ? "现场记录" : cities) · 最近 \(related.first.map { footprintMonthText($0.effectiveDate) } ?? "—")"
        case .city:
            return "\(Set(related.compactMap(\.venueName)).count) 个场馆 · 最近 \(related.first.map { footprintMonthText($0.effectiveDate) } ?? "—")"
        case .venue:
            return "\(related.first?.city ?? "现场") · 最近 \(related.first.map { footprintMonthText($0.effectiveDate) } ?? "—")"
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

private func footprintFullDateText(_ date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d.%02d.%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
}
