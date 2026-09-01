import SwiftUI

// MARK: - Footprint Archive Detail

struct FootprintArchiveDetailView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onVisibilityChange: (Bool) -> Void
    @State private var category: FootprintCategory
    @State private var isShowingShare = false
    @State private var toast: BSToastPayload?
    /// 年度柱状图入场:柱子从 0 高度长到目标高度,逐根错开。
    @State private var barsGrown = false

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
            .bsNavigationScrollEdge()
        }
        .navigationTitle(BSLocalization.text("完整档案"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                FootprintNavigationTitle(title: BSLocalization.text("完整档案"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(BSLocalization.format("分享%@档案", category.title))
            }
        }
        .onAppear { onVisibilityChange(true) }
        .onDisappear { onVisibilityChange(false) }
        .sheet(isPresented: $isShowingShare) {
            FootprintArchiveShareSheet(
                archive: archive,
                category: category,
                onSaved: { presentToast(BSLocalization.text("足迹图片已保存")) }
            )
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
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(1).minimumScaleFactor(0.72)
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

struct FootprintMiniPoster: View {
    let show: Show
    let cover: FootprintCover?

    var body: some View {
        FootprintResolvedCoverImage(show: show, cover: cover)
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
