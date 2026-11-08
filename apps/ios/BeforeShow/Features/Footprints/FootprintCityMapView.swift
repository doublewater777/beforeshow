import MapKit
import SwiftUI

/// Every show pinned where it happened, as its poster. Zoomed out, nearby venues stack;
/// tap a stack to zoom in, tap a venue to see its nights.
struct FootprintCityMapView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let allShows: [Show]

    @State private var cityCoordinates: [String: FootprintCityCoordinate] = [:]
    @State private var venueCoordinates: [String: FootprintCityCoordinate] = [:]
    @State private var isPlaced = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleSpan = 8.0
    /// Venues whose nights the panel lists: one, or a stack that cannot split any further.
    @State private var selectedSpotIDs: [String] = []
    @State private var dropped = 0
    @State private var detailTarget: FootprintDetailDestination?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spots: [FootprintVenueSpot] { FootprintVenueMapPolicy.spots(from: archive.shows) }

    private var stops: [FootprintTourStop] {
        FootprintStagePolicy.tourStops(cities: archive.cityArchiveItems, archive: archive, allShows: allShows)
    }

    /// Shows still to come, one dashed poster per city (its earliest), soonest first.
    private var upcoming: [(city: String, show: Show)] {
        let archived = Set(archive.shows.map(\.id))
        var seen = Set<String>()
        return allShows
            .filter { !archived.contains($0.id) && $0.changeStatus != .canceled && $0.effectiveDate >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.effectiveDate < $1.effectiveDate }
            .compactMap { show in
                guard let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city), seen.insert(city).inserted else { return nil }
                return (city, show)
            }
    }

    /// Upcoming cities not yet on the tour get their own chips after it.
    private var upcomingOnlyCities: [(city: String, show: Show)] {
        let toured = Set(stops.filter { !$0.isNext }.map(\.city))
        return upcoming.filter { !toured.contains($0.city) }
    }

    var body: some View {
        let spots = spots
        let clusters = isPlaced ? FootprintVenueMapPolicy.clusters(placed(spots), cell: visibleSpan / 8) : []
        let dropOrder = clusters.sorted { ($0.spots.map(\.firstDate).min() ?? .distantFuture) < ($1.spots.map(\.firstDate).min() ?? .distantFuture) }.map(\.id)
        let selected = spots.filter { selectedSpotIDs.contains($0.id) }
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            // Night wash over the base map, under the posters.
            MapPolygon(coordinates: FootprintCityMapFraming.nightWash)
                .foregroundStyle(FootprintRoomPalette.mapNight.opacity(0.72))
            ForEach(clusters) { cluster in
                Annotation(cluster.lead.venue ?? cluster.lead.city ?? "", coordinate: CLLocationCoordinate2D(latitude: cluster.latitude, longitude: cluster.longitude), anchor: .bottom) {
                    FootprintPosterPin(
                        show: archive.shows(for: [cluster.lead.showIDs[0]]).first,
                        cover: covers[cluster.lead.showIDs[0]],
                        count: cluster.showCount,
                        isSelected: cluster.spots.contains { selectedSpotIDs.contains($0.id) },
                        isDropped: (dropOrder.firstIndex(of: cluster.id) ?? 0) < dropped
                    )
                    .onTapGesture { tap(cluster) }
                }
                .annotationTitles(.hidden)
            }
            ForEach(Array(upcoming.enumerated()), id: \.element.show.id) { index, item in
                if let coordinate = cityCoordinates[item.city] {
                    Annotation(item.city, coordinate: coordinate.location, anchor: .bottom) {
                        FootprintNextPosterPin(show: item.show, isNext: index == 0)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {}
        .environment(\.colorScheme, .dark)
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleSpan = context.region.span.latitudeDelta
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            panel(selected: selected)
        }
        .overlay(alignment: .top) {
            Text(BSLocalization.format("%lld CITIES · %lld SHOWS", archive.cities.count, archive.shows.count))
                .font(.system(size: 12, weight: .medium).width(.condensed))
                .tracking(3)
                .foregroundStyle(FootprintRoomPalette.bulbGlow.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.top, 8)
                .allowsHitTesting(false)
        }
        .background(FootprintRoomPalette.mapNight.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("走过的城市")) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAll() } label: { Image(systemName: "map") }
                    .accessibilityLabel(BSLocalization.text("显示全部城市"))
            }
        }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.impact(weight: .light), trigger: dropped) { _, new in new > 0 }
        .sensoryFeedback(.selection, trigger: selectedSpotIDs)
        .task {
            // Coming back from a show keeps the map where it was, card and all.
            guard !isPlaced else { return }
            let cityNames = Array(Set(stops.map(\.city) + upcoming.map(\.city)))
            cityCoordinates = await FootprintCityCoordinateResolver.shared.coordinates(for: cityNames)
            venueCoordinates = await FootprintVenueLocator.shared.coordinates(for: spots, cities: cityCoordinates)
            isPlaced = true
            showAll(animated: false)
            await drop(count: FootprintVenueMapPolicy.clusters(placed(spots), cell: visibleSpan / 8).count)
        }
    }

    /// Where each spot goes: its venue, else the middle of its city.
    private func placed(_ spots: [FootprintVenueSpot]) -> [(spot: FootprintVenueSpot, latitude: Double, longitude: Double)] {
        spots.compactMap { spot in
            guard let coordinate = venueCoordinates[spot.id] ?? spot.city.flatMap({ cityCoordinates[$0] }) else { return nil }
            return (spot, coordinate.latitude, coordinate.longitude)
        }
    }

    // MARK: Panel

    @ViewBuilder
    private func panel(selected: [FootprintVenueSpot]) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 36, height: 5).padding(.top, 8)
            if !selected.isEmpty {
                venueCard(selected)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                cityChips
            }
        }
        .padding(.bottom, BSSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.09).opacity(0.96), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: selectedSpotIDs)
    }

    /// Jump between cities without pinching across the country.
    private var cityChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(stops.filter { !$0.isNext }) { stop in
                    cityChip(stop.city, detail: String(stop.count), isUpcoming: false)
                }
                ForEach(Array(upcomingOnlyCities.enumerated()), id: \.element.city) { index, item in
                    cityChip(item.city, detail: index == 0 && upcoming.first?.city == item.city
                        ? BSLocalization.text("下一站") : FootprintUpcomingDate.text(item.show), isUpcoming: true)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 14)
    }

    /// Cities already played sit solid with their count; cities still to come are dashed, with their date.
    private func cityChip(_ city: String, detail: String, isUpcoming: Bool) -> some View {
        Button { fly(toCity: city) } label: {
            HStack(spacing: 6) {
                Text(city).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(isUpcoming ? BSColor.Stage.accent : BSColor.Stage.muted)
            }
            .foregroundStyle(isUpcoming ? BSColor.Stage.accent : BSColor.Stage.foreground)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.white.opacity(isUpcoming ? 0.02 : 0.07), in: Capsule())
            .overlay {
                if isUpcoming {
                    Capsule().strokeBorder(BSColor.Stage.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func venueCard(_ spots: [FootprintVenueSpot]) -> some View {
        let shows = archive.shows(for: spots.flatMap(\.showIDs)).sorted { $0.effectiveDate > $1.effectiveDate }
        let single = spots.count == 1 ? spots.first : nil
        let city = spots.first?.city
        let title = single.map { $0.venue ?? $0.city ?? "" } ?? city ?? ""
        let subtitle = single == nil
            ? BSLocalization.format("%lld 个场馆 · %lld 场", spots.count, shows.count)
            : [city, BSLocalization.format("%lld 场", shows.count)].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(BSColor.Stage.accent)
                }
                Spacer()
                BSRoundIconButton(systemName: "xmark", label: BSLocalization.text("关闭")) { selectedSpotIDs = [] }
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shows) { show in
                        Button { detailTarget = FootprintDetailDestination(show: show) } label: { showCard(show, showsVenue: single == nil) }
                            .buttonStyle(BSPressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.top, 14)
        }
        .padding(.top, 8)
    }

    private func showCard(_ show: Show, showsVenue: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                .frame(width: 96, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(show.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()))
                .font(.system(size: 11, weight: .medium).width(.condensed).monospacedDigit())
                .foregroundStyle(BSColor.Stage.dim)
            if showsVenue, let venue = FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) {
                Text(venue)
                    .font(.system(size: 11))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
        }
        .frame(width: 96, alignment: .leading)
    }

    // MARK: Camera

    private func tap(_ cluster: FootprintMapCluster) {
        let coordinates = cluster.spots.compactMap { spot in placed([spot]).first.map { FootprintCityCoordinate(name: spot.id, latitude: $0.latitude, longitude: $0.longitude) } }
        if cluster.spots.count > 1, FootprintCityMapFraming.canSplit(coordinates, visibleSpan: visibleSpan),
           let region = FootprintCityMapFraming.region(for: coordinates, minimumSpan: 0.04) {
            // A stack opens up: zoom in until its venues stand apart.
            move(to: region)
        } else {
            // One venue, or venues sharing a spot: list their nights.
            selectedSpotIDs = cluster.spots.map(\.id)
            // Street level, with the pin in the open part of the map above the card.
            let span = FootprintCityMapFraming.venueSpan
            move(to: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: cluster.latitude - span * 0.15, longitude: cluster.longitude),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ))
        }
    }

    private func fly(toCity city: String) {
        guard let coordinate = cityCoordinates[city] else { return }
        selectedSpotIDs = []
        move(to: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude - 0.1, longitude: coordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        ))
    }

    private func showAll(animated: Bool = true) {
        selectedSpotIDs = []
        let all = placed(spots).map { FootprintCityCoordinate(name: $0.spot.id, latitude: $0.latitude, longitude: $0.longitude) }
            + upcoming.compactMap { cityCoordinates[$0.city] }
        guard let region = FootprintCityMapFraming.region(for: all) else { return }
        if animated { move(to: region) } else { camera = .region(region); visibleSpan = region.span.latitudeDelta }
    }

    private func move(to region: MKCoordinateRegion) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) {
            camera = .region(region)
        }
    }

    /// Posters land one by one, in the order you first went.
    private func drop(count: Int) async {
        defer { dropped = .max }
        guard !reduceMotion else { return }
        for index in 0..<count {
            try? await Task.sleep(for: .milliseconds(index == 0 ? 400 : max(60, 900 / max(count, 1))))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { dropped = index + 1 }
        }
    }
}

/// Frames a set of places with room left at the bottom for the panel.
enum FootprintCityMapFraming {
    /// How close a tapped venue is shown: a few streets around it.
    static let venueSpan = 0.022
    /// Zooming in only helps while the stack's venues are apart and there is zoom left.
    static func canSplit(_ coordinates: [FootprintCityCoordinate], visibleSpan: Double) -> Bool {
        guard let minLat = coordinates.map(\.latitude).min(), let maxLat = coordinates.map(\.latitude).max(),
              let minLon = coordinates.map(\.longitude).min(), let maxLon = coordinates.map(\.longitude).max() else { return false }
        return max(maxLat - minLat, maxLon - minLon) > 0.002 && visibleSpan > 0.05
    }

    /// Corners spaced under 180° apart so no edge takes the short way across the antimeridian.
    static let nightWash = [-179.0, -60, 60, 179].map { CLLocationCoordinate2D(latitude: 75, longitude: $0) }
        + [179.0, 60, -60, -179].map { CLLocationCoordinate2D(latitude: -60, longitude: $0) }

    static func region(for coordinates: [FootprintCityCoordinate], minimumSpan: Double = 1.5) -> MKCoordinateRegion? {
        guard let minLat = coordinates.map(\.latitude).min(), let maxLat = coordinates.map(\.latitude).max(),
              let minLon = coordinates.map(\.longitude).min(), let maxLon = coordinates.map(\.longitude).max() else { return nil }
        let latSpan = max(minimumSpan, (maxLat - minLat) * 1.5)
        let lonSpan = max(minimumSpan, (maxLon - minLon) * 1.4)
        // Push the places into the upper part of the screen; the panel covers the lower part.
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * 0.2, longitude: (minLon + maxLon) / 2)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan * 1.4, longitudeDelta: lonSpan))
    }
}

/// A poster on a stick. More than one night here: a stack with the count.
private struct FootprintPosterPin: View {
    let show: Show?
    let cover: FootprintCover?
    let count: Int
    let isSelected: Bool
    let isDropped: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if count > 1 {
                        backCard.rotationEffect(.degrees(-8)).offset(x: -4)
                        backCard.rotationEffect(.degrees(6)).offset(x: 4)
                    }
                    Group {
                        if let show {
                            FootprintCoverView(show: show, cover: cover, showsMetadata: false)
                        } else {
                            Color(white: 0.2)
                        }
                    }
                    .frame(width: 52, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(isSelected ? BSColor.Stage.accent : FootprintRoomPalette.neonCore, lineWidth: 2))
                }
                if count > 1 {
                    Text(String(count))
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(FootprintRoomPalette.marqueeInk)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(BSColor.Stage.accent, in: Capsule())
                        .offset(x: 11, y: -11)
                }
            }
            Triangle()
                .fill(isSelected ? BSColor.Stage.accent : FootprintRoomPalette.neonCore)
                .frame(width: 12, height: 7)
        }
        .shadow(color: .black.opacity(0.6), radius: 6, y: 4)
        .scaleEffect(isSelected ? 1.25 : 1, anchor: .bottom)
        .scaleEffect(isDropped ? 1 : 0.1, anchor: .bottom)
        .opacity(isDropped ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle())
    }

    private var backCard: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(white: 0.22))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(FootprintRoomPalette.neonCore.opacity(0.7), lineWidth: 1.5))
            .frame(width: 52, height: 70)
    }
}

/// The next new city: its poster, dimmed, with a dashed frame until you have been.
enum FootprintUpcomingDate {
    static func text(_ show: Show) -> String {
        let parts = show.timingCalendar().dateComponents([.month, .day], from: show.effectiveDate)
        return "\(parts.month ?? 1).\(parts.day ?? 1)"
    }
}

private struct FootprintNextPosterPin: View {
    let show: Show
    let isNext: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(isNext ? BSLocalization.text("NEXT") : FootprintUpcomingDate.text(show))
                .font(.system(size: 9, weight: .bold).width(.condensed))
                .tracking(2)
                .foregroundStyle(BSColor.Stage.accent)
            ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, alignment: .top, enforcesAspectRatio: false, cornerRadius: 4)
                .frame(width: 46, height: 62)
                .opacity(0.55)
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BSColor.Stage.accent, style: StrokeStyle(lineWidth: 1.4, dash: [3, 3])))
                .phaseAnimator([0.55, 1.0]) { pin, opacity in pin.opacity(opacity) } animation: { _ in .easeInOut(duration: 1.2) }
        }
        .allowsHitTesting(false)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private extension FootprintCityCoordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
