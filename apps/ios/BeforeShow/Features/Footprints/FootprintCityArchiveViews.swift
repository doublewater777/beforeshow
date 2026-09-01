import Foundation
import SwiftUI

private struct FootprintMapStar {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let opacity: Double
    let color: Color
}

struct FootprintGeoMap: View {
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
    /// Cap on pins shown on the map (matches `fallbackPositions.count`).
    /// Kept as a named constant so the limit is not buried in a magic number.
    private static let visibleItemsLimit = 8
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
            let visibleItems = Array(items.prefix(Self.visibleItemsLimit))
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
                        if let point = point(for: item, size: proxy.size, projected: projected) {
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
                    pendingDotsStrip(items: visibleItems)
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
        size: CGSize,
        projected: [String: FootprintProjectedCoordinate]
    ) -> CGPoint? {
        guard let projected = projected[item.name] else { return nil }
        return CGPoint(x: size.width * CGFloat(projected.x), y: size.height * CGFloat(projected.y))
    }

    @ViewBuilder
    private func pendingDotsStrip(items: [FootprintCityArchiveItem]) -> some View {
        let pending = items.filter { resolvedCoordinates[$0.name] == nil }
        if !pending.isEmpty {
            HStack(alignment: .center, spacing: 8) {
                ForEach(pending, id: \.id) { item in
                    VStack(spacing: 2) {
                        Circle()
                            .fill(BSColor.Stage.dim.opacity(0.55))
                            .frame(width: 6, height: 6)
                        Text(item.name)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(BSColor.Stage.background.opacity(0.62))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
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
