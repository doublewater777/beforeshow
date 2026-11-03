import SwiftUI

/// Cities printed on the back of a tour shirt, in the order you first played them.
struct FootprintTourShirtView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let allShows: [Show]

    @State private var selectedCity: String?
    @State private var printed = 0
    @State private var coordinates: [String: FootprintCityCoordinate] = [:]
    @State private var cityTarget: FootprintTourStop?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stops = FootprintStagePolicy.tourStops(cities: archive.cityArchiveItems, archive: archive, allShows: allShows)
        let selected = stops.first { $0.city == selectedCity } ?? stops.first
        ScrollView {
            VStack(spacing: 0) {
                title
                    .padding(.top, 20)
                    .printReveal(isPrinted: printed > 0)
                FootprintTourRouteMap(stops: stops, coordinates: coordinates, selected: selected?.city)
                    .frame(height: 230)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .printReveal(isPrinted: printed > 1)
                VStack(spacing: 0) {
                    Rectangle().fill(FootprintRoomPalette.printInk).frame(height: 2)
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        row(stop, isSelected: stop.id == selected?.id)
                            .printReveal(isPrinted: printed > index + 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                Text(BSLocalization.format("CREW OF ONE · %lld ARTISTS · %lld VENUES", archive.artists.count, archive.venues.count))
                    .font(.system(size: 10, weight: .medium).width(.condensed))
                    .tracking(4)
                    .foregroundStyle(FootprintRoomPalette.printInk.opacity(0.5))
                    .padding(.top, 22)
            }
            .bsAdaptiveContentWidth()
            .overlay { FootprintScreenPrintWear().allowsHitTesting(false) }
            .padding(.bottom, BSSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .background { FootprintRoomPalette.cotton.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("走过的城市")) } }
        .navigationDestination(item: $cityTarget) { stop in
            FootprintFilteredShowsView(
                title: stop.city,
                shows: archive.shows.filter { FootprintTextNormalizer.nonEmptyTrimmed($0.city) == stop.city },
                archive: archive,
                covers: covers
            )
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.5), trigger: printed)
        .task {
            coordinates = await FootprintCityCoordinateResolver.shared.coordinates(for: stops.map(\.city))
        }
        .task {
            // Screen-print the shirt one pass at a time.
            let passes = stops.count + 2
            guard !reduceMotion else { printed = passes; return }
            for pass in 1...passes {
                try? await Task.sleep(for: .milliseconds(pass == 1 ? 120 : 140))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.45)) { printed = pass }
            }
        }
    }

    private var title: some View {
        VStack(spacing: 2) {
            Text(BSLocalization.text("BEFORESHOW PRESENTS"))
                .font(.system(size: 11, weight: .medium).width(.condensed))
                .tracking(6)
                .foregroundStyle(FootprintRoomPalette.printInk.opacity(0.7))
            (Text(BSLocalization.text("THE ")) + Text(String(archive.shows.count)).foregroundStyle(BSColor.Stage.accent) + Text(BSLocalization.text(" SHOWS")))
                .font(.system(size: 62, weight: .black).width(.compressed))
                .foregroundStyle(FootprintRoomPalette.printInk)
            Text(BSLocalization.text("TOUR"))
                .font(.system(size: 30, weight: .black).width(.compressed))
                .tracking(10)
                .foregroundStyle(FootprintRoomPalette.printInk)
            if let span = yearSpan {
                Text(BSLocalization.format("%@ · %lld CITIES", span, archive.cities.count))
                    .font(.system(size: 13, weight: .medium).width(.condensed))
                    .tracking(4)
                    .foregroundStyle(FootprintRoomPalette.printInk.opacity(0.75))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var yearSpan: String? {
        guard let latest = archive.years.first?.year, let first = archive.years.last?.year else { return nil }
        return FootprintYearSpan(first: first, latest: latest).displayText
    }

    private func row(_ stop: FootprintTourStop, isSelected: Bool) -> some View {
        let ink = isSelected || stop.isNext ? BSColor.Stage.accent : FootprintRoomPalette.printInk
        return Button {
            guard !stop.isNext else { selectedCity = stop.city; return }
            if isSelected { cityTarget = stop } else { selectedCity = stop.city }
        } label: {
            HStack(spacing: 0) {
                Text(String(format: "%02d.%02d.%02d", stop.firstMonth, stop.firstDay, stop.firstYear % 100))
                    .font(.system(size: 13, weight: .regular).width(.condensed).monospacedDigit())
                    .foregroundStyle(isSelected ? BSColor.Stage.accent : FootprintRoomPalette.printInk.opacity(0.6))
                    .frame(width: 76, alignment: .leading)
                Text(stop.city)
                    .font(.system(size: 21, weight: .black).width(.compressed))
                    .foregroundStyle(stop.isNext ? .clear : ink)
                    .overlay { if stop.isNext { FootprintOutlinedText(text: stop.city, color: ink) } }
                Spacer(minLength: 8)
                Text(stop.isNext ? BSLocalization.text("NEXT") : "×\(stop.count)")
                    .font(.system(size: 15, weight: .medium).width(.condensed))
                    .foregroundStyle(isSelected || stop.isNext ? BSColor.Stage.accent : FootprintRoomPalette.printInk.opacity(0.8))
            }
            .frame(height: 42)
            .overlay(alignment: .bottom) { Rectangle().fill(FootprintRoomPalette.printInk.opacity(0.18)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stop.isNext
            ? BSLocalization.format("下一站 %@", stop.city)
            : BSLocalization.format("%@，%lld 场", stop.city, stop.count))
    }
}

/// The route as a print: lines between first visits, a dashed line to the next new city.
private struct FootprintTourRouteMap: View {
    let stops: [FootprintTourStop]
    let coordinates: [String: FootprintCityCoordinate]
    let selected: String?

    var body: some View {
        let projected = FootprintCoordinateProjector.project(stops.compactMap { coordinates[$0.city] })
        GeometryReader { proxy in
            let size = proxy.size
            let place: (String) -> CGPoint? = { city in
                projected[city].map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            }
            let visited = stops.filter { !$0.isNext }.compactMap { place($0.city) }
            ZStack {
                gridLines(size: size)
                Path { path in
                    guard let first = visited.first else { return }
                    path.move(to: first)
                    visited.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(FootprintRoomPalette.printInk, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                if let next = stops.last(where: \.isNext), let to = place(next.city), let from = visited.last {
                    Path { path in path.move(to: from); path.addLine(to: to) }
                        .stroke(BSColor.Stage.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                }
                ForEach(stops) { stop in
                    if let p = place(stop.city) {
                        let isSelected = stop.city == selected
                        ZStack {
                            if isSelected { Circle().fill(BSColor.Stage.accent.opacity(0.25)).frame(width: 32, height: 32) }
                            Circle()
                                .fill(stop.isNext ? FootprintRoomPalette.cotton : isSelected ? BSColor.Stage.accent : FootprintRoomPalette.printInk)
                                .overlay(Circle().stroke(stop.isNext || isSelected ? BSColor.Stage.accent : FootprintRoomPalette.printInk, lineWidth: 1.4))
                                .frame(width: stop.count >= 10 ? 11 : 7, height: stop.count >= 10 ? 11 : 7)
                        }
                        .position(p)
                        if isSelected {
                            Text(stop.isNext ? BSLocalization.format("下一站 · %@", stop.city) : BSLocalization.format("%@ · %lld 场", stop.city, stop.count))
                                .font(.system(size: 12, weight: .medium).width(.condensed))
                                .foregroundStyle(BSColor.Stage.accent)
                                .fixedSize()
                                .position(x: min(max(p.x, 60), size.width - 60), y: p.y > 30 ? p.y - 16 : p.y + 18)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func gridLines(size: CGSize) -> some View {
        Path { path in
            for i in 1..<4 {
                let y = size.height * CGFloat(i) / 4, x = size.width * CGFloat(i) / 4
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(FootprintRoomPalette.printInk.opacity(0.12), lineWidth: 1)
    }
}

/// Not yet printed: only the outline is on the shirt.
private struct FootprintOutlinedText: View {
    let text: String
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { step in
                let angle = Double(step) / 8 * 2 * .pi
                Text(text).offset(x: cos(angle) * 0.9, y: sin(angle) * 0.9)
            }
            Text(text).foregroundStyle(FootprintRoomPalette.cotton)
        }
        .font(.system(size: 21, weight: .black).width(.compressed))
        .foregroundStyle(color)
    }
}

/// Washed-out specks where the plastisol has worn off.
private struct FootprintScreenPrintWear: View {
    var body: some View {
        Canvas { canvas, size in
            var seed: UInt64 = 3
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt32.max >> 1)
            }
            let specks = Int(size.width * size.height / 90)
            for _ in 0..<specks {
                let r = 0.4 + next() * 0.9
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: r * 2, height: r * 2)
                canvas.fill(Path(ellipseIn: rect), with: .color(FootprintRoomPalette.cotton.opacity(0.55)))
            }
        }
        .accessibilityHidden(true)
    }
}

private extension View {
    /// Screen-print pass: ink wipes on from the leading edge.
    func printReveal(isPrinted: Bool) -> some View {
        mask(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle().frame(width: isPrinted ? proxy.size.width : 0)
            }
        }
    }
}

extension FootprintTourStop: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
