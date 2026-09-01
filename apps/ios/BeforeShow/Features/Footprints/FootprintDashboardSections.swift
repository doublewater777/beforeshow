import Foundation
import SwiftUI

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
                sectionLabel(BSLocalization.text("现场记录"), BSLocalization.text("按年份收纳"))
                Spacer()
                if !isForExport {
                    Button(BSLocalization.text("添加现场"), action: onAdd)
                        .font(BSFont.tag)
                        .foregroundColor(BSColor.Stage.accent)
                        .buttonStyle(.plain)
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
