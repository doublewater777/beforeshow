import SwiftUI

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
                    Text(BSLocalization.text("场次"))
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
            if $0.count != $1.count { return $0.count > $1.count }
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
