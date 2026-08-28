import SwiftData
import SwiftUI

struct FootprintDashboardView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onShowSelected: (Show) -> Void
    let onAdd: () -> Void
    let onSearch: () -> Void
    let onShare: () -> Void
    let onArchiveVisibilityChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var sections: FootprintDashboardSections {
        FootprintDashboardSections(
            archive: archive,
            covers: covers,
            onShowSelected: onShowSelected,
            onAdd: onAdd,
            onArchiveVisibilityChange: onArchiveVisibilityChange
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                hero
                if sections.visibility.showsTrend {
                    sections.trendSection.bsScrollReveal(reduceMotion: reduceMotion)
                }
                sections.artistSection.bsScrollReveal(reduceMotion: reduceMotion)
                sections.citySection.bsScrollReveal(reduceMotion: reduceMotion)
                sections.venueSection.bsScrollReveal(reduceMotion: reduceMotion)
                sections.memorySection.bsScrollReveal(reduceMotion: reduceMotion)
                sections.timelineSection.bsScrollReveal(reduceMotion: reduceMotion)
            }
            .padding(.bottom, BSLayout.tabBarContentInset)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion { hasAppeared = true }
            else { withAnimation(.easeOut(duration: 0.55)) { hasAppeared = true } }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(BSLocalization.text("足迹"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("走过的现场，慢慢长成你的档案"))
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.dim)
            }
            Spacer()
            HStack(spacing: BSSpacing.sm) {
                dashboardIcon("magnifyingglass", label: BSLocalization.text("搜索足迹"), action: onSearch)
                dashboardIcon("square.and.arrow.up", label: BSLocalization.text("分享足迹"), action: onShare)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, BSLayout.pageHeaderTopPadding)
    }

    private func dashboardIcon(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.075), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border))
        }
        .accessibilityLabel(label)
    }

    private var hero: some View {
        PassportCardHeroView(archive: archive, covers: covers)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : 8)
    }

    private func dashboardMetric(_ value: Int, _ label: String) -> some View { dashboardMetric("\(value)", label) }

    private func dashboardMetric(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(.system(size: 11)).foregroundColor(BSColor.Stage.muted)
        }
    }

    private var statsSection: some View {
        HStack(spacing: 8) {
            footprintStat(value: archive.artistArchiveItems.count, label: BSLocalization.text("看过的艺人"))
            footprintStat(value: archive.cityArchiveItems.count, label: BSLocalization.text("去过的城市"))
            footprintStat(value: archive.venueArchiveItems.count, label: BSLocalization.text("到过的场馆"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private func footprintStat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.system(size: 20, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(.system(size: 10)).foregroundColor(BSColor.Stage.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BSColor.Stage.border))
    }
}

/// Dashboard sections shared by the live dashboard (`LazyVStack`) and the
/// long-image export view (plain `VStack`). A pure value type: stateful
/// subviews own their own state so offscreen export renders stay consistent.
@MainActor
struct FootprintDashboardSections {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onShowSelected: (Show) -> Void
    let onAdd: () -> Void
    let onArchiveVisibilityChange: (Bool) -> Void
    /// Export renders via ImageRenderer, where a horizontal ScrollView
    /// snapshots blank — so the export swaps it for a plain clipped HStack.
    var isForExport = false

    var visibility: FootprintVisibility { archive.visibility }

    var trendSection: some View {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let activity = archive.yearActivity(for: currentYear) ?? archive.allYearActivities.first
        let visibleMonth = activity?.year == currentYear ? calendar.component(.month, from: Date()) : nil
        return dashboardSection(
            title: BSLocalization.text("现场轨迹"),
            subtitle: nil,
            action: isForExport || archive.years.isEmpty ? nil : BSLocalization.text("查看全部 →"),
            actionDestination: archive.years.isEmpty ? nil : AnyView(
                FootprintYearArchiveView(
                    archive: archive,
                    covers: covers,
                    onDetailVisibilityChange: onArchiveVisibilityChange
                )
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(activity?.totalShows ?? archive.currentYearCount)")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(BSColor.Stage.foreground)
                        Text(BSLocalization.text("场现场"))
                            .font(.system(size: 10))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    Spacer()
                    if let activity, let peak = activity.peakMonth {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(BSLocalization.format("%@ · %lld 场", BSLocalization.text(footprintMonthKey(peak.month)), peak.showCount))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(BSColor.Stage.accent)
                            Text(BSLocalization.text(activity.year == currentYear ? "今年目前最密集" : "这一年最密集"))
                                .font(.system(size: 8))
                                .foregroundColor(BSColor.Stage.muted)
                        }
                        .multilineTextAlignment(.trailing)
                    }
                }
                if let activity {
                    FootprintTrendChart(
                        year: activity.year,
                        months: activity.months,
                        currentMonth: visibleMonth,
                        peakMonth: activity.peakMonth?.month
                    )
                    .frame(height: 170)
                }
            }
        }
    }

    var artistSection: some View {
        let items = archive.artistArchiveItems
        return Group {
            if items.isEmpty {
                EmptyView()
            } else {
        dashboardSection(title: BSLocalization.text("艺人足迹"), action: isForExport || items.isEmpty ? nil : BSLocalization.text("查看全部 →"), actionDestination: items.isEmpty ? nil : AnyView(FootprintArtistArchiveView(archive: archive, covers: covers, onDetailVisibilityChange: onArchiveVisibilityChange)), contentPadding: 0) {
            if let first = items.first {
                FootprintTopArtistCard(
                    items: items,
                    first: first,
                    archive: archive,
                    covers: covers,
                    isForExport: isForExport,
                    onArchiveVisibilityChange: onArchiveVisibilityChange
                )
            }
        }
            }
        }
    }

    var citySection: some View {
        let items = archive.cityArchiveItems
        return Group {
            if items.isEmpty {
                EmptyView()
            } else {
        dashboardSection(title: BSLocalization.text("城市足迹"), action: isForExport || items.isEmpty ? nil : BSLocalization.text("查看全部 →"), actionDestination: items.isEmpty ? nil : AnyView(FootprintCityArchiveView(archive: archive, covers: covers, onDetailVisibilityChange: onArchiveVisibilityChange)), contentPadding: 0) {
            if isForExport {
                FootprintGeoMap(items: items, showsControls: false)
            } else {
                NavigationLink {
                    FootprintCityArchiveView(archive: archive, covers: covers, onDetailVisibilityChange: onArchiveVisibilityChange)
                } label: { FootprintGeoMap(items: items) }
                .buttonStyle(.plain)
            }
        }
            }
        }
    }

    var venueSection: some View {
        let items = archive.venueArchiveItems
        return Group {
            if items.isEmpty {
                EmptyView()
            } else {
        dashboardSection(title: BSLocalization.text("场馆足迹"), action: isForExport || items.isEmpty ? nil : BSLocalization.text("查看全部 →"), actionDestination: items.isEmpty ? nil : AnyView(FootprintVenueArchiveView(archive: archive, covers: covers, onDetailVisibilityChange: onArchiveVisibilityChange)), contentPadding: 0) {
            if let first = items.first {
                if isForExport {
                    venueFootprintCard(items: items, first: first)
                } else {
                    NavigationLink {
                        FootprintVenueArchiveView(archive: archive, covers: covers, onDetailVisibilityChange: onArchiveVisibilityChange)
                    } label: { venueFootprintCard(items: items, first: first) }
                    .buttonStyle(.plain)
                }
            }
        }
            }
        }
    }

    private func venueFootprintCard(items: [FootprintVenueArchiveItem], first: FootprintVenueArchiveItem) -> some View {
        let firstShows = archive.shows(for: first.showIDs)
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(BSColor.Stage.accent)
                        Text("\(BSLocalization.text("MOST FAMILIAR")) · #1")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1.4)
                            .foregroundColor(BSColor.Stage.accent)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.3), lineWidth: 1))

                    Text(first.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let city = first.cities.first, !city.isEmpty {
                            Text(city.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1)
                                .foregroundColor(BSColor.Stage.muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        Text(BSLocalization.format("你最常回去的场馆 · %lld 次", first.count))
                            .font(.system(size: 9))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                }

                Spacer(minLength: 0)

                FootprintVenueCoverStack(shows: firstShows, covers: covers, maxCovers: 2, width: 60, height: 80)
                    .padding(.trailing, 4)
            }
            .padding(18)

            if items.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(items.dropFirst().prefix(2).enumerated()), id: \.element.id) { offset, item in
                        let itemShows = archive.shows(for: item.showIDs)
                        HStack(spacing: 8) {
                            Text("\(offset + 2)")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(BSColor.Stage.accent.opacity(0.85))
                                .frame(width: 16, alignment: .leading)

                            if let firstShow = itemShows.first {
                                FootprintCoverView(show: firstShow, cover: covers[firstShow.id], showsMetadata: false)
                                    .frame(width: 26, height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(BSColor.Stage.foreground)
                                    .lineLimit(1)

                               if let city = item.cities.first, !city.isEmpty {
                                   Text(city.uppercased())
                                       .font(.system(size: 8, weight: .medium))
                                       .tracking(0.6)
                                       .foregroundColor(BSColor.Stage.muted)
                               }
                           }

                            Spacer(minLength: 8)

                            Text(BSLocalization.format("%lld 场", item.count))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(BSColor.Stage.accent)
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)

                        if offset == 0 && items.count > 2 {
                            Rectangle()
                                .fill(Color.white.opacity(0.045))
                                .frame(height: 1)
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BSColor.Stage.border))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border))
    }

    var memorySection: some View {
        let memoryShows = archive.shows.filter { covers[$0.id]?.badge == .memory }
        return Group {
            if !memoryShows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BSLocalization.text("最近留下的回忆"))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(BSColor.Stage.foreground)
                        }
                        Spacer()
                        if !isForExport {
                            NavigationLink {
                                FootprintMemoriesArchiveView(
                                    archive: archive,
                                    covers: covers,
                                    onDetailVisibilityChange: onArchiveVisibilityChange
                                )
                            } label: {
                                Text(BSLocalization.text("查看全部 ›"))
                                    .font(.system(size: 10))
                                    .foregroundColor(BSColor.Stage.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    if isForExport {
                        let shown = FootprintExportContentPolicy.prefix(
                            memoryShows,
                            limit: FootprintExportContentPolicy.memoryCardLimit
                        )
                        let rows = stride(from: 0, to: shown.count, by: 2).map { start in
                            Array(shown[start..<min(start + 2, shown.count)])
                        }
                        VStack(spacing: 12) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                                HStack(spacing: 12) {
                                    ForEach(Array(row.enumerated()), id: \.element.id) { column, show in
                                        FootprintMemoryCard(
                                            show: show,
                                            cover: covers[show.id],
                                            index: rowIndex * 2 + column + 1
                                        )
                                        .aspectRatio(138.0 / 184.0, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                    }
                                    if row.count == 1 {
                                        Color.clear
                                            .aspectRatio(138.0 / 184.0, contentMode: .fit)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        footprintExportRemainingCaption(
                            total: memoryShows.count,
                            limit: FootprintExportContentPolicy.memoryCardLimit,
                            style: .memories
                        )
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(memoryShows.prefix(8).enumerated()), id: \.element.id) { index, show in
                                    Button { onShowSelected(show) } label: {
                                        FootprintMemoryCard(show: show, cover: covers[show.id], index: index + 1)
                                            .frame(width: 138, height: 184)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.top, 28)
            }
        }
    }

    var timelineSection: some View {
        let groups = isForExport
            ? FootprintExportContentPolicy.cappedYearGroups(
                archive.years,
                limit: FootprintExportContentPolicy.timelineShowLimit
            )
            : archive.years
        let totalShows = archive.years.reduce(0) { $0 + $1.shows.count }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(BSLocalization.text("现场记录"), nil)
                Spacer()
                if !isForExport {
                    Button(BSLocalization.text("补录历史"), action: onAdd)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.28), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)

            ForEach(groups) { group in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(group.year))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(BSColor.Stage.accent)
                    Text(BSLocalization.format("%lld 场现场", group.shows.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BSColor.Stage.muted)
                    Rectangle()
                        .fill(LinearGradient(colors: [BSColor.Stage.border, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)

               ForEach(group.shows) { show in
                   Button { onShowSelected(show) } label: {
                       HStack(alignment: .top, spacing: 12) {
                           VStack(alignment: .trailing, spacing: 2) {
                               Text(String(footprintEnhancementDayText(show.effectiveDate, calendar: show.timingCalendar()).suffix(2)))
                                   .font(.system(size: 20, weight: .bold))
                                   .foregroundColor(BSColor.Stage.foreground)
                               Text(footprintEnhancementMonthAbbreviation(show.effectiveDate, calendar: show.timingCalendar()))
                                   .font(.system(size: 9, weight: .bold))
                                   .tracking(1)
                                   .foregroundColor(BSColor.Stage.accent)
                           }
                           .frame(width: 48, alignment: .trailing)

                            FootprintTimelineRail()
                                .frame(width: 14)

                            FootprintCoverView(show: show, cover: covers[show.id])
                                .frame(width: 76, height: 86)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    if let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city) {
                                        Text(city.uppercased())
                                            .font(.system(size: 8.5, weight: .bold))
                                            .tracking(0.8)
                                            .foregroundColor(BSColor.Stage.muted)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.06), in: Capsule())
                                    }
                                    Spacer(minLength: 0)
                                }

                                Text(show.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BSColor.Stage.foreground)
                                    .lineLimit(2)

                                if let venue = FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) {
                                    Text(venue)
                                        .font(.system(size: 11))
                                        .foregroundColor(BSColor.Stage.muted)
                                        .lineLimit(1)
                                }

                                HStack(spacing: 6) {
                                    Text(BSLocalization.format("第 %lld 场", ordinal(of: show)))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(BSColor.Stage.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())

                                   if let cover = covers[show.id] {
                                        Text(cover.badge.localizedTitle)
                                           .font(.system(size: 9, weight: .medium))
                                           .foregroundColor(BSColor.Stage.dim)
                                   }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                            .padding(.bottom, 22)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            if isForExport {
                footprintExportRemainingCaption(
                    total: totalShows,
                    limit: FootprintExportContentPolicy.timelineShowLimit
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }

    private func ordinal(of show: Show) -> Int {
        archive.shows.firstIndex(where: { $0.id == show.id }).map { archive.shows.count - $0 } ?? 1
    }

    private func dashboardSection<Content: View>(title: String, subtitle: String? = nil, description: String? = nil, action: String? = nil, actionDestination: AnyView? = nil, contentPadding: CGFloat = 15, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel(title, subtitle)
                    if let description { Text(description).font(.system(size: 10)).foregroundColor(BSColor.Stage.muted).lineSpacing(2) }
                }
                Spacer(minLength: 8)
                if let action {
                    if isForExport {
                        Text(action).font(.system(size: 10)).foregroundColor(BSColor.Stage.accent).lineLimit(1)
                    } else if let actionDestination {
                        NavigationLink { actionDestination } label: {
                            Text(action).font(.system(size: 10)).foregroundColor(BSColor.Stage.accent).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(action).font(.system(size: 10)).foregroundColor(BSColor.Stage.accent).lineLimit(1)
                    }
                }
            }
            content().padding(contentPadding)
                .background(LinearGradient(colors: [Color.white.opacity(0.042), Color.white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border))
                .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
        }
        .padding(.horizontal, 20).padding(.top, 30)
    }

    private func sectionLabel(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 18, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 9)).tracking(1.5).foregroundColor(BSColor.Stage.muted)
            }
        }
    }
}

/// Top-artist card; owns its artwork-resolution state so
/// `FootprintDashboardSections` stays a pure value type.
private struct FootprintArtistAvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                if let cached = ShowCoverDiskCache.application.image(from: url) {
                    Image(uiImage: cached)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            initialFallback
                        }
                    }
                }
            } else {
                initialFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.18), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(6, size * 0.18), style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var initialFallback: some View {
        ZStack {
            LinearGradient(
                colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(BSColor.Stage.accent)
        }
    }
}

@MainActor
private enum FootprintArtistAlbumArtworkLoader {
    static func resolveIfNeeded(
        name: String,
        existingURL: URL?,
        showIDs: [UUID],
        in shows: [Show],
        modelContext: ModelContext
    ) async -> URL? {
        if let existingURL { return existingURL }
        guard let url = await ArtistAlbumArtworkResolver.shared.artworkURL(forArtistName: name) else { return nil }
        if FootprintAlbumArtworkWriteback.persist(url, artistName: name, showIDs: showIDs, in: shows) {
            try? modelContext.save()
        }
        return url
    }
}

private struct FootprintArtistCoverView: View {
    let item: FootprintArtistArchiveItem
    let shows: [Show]
    let size: CGFloat

    @Environment(\.modelContext) private var modelContext
    @State private var resolvedAlbumArtworkURL: URL?

    var body: some View {
        FootprintArtistAvatarView(
            url: item.albumArtworkURL ?? resolvedAlbumArtworkURL ?? item.artworkURL,
            name: item.name,
            size: size
        )
        .task(id: item.id) {
            resolvedAlbumArtworkURL = await FootprintArtistAlbumArtworkLoader.resolveIfNeeded(
                name: item.name,
                existingURL: item.albumArtworkURL,
                showIDs: item.showIDs,
                in: shows,
                modelContext: modelContext
            )
        }
    }
}

private struct FootprintTopArtistCard: View {
    let items: [FootprintArtistArchiveItem]
    let first: FootprintArtistArchiveItem
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let isForExport: Bool
    let onArchiveVisibilityChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            footprintExportAwareNavigationLink(isForExport: isForExport) {
                FootprintFilteredShowsView(
                    title: first.name,
                    shows: archive.shows(for: first.showIDs),
                    archive: archive,
                    covers: covers,
                    onDetailVisibilityChange: onArchiveVisibilityChange
                )
            } label: {
                artistHeroRow(first, showsChevron: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.dropFirst().prefix(2).enumerated()), id: \.element.id) { offset, item in
                    footprintExportAwareNavigationLink(isForExport: isForExport) {
                        FootprintFilteredShowsView(
                            title: item.name,
                            shows: archive.shows(for: item.showIDs),
                            archive: archive,
                            covers: covers,
                            onDetailVisibilityChange: onArchiveVisibilityChange
                        )
                    } label: {
                        artistRankRow(rank: offset + 2, item: item, showsChevron: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1)
                            }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private func artistHeroRow(_ item: FootprintArtistArchiveItem, showsChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .topLeading) {
                FootprintArtistCoverView(item: item, shows: archive.shows, size: 108)
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("#1")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.35), lineWidth: 0.5))
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(BSLocalization.format("%lld 场", item.count))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                if let city = latestCity(for: item) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10, weight: .semibold))
                        Text(BSLocalization.format("最近观看 · %@", city))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Text(BSLocalization.text("最常看").uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(BSColor.Stage.accent)
                if showsChevron {
                    footprintRowChevron(isForExport: isForExport, size: 12, weight: .semibold)
                }
            }
        }
    }

    private func artistRankRow(rank: Int, item: FootprintArtistArchiveItem, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BSColor.Stage.dim)
                .frame(width: 16, alignment: .leading)

            FootprintArtistCoverView(item: item, shows: archive.shows, size: 36)

            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(BSLocalization.format("%lld 场", item.count))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BSColor.Stage.dim)

            if showsChevron {
                footprintRowChevron(isForExport: isForExport, size: 11, weight: .semibold)
            }
        }
    }

    private func latestCity(for item: FootprintArtistArchiveItem) -> String? {
        guard let showID = item.latestShowID else { return nil }
        return archive.shows(for: [showID]).first.flatMap { FootprintTextNormalizer.nonEmptyTrimmed($0.city) }
    }
}

private struct FootprintTrendChart: View {
    let year: Int
    let months: [FootprintMonthActivity]
    let currentMonth: Int?
    let peakMonth: Int?

    var body: some View {
        GeometryReader { proxy in
           let width = proxy.size.width
           let chartHeight = proxy.size.height - 24
           let chartTop: CGFloat = 18
           let chartBottom = chartHeight - 8
           let plotHeight = max(1, chartBottom - chartTop)
           let visibleCount = max(1, min(currentMonth ?? months.count, months.count))
           let visibleMonths = Array(months.prefix(visibleCount))
           let maxCount = max(1, visibleMonths.map(\.showCount).max() ?? 1)
           let chartInset: CGFloat = 12
           let plotWidth = max(1, width - chartInset * 2)
           let points = months.enumerated().map { index, month in
               CGPoint(
                   x: chartInset + plotWidth * CGFloat(index) / CGFloat(max(months.count - 1, 1)),
                   y: chartBottom - plotHeight * CGFloat(month.showCount) / CGFloat(maxCount)
               )
           }
            let visiblePoints = Array(points.prefix(visibleCount))
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(0.075))
                        .frame(width: width, height: 1)
                        .position(x: width / 2, y: chartTop + CGFloat(index) * plotHeight / 2)
                }
                if let currentMonth, currentMonth >= 1, currentMonth <= months.count {
                    Path { path in
                        let point = points[currentMonth - 1]
                        path.move(to: CGPoint(x: point.x, y: chartTop))
                        path.addLine(to: CGPoint(x: point.x, y: chartBottom))
                    }
                    .stroke(BSColor.Stage.accent.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                }
                if let first = visiblePoints.first {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: chartBottom))
                        path.addLine(to: first)
                        addSmoothSegments(to: &path, points: visiblePoints)
                        if let last = visiblePoints.last {
                            path.addLine(to: CGPoint(x: last.x, y: chartBottom))
                            path.closeSubpath()
                        }
                    }
                    .fill(LinearGradient(colors: [BSColor.Stage.accent.opacity(0.40), BSColor.Stage.accent.opacity(0.04)], startPoint: .top, endPoint: .bottom))

                    Path { path in
                        path.move(to: first)
                        addSmoothSegments(to: &path, points: visiblePoints)
                    }
                    .stroke(BSColor.Stage.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
               ForEach(Array(visiblePoints.enumerated()), id: \.offset) { index, point in
                   let month = months[index]
                   let isPeak = peakMonth == month.month
                   let isCurrent = currentMonth == month.month
                   Circle()
                       .fill(isCurrent ? BSColor.Stage.accent : BSColor.Stage.background)
                       .frame(width: isCurrent ? 10 : (isPeak ? 8 : 7), height: isCurrent ? 10 : (isPeak ? 8 : 7))
                       .overlay(Circle().stroke(BSColor.Stage.accent, lineWidth: isCurrent ? 3 : 2))
                       .shadow(color: BSColor.Stage.accent.opacity(isCurrent || isPeak ? 0.36 : 0.12), radius: isCurrent || isPeak ? 6 : 3)
                       .position(point)
               }
               ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                   Text(BSLocalization.text(footprintMonthKey(month.month)))
                       .font(.system(size: 8.5, weight: month.month == currentMonth ? .bold : .medium))
                       .foregroundColor(
                           month.month == currentMonth
                               ? BSColor.Stage.accent
                               : (currentMonth.map { month.month > $0 } ?? false ? BSColor.Stage.dim.opacity(0.68) : BSColor.Stage.foreground.opacity(0.65))
                       )
                       .position(x: points[index].x, y: proxy.size.height - 7)
               }
           }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BSLocalization.format("%lld 年 1 月到 12 月现场轨迹", year))
            .accessibilityValue(
                peakMonth
                    .flatMap { month in months.first(where: { $0.month == month }).map { BSLocalization.format("最高点 %lld 月，%lld 场", $0.month, $0.showCount) } }
                    ?? BSLocalization.text("暂无现场记录")
            )
        }
    }

    private func addSmoothSegments(to path: inout Path, points: [CGPoint]) {
        guard points.count > 1 else { return }
        for (start, end) in zip(points, points.dropFirst()) {
            let midpoint = (start.x + end.x) / 2
            path.addCurve(
                to: end,
                control1: CGPoint(x: midpoint, y: start.y),
                control2: CGPoint(x: midpoint, y: end.y)
            )
        }
    }
}

private struct FootprintMapStar {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let opacity: Double
    let color: Color
}

private struct FootprintGeoMap: View {
    let items: [FootprintCityArchiveItem]
    var height: CGFloat = 230
    var showsControls = true
    var onSelect: ((FootprintCityArchiveItem) -> Void)? = nil
    @State private var resolvedCoordinates: [String: FootprintCityCoordinate]
    @State private var mapScale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1

    init(
        items: [FootprintCityArchiveItem],
        height: CGFloat = 230,
        showsControls: Bool = true,
        onSelect: ((FootprintCityArchiveItem) -> Void)? = nil
    ) {
        self.items = items
        self.height = height
        self.showsControls = showsControls
        self.onSelect = onSelect
        _resolvedCoordinates = State(
            initialValue: FootprintCityCoordinateResolver.shared.cachedCoordinates(for: items.map(\.name))
        )
    }

    private let fallbackPositions: [CGPoint] = [CGPoint(x: 0.72, y: 0.44), CGPoint(x: 0.58, y: 0.63), CGPoint(x: 0.44, y: 0.48), CGPoint(x: 0.82, y: 0.70), CGPoint(x: 0.28, y: 0.36), CGPoint(x: 0.64, y: 0.28), CGPoint(x: 0.16, y: 0.66), CGPoint(x: 0.38, y: 0.76)]
    private let starField: [FootprintMapStar] = [
        FootprintMapStar(x: 0.08, y: 0.14, radius: 1.1, opacity: 0.72, color: .white),
        FootprintMapStar(x: 0.19, y: 0.27, radius: 0.7, opacity: 0.46, color: .cyan),
        FootprintMapStar(x: 0.33, y: 0.11, radius: 0.8, opacity: 0.58, color: .white),
        FootprintMapStar(x: 0.47, y: 0.22, radius: 0.55, opacity: 0.36, color: .white),
        FootprintMapStar(x: 0.64, y: 0.12, radius: 1.0, opacity: 0.62, color: .white),
        FootprintMapStar(x: 0.83, y: 0.18, radius: 0.65, opacity: 0.44, color: .cyan),
        FootprintMapStar(x: 0.93, y: 0.34, radius: 0.9, opacity: 0.56, color: .white),
        FootprintMapStar(x: 0.12, y: 0.48, radius: 0.55, opacity: 0.38, color: .white),
        FootprintMapStar(x: 0.28, y: 0.57, radius: 0.85, opacity: 0.48, color: .cyan),
        FootprintMapStar(x: 0.43, y: 0.42, radius: 0.65, opacity: 0.42, color: .white),
        FootprintMapStar(x: 0.57, y: 0.52, radius: 0.55, opacity: 0.36, color: .white),
        FootprintMapStar(x: 0.77, y: 0.47, radius: 1.05, opacity: 0.64, color: .white),
        FootprintMapStar(x: 0.89, y: 0.63, radius: 0.65, opacity: 0.42, color: .cyan),
        FootprintMapStar(x: 0.08, y: 0.82, radius: 0.8, opacity: 0.48, color: .white),
        FootprintMapStar(x: 0.23, y: 0.72, radius: 0.55, opacity: 0.34, color: .white),
        FootprintMapStar(x: 0.39, y: 0.88, radius: 0.95, opacity: 0.52, color: .cyan),
        FootprintMapStar(x: 0.68, y: 0.78, radius: 0.7, opacity: 0.4, color: .white),
        FootprintMapStar(x: 0.9, y: 0.86, radius: 1.0, opacity: 0.58, color: .white)
    ]

    var body: some View {
        GeometryReader { proxy in
            let visibleItems = Array(items.prefix(fallbackPositions.count))
            let projected = FootprintCoordinateProjector.project(Array(resolvedCoordinates.values))
            ZStack {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.045, blue: 0.08),
                            Color(red: 0.08, green: 0.065, blue: 0.09),
                            Color(red: 0.02, green: 0.025, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // 淡黄色暖金舞台光晕渐变
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.88, blue: 0.65).opacity(0.22),
                            BSColor.Stage.accent.opacity(0.10),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.45, y: 0.35),
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.75
                    )
                    LinearGradient(
                        colors: [
                            BSColor.Stage.accent.opacity(0.12),
                            Color.clear,
                            Color(red: 0.96, green: 0.86, blue: 0.62).opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [BSColor.Stage.glowBlue.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.82, y: 0.2),
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.68
                    )
                    RadialGradient(
                        colors: [Color.purple.opacity(0.10), .clear],
                        center: .bottomLeading,
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.65
                    )
                    Canvas { context, size in
                        for star in starField {
                            let center = CGPoint(x: size.width * star.x, y: size.height * star.y)
                            let glowRadius = star.radius * 3.5
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: center.x - glowRadius,
                                    y: center.y - glowRadius,
                                    width: glowRadius * 2,
                                    height: glowRadius * 2
                                )),
                                with: .color(star.color.opacity(star.opacity * 0.08))
                            )
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: center.x - star.radius,
                                    y: center.y - star.radius,
                                    width: star.radius * 2,
                                    height: star.radius * 2
                                )),
                                with: .color(star.color.opacity(star.opacity))
                            )
                        }
                    }
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        let point = point(for: item, index: index, size: proxy.size, projected: projected)
                        if let onSelect {
                            Button { onSelect(item) } label: {
                                cityPin(item, isPrimary: index == 0)
                            }
                            .buttonStyle(.plain)
                            .position(point)
                        } else {
                            cityPin(item, isPrimary: index == 0)
                                .position(point)
                        }
                    }
                }
                .scaleEffect(mapScale * pinchScale)
                .simultaneousGesture(pinchZoomGesture)
                if showsControls { mapControls }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.accent.opacity(0.22), lineWidth: 1))
        .task(id: items.map(\.name)) {
            resolvedCoordinates = await FootprintCityCoordinateResolver.shared.coordinates(for: items.map(\.name))
        }
    }

    private var mapControls: some View {
        VStack(spacing: 7) {
            mapControlButton("plus", label: BSLocalization.text("放大地图")) {
                mapScale = min(mapScale + 0.18, FootprintMapZoom.maximum)
            }
            mapControlButton("minus", label: BSLocalization.text("缩小地图")) {
                mapScale = max(mapScale - 0.18, FootprintMapZoom.minimum)
            }
            mapControlButton("scope", label: BSLocalization.text("重置地图")) {
                mapScale = FootprintMapZoom.minimum
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 12)
        .padding(.trailing, 12)
    }

    private func mapControlButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BSColor.Stage.dim)
                .frame(width: 30, height: 30)
                .background(BSColor.Stage.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(BSColor.Stage.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                mapScale = FootprintMapZoom.settledScale(current: mapScale, gesture: value)
            }
    }

    private func point(
        for item: FootprintCityArchiveItem,
        index: Int,
        size: CGSize,
        projected: [String: FootprintProjectedCoordinate]
    ) -> CGPoint {
        let normalized = projected[item.name]
            .map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            ?? fallbackPositions[index % fallbackPositions.count]
        return CGPoint(x: size.width * normalized.x, y: size.height * normalized.y)
    }

    private func cityPin(_ item: FootprintCityArchiveItem, isPrimary: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isPrimary ? BSColor.Stage.accent : BSColor.Stage.accent.opacity(0.70))
                .frame(width: isPrimary ? 18 : 11, height: isPrimary ? 18 : 11)
                .overlay(Circle().stroke(BSColor.Stage.background, lineWidth: 2))
                .shadow(color: BSColor.Stage.accent.opacity(isPrimary ? 0.34 : 0.14), radius: isPrimary ? 11 : 5)
            Text(item.name)
                .font(.system(size: isPrimary ? 8 : 7))
                .foregroundColor(isPrimary ? BSColor.Stage.accent : BSColor.Stage.dim)
            Text(BSLocalization.format("%lld 场", item.count))
                .font(.system(size: 7))
                .foregroundColor(BSColor.Stage.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.format("%@，%lld 场", item.name, item.count))
    }
}

private struct FootprintTimelineRail: View {
    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(BSColor.Stage.accent)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(BSColor.Stage.background, lineWidth: 2.5))
                .shadow(color: BSColor.Stage.accent.opacity(0.45), radius: 4)
            Rectangle()
                .fill(LinearGradient(
                    colors: [BSColor.Stage.accent.opacity(0.35), Color.white.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
        }
    }
}

struct FootprintCoverView: View {
    let show: Show
    let cover: FootprintCover?
    var showsMetadata = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            coverContent
            LinearGradient(colors: [.clear, .black.opacity(0.66)], startPoint: .center, endPoint: .bottom)
           if showsMetadata, let cover, cover.source != .archive {
               VStack(alignment: .leading, spacing: 3) {
                    Text(cover.badge.localizedTitle).font(.system(size: 8.5, weight: .bold)).tracking(0.8).foregroundColor(.white.opacity(0.78))
                   if let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city) {
                        Text(city.uppercased()).font(.system(size: 8.5, weight: .medium)).tracking(0.6).foregroundColor(.white.opacity(0.82)).lineLimit(1)
                    }
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.10)))
    }

    @ViewBuilder
    private var coverContent: some View {
        FootprintResolvedCoverImage(show: show, cover: cover)
    }
}

/// Shared footprint-cover rendering: `.local`/`.remote`/`.archive` all funnel
/// through here, and any load failure or empty source falls back to
/// `FootprintTypographyCover` — the single fallback inside the archive.
struct FootprintResolvedCoverImage: View {
    let show: Show
    let cover: FootprintCover?

    private var resolvedCover: FootprintCover {
        cover ?? FootprintCover(
            showID: show.id,
            source: .archive,
            badge: .archive,
            ordinal: 1,
            variant: FootprintArchiveCoverLayout.variant(for: show.id)
        )
    }

    var body: some View {
        switch resolvedCover.source {
        case let .local(url):
            FootprintCoverLocalImage(url: url) {
                FootprintTypographyCover(show: show, cover: resolvedCover)
            }
        case let .remote(url):
            FootprintCoverRemoteImage(url: url) {
                FootprintTypographyCover(show: show, cover: resolvedCover)
            }
        case .archive:
            FootprintTypographyCover(show: show, cover: resolvedCover)
        }
    }
}

private struct FootprintCoverLocalImage<Fallback: View>: View {
    let url: URL
    @ViewBuilder let fallback: Fallback
    @State private var image: UIImage?

    init(url: URL, @ViewBuilder fallback: () -> Fallback) {
        self.url = url
        self.fallback = fallback()
        _image = State(initialValue: UIImage(contentsOfFile: url.path))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            guard image == nil else { return }
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
        }
    }
}

private struct FootprintCoverRemoteImage<Fallback: View>: View {
    let url: URL
    @ViewBuilder let fallback: Fallback
    @State private var image: UIImage?

    init(url: URL, @ViewBuilder fallback: () -> Fallback) {
        self.url = url
        self.fallback = fallback()
        _image = State(initialValue: ShowCoverDiskCache.application.image(from: url))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            guard image == nil else { return }
            image = await ShowCoverImageCache.shared.image(from: url)
        }
    }
}

struct FootprintTypographyCover: View {
    let show: Show
    let cover: FootprintCover

    var body: some View {
        let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city)?.uppercased() ?? "LIVE"
        let date = footprintEnhancementFullDateText(show.effectiveDate, calendar: show.timingCalendar())
        GeometryReader { proxy in
            let compact = proxy.size.width < 74
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: palette,
                    startPoint: cover.variant.isMultiple(of: 2) ? .topLeading : .bottomTrailing,
                    endPoint: cover.variant.isMultiple(of: 2) ? .bottomTrailing : .topLeading
                )
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: proxy.size.width * 1.1, height: proxy.size.width * 1.1)
                    .blur(radius: compact ? 12 : 20)
                    .offset(x: CGFloat(cover.variant % 3) * proxy.size.width * 0.12, y: cover.variant.isMultiple(of: 2) ? -proxy.size.height * 0.18 : proxy.size.height * 0.22)
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: 1)
                    .padding(.top, proxy.size.height * (cover.variant == 1 ? 0.38 : 0.55))
                VStack(alignment: .leading, spacing: 0) {
                    Text("BEFORESHOW")
                        .font(.system(size: compact ? 5.5 : 8, weight: .bold))
                        .tracking(compact ? 0.7 : 1.2)
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 2)
                    Text(city)
                        .font(.system(size: compact ? 8 : 13, weight: .semibold))
                        .tracking(compact ? 0.5 : 1.1)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text(String(format: "%03d", cover.ordinal))
                        .font(.system(size: compact ? 22 : 34, weight: .ultraLight, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !compact {
                        Text(date)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
                .padding(compact ? 7 : 11)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var palette: [Color] {
        switch cover.variant {
        case 0: return [BSColor.Stage.surfaceRaised, BSColor.Stage.glowBlue.opacity(0.82)]
        case 1: return [BSColor.Stage.prepare.opacity(0.92), BSColor.Stage.surface]
        case 2: return [BSColor.Stage.accent.opacity(0.72), BSColor.Stage.surfaceRaised]
        default: return [Color(red: 0.18, green: 0.22, blue: 0.34), Color(red: 0.44, green: 0.28, blue: 0.46)]
        }
    }
}

struct FootprintYearArchiveView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void

    @State private var selectedYear: Int

    init(
        archive: FootprintArchiveSnapshot,
        covers: [UUID: FootprintCover],
        onDetailVisibilityChange: @escaping (Bool) -> Void
    ) {
        self.archive = archive
        self.covers = covers
        self.onDetailVisibilityChange = onDetailVisibilityChange
        _selectedYear = State(initialValue: archive.years.first?.year ?? Calendar.current.component(.year, from: Date()))
    }

    private var selectedGroup: FootprintYearGroup? {
        archive.years.first(where: { $0.year == selectedYear })
    }

    private var selectedActivity: FootprintYearActivity? {
        archive.yearActivity(for: selectedYear)
    }

    private var selectedSummary: FootprintYearArchiveSummary? {
        archive.yearArchiveSummary(for: selectedYear)
    }

    var body: some View {
        FootprintArchivePage(title: BSLocalization.text("年度档案"), kicker: "", shareCovers: covers) { isForExport in
            if let summary = selectedSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.year)")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundColor(BSColor.Stage.foreground)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(BSLocalization.format("%lld 场现场", summary.showCount))
                        Text("·")
                            .foregroundColor(BSColor.Stage.dim)
                        Text(ShowDurationFormatter.aggregate(totalMinutes: summary.durationMinutes))
                    }
                    .font(.system(size: 13))
                        .foregroundColor(BSColor.Stage.muted)
                }

                yearPicker(isForExport: isForExport)

                if let activity = selectedActivity {
                    yearRhythmCard(activity)
                }

                if let highlight = highlightShow {
                    yearHighlight(highlight, isForExport: isForExport)
                }

                archiveSectionTitle(BSLocalization.text("全部现场"), BSLocalization.format("%lld 场", summary.showCount))
                let yearShows = selectedGroup?.shows ?? []
                let visibleYearShows = isForExport
                    ? FootprintExportContentPolicy.prefix(yearShows, limit: FootprintExportContentPolicy.yearShowLimit)
                    : yearShows
                ForEach(visibleYearShows) { show in
                    yearShowRow(show, isForExport: isForExport)
                }
                if isForExport {
                    footprintExportRemainingCaption(
                        total: yearShows.count,
                        limit: FootprintExportContentPolicy.yearShowLimit
                    )
                }
            } else {
                Text(BSLocalization.text("暂无本地数据"))
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.vertical, 30)
            }
        }
    }

    /// isForExport: 导出的静态长图里年份切换没有意义(大标题已含年份),直接省略;
    /// 且 ImageRenderer 快照里横向 ScrollView 会渲染成空白。
    @ViewBuilder
    private func yearPicker(isForExport: Bool) -> some View {
        if !isForExport {
            let pills = HStack(spacing: 8) {
                ForEach(archive.years.map(\.year), id: \.self) { year in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedYear = year
                        }
                    } label: {
                        Text(String(year))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(year == selectedYear ? BSColor.Stage.background : BSColor.Stage.dim)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(year == selectedYear ? BSColor.Stage.accent : Color.white.opacity(0.045), in: Capsule())
                            .overlay(Capsule().stroke(year == selectedYear ? BSColor.Stage.accent : BSColor.Stage.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(year == selectedYear ? .isSelected : [])
                }
            }
            ScrollView(.horizontal, showsIndicators: false) { pills }
        }
    }

    private func yearRhythmCard(_ activity: FootprintYearActivity) -> some View {
        let maxCount = max(1, activity.months.map(\.showCount).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(BSLocalization.format("%@ · %@", BSLocalization.text("年度节拍"), String(activity.year)))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(yearPeakText(activity))
                .font(.system(size: 9))
                .foregroundColor(BSColor.Stage.muted)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(activity.months) { month in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(month.showCount == maxCount && month.showCount > 0 ? BSColor.Stage.accent : BSColor.Stage.accent.opacity(0.46))
                            .frame(height: max(4, CGFloat(month.showCount) / CGFloat(maxCount) * 82))
                       Text(monthLabel(month.month))
                           .font(.system(size: 8.5, weight: .medium))
                           .foregroundColor(BSColor.Stage.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 104, alignment: .bottom)
        }
        .padding(16)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BSColor.Stage.border))
    }

    private func yearHighlight(_ show: Show, isForExport: Bool) -> some View {
        footprintExportAwareNavigationLink(isForExport: isForExport) {
            FootprintDetailView(show: show, archive: archive, onDetailVisibilityChange: onDetailVisibilityChange)
        } label: {
            HStack(spacing: 12) {
                FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                    .frame(width: 82, height: 94)
                    .clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(BSLocalization.text("THE NIGHT OF THE YEAR"))
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.25)
                        .foregroundColor(BSColor.Stage.accent)
                    Text(show.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text([footprintEnhancementFullDateText(show.effectiveDate, calendar: show.timingCalendar()), FootprintTextNormalizer.nonEmptyTrimmed(show.city)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundColor(BSColor.Stage.muted)
                    Text(BSLocalization.text("记录最完整的一晚"))
                        .font(.system(size: 8))
                        .foregroundColor(BSColor.Stage.dim)
                }
                Spacer(minLength: 0)
                footprintRowChevron(isForExport: isForExport, size: 10)
            }
            .padding(12)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BSColor.Stage.border))
        }
    }

    private func yearShowRow(_ show: Show, isForExport: Bool) -> some View {
        footprintExportAwareNavigationLink(isForExport: isForExport) {
            FootprintDetailView(show: show, archive: archive, onDetailVisibilityChange: onDetailVisibilityChange)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(footprintEnhancementDayText(show.effectiveDate, calendar: show.timingCalendar()).suffix(2)))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(footprintEnhancementMonthAbbreviation(show.effectiveDate, calendar: show.timingCalendar()))
                        .font(.system(size: 8))
                        .foregroundColor(BSColor.Stage.muted)
                }
                .frame(width: 38)
                FootprintCoverView(show: show, cover: covers[show.id])
                    .frame(width: 76, height: 86)
                    .clipped()
                VStack(alignment: .leading, spacing: 5) {
                    Text(show.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text([show.city, show.venueName].compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0) }.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundColor(BSColor.Stage.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                footprintRowChevron(isForExport: isForExport, size: 9)
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1) }
        }
    }

    private var highlightShow: Show? {
        archive.yearHighlightShow(for: selectedYear, covers: covers)
    }

    private func yearPeakText(_ activity: FootprintYearActivity) -> String {
        footprintYearPeakText(activity)
    }

    private func monthLabel(_ month: Int) -> String {
        guard Calendar.current.shortMonthSymbols.indices.contains(month - 1) else { return "—" }
        return Calendar.current.shortMonthSymbols[month - 1].uppercased()
    }
}

struct FootprintArtistArchiveView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = archive.artistArchiveItems
        FootprintArchivePage(
            title: BSLocalization.text("艺人足迹"),
            kicker: "",
            shareCovers: covers,
            extraWarmup: {
                await FootprintCoverExportWarmup.warm(artists: items)
            }
        ) { isForExport in
            artistSummaryCard(items: items)

            HStack(spacing: 6) {
                Text(BSLocalization.text("同场次按最近观看排序"))
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BSColor.Stage.dim)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                footprintExportAwareNavigationLink(isForExport: isForExport) {
                    FootprintFilteredShowsView(
                        title: item.name,
                        shows: archive.shows(for: item.showIDs),
                        archive: archive,
                        covers: covers,
                        onDetailVisibilityChange: onDetailVisibilityChange
                    )
                } label: {
                    artistArchiveRow(rank: index + 1, item: item, isForExport: isForExport)
                }
            }
        }
    }

    private func artistSummaryCard(items: [FootprintArtistArchiveItem]) -> some View {
        HStack(spacing: 0) {
            summaryMetric("\(items.count)", BSLocalization.text("位艺人"))
            summaryDivider
            summaryMetric("\(archive.shows.count)", BSLocalization.text("场现场"))
            summaryDivider
            VStack(spacing: 4) {
                Text(BSLocalization.text("最常看"))
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                Text(items.first?.name ?? "—")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border))
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 36)
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private func artistArchiveRow(rank: Int, item: FootprintArtistArchiveItem, isForExport: Bool) -> some View {
        HStack(spacing: 12) {
            rankBadge(rank)

            FootprintArtistCoverView(item: item, shows: archive.shows, size: rank == 1 ? 64 : 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: rank == 1 ? 17 : 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                if rank == 1 {
                    Text("\(BSLocalization.text("最常看")) · #1")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.28), lineWidth: 0.5))
                }
                if let city = latestCity(for: item) {
                    Text(BSLocalization.format("最近观看 · %@", city))
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(BSLocalization.format("%lld 场", item.count))
                .font(.system(size: 13, weight: rank == 1 ? .semibold : .medium))
                .foregroundColor(rank == 1 ? BSColor.Stage.accent : BSColor.Stage.dim)

            footprintRowChevron(isForExport: isForExport, size: 11, weight: .semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, rank == 1 ? 16 : 13)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(rank == 1 ? BSColor.Stage.accent.opacity(0.28) : BSColor.Stage.border, lineWidth: 1)
        )
    }

    private func rankBadge(_ rank: Int) -> some View {
        ZStack {
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(BSColor.Stage.accent)
                    .offset(y: -16)
            }
            Text("\(rank)")
                .font(.system(size: rank == 1 ? 22 : 18, weight: .semibold))
                .foregroundColor(rank == 1 ? BSColor.Stage.accent : BSColor.Stage.dim)
        }
        .frame(width: 28, height: rank == 1 ? 44 : 28)
    }

    private func latestCity(for item: FootprintArtistArchiveItem) -> String? {
        guard let showID = item.latestShowID else { return nil }
        return archive.shows(for: [showID]).first.flatMap { FootprintTextNormalizer.nonEmptyTrimmed($0.city) }
    }
}

struct FootprintCityArchiveView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void
    @State private var selectedCity: FootprintCityArchiveItem?

    var body: some View {
        FootprintArchivePage(
            title: BSLocalization.text("城市档案"),
            kicker: "",
            shareCovers: covers,
            extraWarmup: {
                _ = await FootprintCityCoordinateResolver.shared.coordinates(
                    for: archive.cityArchiveItems.map(\.name)
                )
            }
        ) { isForExport in
            if isForExport {
                FootprintGeoMap(items: archive.cityArchiveItems, height: 360, showsControls: false)
            } else {
                FootprintGeoMap(items: archive.cityArchiveItems, height: 360) { item in
                    selectedCity = item
                }
            }
            archiveSectionTitle(BSLocalization.text("去过的城市"), BSLocalization.format("%lld 座城市", archive.cityArchiveItems.count))
            ForEach(archive.cityArchiveItems) { item in
                footprintExportAwareButton(isForExport: isForExport) {
                    selectedCity = item
                } label: {
                    cityRow(item, isForExport: isForExport)
                }
            }
        }
        .navigationDestination(item: $selectedCity) { item in
            FootprintCityDetailView(
                item: item,
                shows: Array(archive.shows(for: item.showIDs).reversed()),
                archive: archive,
                covers: covers,
                onDetailVisibilityChange: onDetailVisibilityChange
            )
        }
    }

    private func cityRow(_ item: FootprintCityArchiveItem, isForExport: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(BSFont.headline).foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.format("%lld 场 · %@", item.count, yearSpanText(item.yearSpan))).font(BSFont.V3.caption).foregroundColor(BSColor.Stage.muted)
            }
            Spacer()
            footprintRowChevron(isForExport: isForExport)
        }
        .padding(13)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
    }

    private func yearSpanText(_ span: FootprintYearSpan) -> String {
        span.isSingleYear ? String(span.first) : BSLocalization.format("%lld–%lld", span.first, span.latest)
    }
}

struct FootprintCityDetailView: View {
    let item: FootprintCityArchiveItem
    let shows: [Show]
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void

    var body: some View {
        FootprintArchivePage(title: BSLocalization.format("%@现场", item.name), kicker: "", shareCovers: covers) { isForExport in
            cityHero
            archiveSectionTitle(BSLocalization.text("这座城市里的现场"), BSLocalization.format("%lld 场 · 按时间倒序", item.count))
            let visibleShows = isForExport
                ? FootprintExportContentPolicy.prefix(shows, limit: FootprintExportContentPolicy.yearShowLimit)
                : shows
            ForEach(visibleShows) { show in
                footprintExportAwareNavigationLink(isForExport: isForExport) {
                    FootprintDetailView(show: show, archive: archive, onDetailVisibilityChange: onDetailVisibilityChange)
                } label: {
                    HStack(spacing: 11) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(footprintEnhancementDayText(show.effectiveDate, calendar: show.timingCalendar()).suffix(2)))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(BSColor.Stage.foreground)
                            Text(footprintEnhancementMonthAbbreviation(show.effectiveDate, calendar: show.timingCalendar()))
                                .font(.system(size: 8))
                                .foregroundColor(BSColor.Stage.muted)
                            Text(String(show.timingCalendar().component(.year, from: show.effectiveDate)))
                                .font(.system(size: 8))
                                .foregroundColor(BSColor.Stage.dim)
                        }
                        .frame(width: 42)
                        FootprintCoverView(show: show, cover: covers[show.id])
                            .frame(width: 68, height: 76)
                            .clipped()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(show.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(BSColor.Stage.foreground)
                                .lineLimit(2)
                            Text(FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) ?? item.name)
                                .font(.system(size: 9))
                                .foregroundColor(BSColor.Stage.muted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        footprintRowChevron(isForExport: isForExport, size: 9)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1) }
                }
            }
            if isForExport {
                footprintExportRemainingCaption(
                    total: shows.count,
                    limit: FootprintExportContentPolicy.yearShowLimit
                )
            }
        }
    }

    private var cityHero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.05, blue: 0.12),
                    Color(red: 0.075, green: 0.045, blue: 0.15),
                    BSColor.Stage.surface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [BSColor.Stage.glowBlue.opacity(0.18), .clear], center: .topTrailing, startRadius: 4, endRadius: 180)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(BSLocalization.text("CITY ARCHIVE"))
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(BSColor.Stage.accent)
                        Text(item.name)
                            .font(.system(size: 38, weight: .regular))
                            .foregroundColor(BSColor.Stage.foreground)
                    }
                   Spacer()
                   VStack(alignment: .trailing, spacing: 7) {
                        Text("\(item.count)")
                           .font(.system(size: 44, weight: .ultraLight))
                           .foregroundColor(BSColor.Stage.accent)
                       Text(BSLocalization.text("场现场"))
                            .font(.system(size: 7))
                            .tracking(1)
                            .foregroundColor(BSColor.Stage.muted)
                    }
                }
                Spacer(minLength: 18)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BSLocalization.format("%lld 个场馆", item.venueCount))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(BSColor.Stage.foreground)
                        Text(item.yearSpan.displayText)
                            .font(.system(size: 9))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    Spacer()
                    Text(BSLocalization.text("现场档案"))
                        .font(.system(size: 8, weight: .medium))
                        .tracking(1)
                        .foregroundColor(BSColor.Stage.dim)
                }
            }
            .padding(18)
        }
        .frame(minHeight: 172)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border))
    }
}

struct FootprintVenueArchiveView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void

    private var items: [FootprintVenueArchiveItem] { archive.venueArchiveItems }
    private var mostRecentVenueID: String? {
        items.max(by: { $0.latestShowDate < $1.latestShowDate })?.id
    }

    var body: some View {
        FootprintArchivePage(
            title: BSLocalization.text("场馆足迹"),
            kicker: "",
            shareCovers: covers
        ) { isForExport in
            if let first = items.first {
                footprintExportAwareNavigationLink(isForExport: isForExport) {
                    FootprintFilteredShowsView(
                        title: first.name,
                        shows: archive.shows(for: first.showIDs),
                        archive: archive,
                        covers: covers,
                        onDetailVisibilityChange: onDetailVisibilityChange
                    )
                } label: {
                    venueHeroCard(first)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(BSLocalization.format("全部场馆 · %lld", items.count))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                HStack(spacing: 4) {
                    Text(BSLocalization.text("按最近到访排序"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.dim)
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            ForEach(listedVenues) { item in
                footprintExportAwareNavigationLink(isForExport: isForExport) {
                    FootprintFilteredShowsView(
                        title: item.name,
                        shows: archive.shows(for: item.showIDs),
                        archive: archive,
                        covers: covers,
                        onDetailVisibilityChange: onDetailVisibilityChange
                    )
                } label: {
                    venueArchiveRow(item, isForExport: isForExport)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                Text(BSLocalization.text("仅统计你有观演记录的场馆"))
                    .font(.system(size: 11))
            }
            .foregroundColor(BSColor.Stage.dim)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private var listedVenues: [FootprintVenueArchiveItem] {
        let remaining = Array(items.dropFirst())
        return remaining.sorted {
            if $0.latestShowDate != $1.latestShowDate { return $0.latestShowDate > $1.latestShowDate }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func venueHeroCard(_ item: FootprintVenueArchiveItem) -> some View {
        let shows = archive.shows(for: item.showIDs)
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(BSLocalization.text("MOST FAMILIAR")) · #1")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                }
                .foregroundColor(BSColor.Stage.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.28), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.28), lineWidth: 0.5))

                Text(item.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(2)

                if let city = item.cities.first, !city.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11, weight: .semibold))
                        Text(city)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.dim)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(item.count)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(BSColor.Stage.accent)
                    Text(BSLocalization.text("场现场"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BSColor.Stage.muted)
                }

                Text(BSLocalization.format("占全部现场的 %lld%%", percentage(item.count)))
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                    Text(BSLocalization.format("最近到访 %@", latestVisitText(for: item)))
                }
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.dim)
            }

            Spacer(minLength: 0)

            FootprintVenueCoverStack(shows: shows.reversed(), covers: covers, maxCovers: 1, width: 108, height: 144)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.07, blue: 0.12),
                    BSColor.Stage.surface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BSColor.Stage.accent.opacity(0.18)))
    }

    private func venueArchiveRow(_ item: FootprintVenueArchiveItem, isForExport: Bool) -> some View {
        let shows = archive.shows(for: item.showIDs)
        return HStack(spacing: 12) {
            if let show = shows.last {
                FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                    .frame(width: 52, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(2)
                Text(venueMetaText(for: item))
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                    .lineLimit(1)
                if item.id == mostRecentVenueID {
                    Text(BSLocalization.text("最近到访"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.28), lineWidth: 0.5))
                }
            }

            Spacer(minLength: 8)

            Text(BSLocalization.format("%lld 场", item.count))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)

            footprintRowChevron(isForExport: isForExport, size: 11, weight: .semibold)
        }
        .padding(14)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BSColor.Stage.border))
    }

    private func venueMetaText(for item: FootprintVenueArchiveItem) -> String {
        let city = item.cities.first.flatMap(FootprintTextNormalizer.nonEmptyTrimmed)
        let date = latestVisitText(for: item)
        if let city {
            return "\(city) · \(date)"
        }
        return date
    }

    private func latestVisitText(for item: FootprintVenueArchiveItem) -> String {
        guard let showID = item.latestShowID,
              let show = archive.shows(for: [showID]).first else {
            return footprintEnhancementMonthText(item.latestShowDate, calendar: Calendar.current)
        }
        return footprintEnhancementMonthText(show.effectiveDate, calendar: show.timingCalendar())
    }

    private func percentage(_ count: Int) -> Int {
        Int((Double(count) / Double(max(archive.shows.count, 1)) * 100).rounded())
    }
}

private struct FootprintMemoryYearGroup: Identifiable {
    let year: Int
    let shows: [Show]
    var id: Int { year }
}

struct FootprintMemoriesArchiveView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void

    private var memoryShows: [Show] {
        archive.shows.filter { covers[$0.id]?.badge == .memory }
    }

    var body: some View {
        FootprintArchivePage(title: BSLocalization.text("全部回忆"), kicker: "", shareCovers: covers) { isForExport in
            if memoryShows.isEmpty {
                emptyState
            } else {
                headerHero
                let visible = isForExport
                    ? FootprintExportContentPolicy.prefix(
                        memoryShows,
                        limit: FootprintExportContentPolicy.memoriesPageLimit
                    )
                    : memoryShows
                let left = Array(visible.enumerated().filter { $0.offset % 2 == 0 })
                let right = Array(visible.enumerated().filter { $0.offset % 2 != 0 })

                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(left, id: \.element.id) { index, show in
                            let isTall = index % 3 == 0
                            footprintExportAwareNavigationLink(isForExport: isForExport) {
                                FootprintDetailView(
                                    show: show,
                                    archive: archive,
                                    onDetailVisibilityChange: onDetailVisibilityChange
                                )
                            } label: {
                                FootprintMemoryCard(
                                    show: show,
                                    cover: covers[show.id],
                                    index: index + 1,
                                    isTall: isTall
                                )
                            }
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(right, id: \.element.id) { index, show in
                            let isTall = index % 3 == 0
                            footprintExportAwareNavigationLink(isForExport: isForExport) {
                                FootprintDetailView(
                                    show: show,
                                    archive: archive,
                                    onDetailVisibilityChange: onDetailVisibilityChange
                                )
                            } label: {
                                FootprintMemoryCard(
                                    show: show,
                                    cover: covers[show.id],
                                    index: index + 1,
                                    isTall: isTall
                                )
                            }
                        }
                    }
                }
                .padding(.top, 12)
                if isForExport {
                    footprintExportRemainingCaption(
                        total: memoryShows.count,
                        limit: FootprintExportContentPolicy.memoriesPageLimit,
                        style: .memories
                    )
                }
            }
        }
    }

    private var headerHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(memoryShows.count))
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("场回忆"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BSColor.Stage.muted)
            }
            Text(BSLocalization.text("照片和视频都留在对应的那一晚里。这里按时间把它们重新铺开。"))
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.muted)
                .lineSpacing(3)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(BSColor.Stage.dim)
            Text(BSLocalization.text("暂无回忆"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("散场后留下照片或视频记忆，在这里筑造你的现场回忆。"))
                .font(.system(size: 12))
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border))
    }
}

struct FootprintFilteredShowsView: View {
    let title: String
    let shows: [Show]
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void

    var body: some View {
        FootprintArchivePage(title: title, kicker: BSLocalization.text("关联现场"), shareCovers: covers) { isForExport in
            archiveSectionTitle(BSLocalization.text("全部现场"), BSLocalization.format("%lld 场", shows.count))
            let visibleShows = isForExport
                ? FootprintExportContentPolicy.prefix(shows, limit: FootprintExportContentPolicy.yearShowLimit)
                : shows
            ForEach(visibleShows) { show in
                footprintExportAwareNavigationLink(isForExport: isForExport) {
                    FootprintDetailView(show: show, archive: archive, onDetailVisibilityChange: onDetailVisibilityChange)
                } label: {
                    HStack(spacing: 11) {
                        FootprintCoverView(show: show, cover: covers[show.id])
                            .frame(width: 76, height: 86)
                            .clipped()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(show.name).font(BSFont.headline).foregroundColor(BSColor.Stage.foreground).lineLimit(2)
                            Text([show.city, show.venueName].compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0) }.joined(separator: " · "))
                                .font(BSFont.V3.caption).foregroundColor(BSColor.Stage.muted).lineLimit(2)
                            Text(footprintEnhancementDayText(show.effectiveDate, calendar: show.timingCalendar())).font(BSFont.V3.caption).foregroundColor(BSColor.Stage.dim)
                        }
                        Spacer(minLength: 0)
                        footprintRowChevron(isForExport: isForExport)
                    }
                    .padding(10)
                    .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
                }
            }
            if isForExport {
                footprintExportRemainingCaption(
                    total: shows.count,
                    limit: FootprintExportContentPolicy.yearShowLimit
                )
            }
        }
    }
}

@ViewBuilder
private func footprintRowChevron(
    isForExport: Bool,
    size: CGFloat = 11,
    weight: Font.Weight = .regular
) -> some View {
    if !isForExport {
        Image(systemName: "chevron.right")
            .font(.system(size: size, weight: weight))
            .foregroundColor(BSColor.Stage.dim)
    }
}

@ViewBuilder
private func footprintExportRemainingCaption(
    total: Int,
    limit: Int,
    style: FootprintExportContentPolicy.RemainingStyle = .shows
) -> some View {
    if let text = FootprintExportContentPolicy.remainingText(total: total, limit: limit, style: style) {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(BSColor.Stage.dim)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}

@ViewBuilder
@MainActor
private func footprintExportAwareNavigationLink<Destination: View, Label: View>(
    isForExport: Bool,
    @ViewBuilder destination: () -> Destination,
    @ViewBuilder label: () -> Label
) -> some View {
    if isForExport {
        label()
    } else {
        NavigationLink(destination: destination, label: label)
            .buttonStyle(.plain)
    }
}

@ViewBuilder
@MainActor
private func footprintExportAwareButton<Label: View>(
    isForExport: Bool,
    action: @escaping () -> Void,
    @ViewBuilder label: () -> Label
) -> some View {
    if isForExport {
        label()
    } else {
        Button(action: action, label: label)
            .buttonStyle(.plain)
    }
}

/// 年度节拍峰值文案:年度档案页与年度分享卡片共用。
func footprintYearPeakText(_ activity: FootprintYearActivity) -> String {
    guard let peak = activity.months.max(by: { $0.showCount < $1.showCount }), peak.showCount > 0 else {
        return BSLocalization.text("这一年还没有现场记录")
    }
    return BSLocalization.format("%lld 月是这一年最密集的一个月", peak.month)
}

struct FootprintNavigationTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(BSColor.Stage.foreground)
            .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

private struct FootprintArchivePage<Content: View>: View {
    let title: String
    let kicker: String
    /// 分享长图导出前用于预热封面缓存的封面表。
    let shareCovers: [UUID: FootprintCover]
    var extraWarmup: (() async -> Void)? = nil
    /// 页面内容。参数 isForExport 为 true 时表示用于整页长图导出:
    /// ImageRenderer 快照里横向 ScrollView 等交互组件会渲染空白,需换静态布局。
    @ViewBuilder let content: (_ isForExport: Bool) -> Content
    @State private var isShowingShare = false
    @State private var toast: BSToastPayload?

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !kicker.isEmpty {
                        Text(kicker).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundColor(BSColor.Stage.accent)
                    }
                    content(false)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, BSLayout.tabBarContentInset)
            }
            .scrollIndicators(.hidden)
            .bsNavigationScrollEdge()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                FootprintNavigationTitle(title: title)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(BSLocalization.text("分享足迹"))
            }
        }
        .sheet(isPresented: $isShowingShare) {
            shareSheet()
        }
        .bsToastOverlay(toast, bottomPadding: 100)
    }

    private func shareSheet() -> some View {
        FootprintPageShareSheet(
            title: title,
            kicker: kicker,
            covers: shareCovers,
            extraWarmup: extraWarmup,
            onSaved: { presentToast(BSLocalization.text("足迹图片已保存")) },
            content: { content(true) }
        )
        .presentationCornerRadius(26)
        .presentationDragIndicator(.visible)
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

private func archiveSectionTitle(_ title: String, _ subtitle: String = "") -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundColor(BSColor.Stage.muted)
        if !subtitle.isEmpty {
            Text(subtitle).font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
        }
    }
    .padding(.top, 4)
}

private func archiveRow(rank: Int, title: String, subtitle: String, count: Int, color: Color) -> some View {
    HStack(spacing: 11) {
        Text("\(rank)").font(rank == 1 ? .system(size: 12, weight: .bold) : BSFont.tag).foregroundColor(rank == 1 ? color : BSColor.Stage.dim).frame(width: 28)
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(rank == 1 ? BSFont.headline : BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(2)
            Text(subtitle).font(BSFont.V3.caption).foregroundColor(BSColor.Stage.muted)
        }
        Spacer()
        Text(BSLocalization.format("%lld 场", count)).font(BSFont.tag).foregroundColor(rank == 1 ? color : BSColor.Stage.foreground)
    }
    .padding(13)
    .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
}

private func footprintEnhancementMonthText(_ date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d.%02d", components.year ?? 0, components.month ?? 0)
}

private func footprintEnhancementDayText(_ date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.month, .day], from: date)
    return String(format: "%02d.%02d", components.month ?? 0, components.day ?? 0)
}

private func footprintEnhancementMonthAbbreviation(_ date: Date, calendar: Calendar) -> String {
    let month = calendar.component(.month, from: date)
    let symbols = calendar.shortMonthSymbols
    guard symbols.indices.contains(month - 1) else { return "LIVE" }
    return symbols[month - 1].uppercased()
}

private func footprintEnhancementFullDateText(_ date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d.%02d.%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
}

private func footprintMonthKey(_ month: Int) -> String {
    "\(month)月"
}

// MARK: - Footprint Venue Visual Components
struct FootprintVenueCoverStack: View {
    let shows: [Show]
    let covers: [UUID: FootprintCover]
    var maxCovers: Int = 2
    var width: CGFloat = 64
    var height: CGFloat = 84

    var body: some View {
        ZStack {
            let stackShows = Array(shows.prefix(maxCovers))
            if stackShows.isEmpty {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Image(systemName: "building.2")
                            .font(.system(size: 16))
                            .foregroundColor(BSColor.Stage.dim)
                    )
                    .frame(width: width, height: height)
            } else {
               ForEach(Array(stackShows.enumerated().reversed()), id: \.element.id) { index, show in
                   let isBack = index > 0
                   FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                       .frame(width: width, height: height)
                       .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                       .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
                       .scaleEffect(isBack ? 0.90 : 1.0)
                       .rotationEffect(.degrees(isBack ? -4 : 0))
                       .offset(x: isBack ? -4 : 0, y: isBack ? -2 : 0)
               }
           }
       }
       .padding(.leading, 4)
   }
}

struct FootprintMemoryCard: View {
    let show: Show
    let cover: FootprintCover?
    var index: Int? = nil
    var isTall: Bool = false

    private var calendar: Calendar { show.timingCalendar() }

    private var memoryTagText: String {
        if let cover, cover.badge == .memory {
            return BSLocalization.text(cover.isVideoMemory ? "视频" : "照片")
        }
        return BSLocalization.text(show.dynamicCover != nil ? "视频" : "照片")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FootprintCoverView(show: show, cover: cover, showsMetadata: false)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.35),
                    .init(color: Color.black.opacity(0.3), location: 0.60),
                    .init(color: Color.black.opacity(0.78), location: 0.84),
                    .init(color: Color.black.opacity(0.94), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.04), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    if let index {
                        Text(String(format: "%02d", index))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.55))
                            .tracking(1)
                    } else {
                        Text(footprintEnhancementFullDateText(show.effectiveDate, calendar: calendar))
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(BSColor.Stage.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.black.opacity(0.48), in: Capsule())
                            .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.32), lineWidth: 0.5))
                    }

                    Spacer(minLength: 0)

                    Text(memoryTagText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(show.name)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .lineSpacing(1.5)
                        .shadow(color: Color.black.opacity(0.8), radius: 4, x: 0, y: 2)

                    Text(footprintEnhancementFullDateText(show.effectiveDate, calendar: calendar))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(11)
        }
        .frame(height: isTall ? 240 : 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}
