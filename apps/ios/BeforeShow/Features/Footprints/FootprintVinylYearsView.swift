import SwiftUI

/// Years as records: one sleeve per year, its shows are the tracks.
struct FootprintVinylYearsView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    @State private var selectedYear: Int
    @State private var trackIndex = 0
    @State private var armDown = false
    @State private var detailTarget: FootprintDetailDestination?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(archive: FootprintArchiveSnapshot, covers: [UUID: FootprintCover]) {
        self.archive = archive
        self.covers = covers
        _selectedYear = State(initialValue: archive.years.first?.year ?? Calendar.current.component(.year, from: Date()))
    }

    private var tracks: [Show] {
        FootprintArchiveRankingBuilder.chronological(archive.years.first { $0.year == selectedYear }?.shows ?? [])
    }

    var body: some View {
        let tracks = tracks
        let current = tracks.indices.contains(trackIndex) ? tracks[trackIndex] : tracks.first
        ScrollView {
            VStack(spacing: 0) {
                crate
                    .padding(.top, 12)
                turntable(tracks: tracks, current: current)
                    .padding(.top, 26)
                if let current {
                    nowPlaying(current, index: trackIndex, total: tracks.count)
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                }
                trackList(tracks)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }
            .bsAdaptiveContentWidth()
            .padding(.bottom, BSSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .background {
            RadialGradient(colors: [Color(red: 0.102, green: 0.09, blue: 0.078), BSColor.Stage.background], center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("这些年")) } }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.selection, trigger: selectedYear)
        .sensoryFeedback(.selection, trigger: trackIndex)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: armDown) { _, down in down }
        // Fast flicks through the crate only drop the needle once the sleeve settles.
        .task(id: selectedYear) {
            armDown = false
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            armDown = true
        }
    }

    private var crate: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(archive.years) { group in
                    let isSelected = group.year == selectedYear
                    Button {
                        guard !isSelected else { return }
                        selectedYear = group.year
                        trackIndex = 0
                    } label: {
                        VStack(spacing: 7) {
                            sleeve(for: group)
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(isSelected ? BSColor.Stage.accent.opacity(0.6) : Color.white.opacity(0.08)))
                                .opacity(isSelected ? 1 : 0.55)
                                .offset(y: isSelected ? -8 : 0)
                                .shadow(color: .black.opacity(isSelected ? 0.6 : 0), radius: 10, y: 10)
                            Text(String(group.year))
                                .font(.system(size: 13, design: .serif))
                                .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.Stage.dim)
                        }
                        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.format("%lld 年，%lld 场", group.year, group.shows.count))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func sleeve(for group: FootprintYearGroup) -> some View {
        if let show = archive.yearHighlightShow(for: group.year, covers: covers) {
            FootprintResolvedCoverImage(show: show, cover: covers[show.id])
        } else {
            Color(white: 0.11)
        }
    }

    private func turntable(tracks: [Show], current: Show?) -> some View {
        let count = max(tracks.count, 1)
        let progress = count > 1 ? Double(trackIndex) / Double(count - 1) : 0.5
        // Swing from the outer groove (7°) to the inner one (25°); parked off the record when lifted.
        let armAngle = armDown ? 7 + 18 * progress : -6
        return ZStack {
            Circle().fill(Color.black.opacity(0.7)).frame(width: 330, height: 330).blur(radius: 18)
            FootprintSpinningRecord(isSpinning: !reduceMotion) {
                FootprintRecordDisc(diameter: 300, labelDiameter: 108, grooves: min(tracks.count, 24)) {
                    if let current {
                        FootprintResolvedCoverImage(show: current, cover: covers[current.id])
                    }
                }
            }
            .onTapGesture { if let current { detailTarget = FootprintDetailDestination(show: current) } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(current?.name ?? "")
            FootprintRecordSheen().frame(width: 300, height: 300).allowsHitTesting(false)
            FootprintTonearm()
                .frame(width: 40, height: 260)
                // The pivot sits 18pt below the arm's top edge, up and right of the spindle.
                .rotationEffect(.degrees(armAngle), anchor: UnitPoint(x: 0.5, y: 18 / 260))
                .offset(x: 155, y: -160 + (130 - 18))
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.72), value: armAngle)
                .allowsHitTesting(false)
        }
        .frame(height: 330)
    }

    private func nowPlaying(_ show: Show, index: Int, total: Int) -> some View {
        Button {
            detailTarget = FootprintDetailDestination(show: show)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(trackCode(index, total: total))
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(BSColor.Stage.accent)
                Text(show.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text([FootprintTextNormalizer.nonEmptyTrimmed(show.city), footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar())].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(BSColor.Stage.muted)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.dim)
            }
        }
        .buttonStyle(.plain)
    }

    private func trackList(_ tracks: [Show]) -> some View {
        let half = (tracks.count + 1) / 2
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, show in
                if index == 0 || index == half {
                    Text(index == 0 ? BSLocalization.text("SIDE A") : BSLocalization.text("SIDE B"))
                        .font(.system(size: 12, design: .serif))
                        .tracking(3)
                        .foregroundStyle(BSColor.Stage.dim)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
                trackRow(show, index: index, total: tracks.count)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private func trackRow(_ show: Show, index: Int, total: Int) -> some View {
        let isCurrent = index == trackIndex
        return Button {
            guard !isCurrent else { return }
            trackIndex = index
        } label: {
            HStack(spacing: 10) {
                Text(trackCode(index, total: total))
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(isCurrent ? BSColor.Stage.accent : BSColor.Stage.dim)
                    .frame(width: 30, alignment: .leading)
                Text(footprintDayText(show.effectiveDate, calendar: show.timingCalendar()))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(BSColor.Stage.dim)
                    .frame(width: 46, alignment: .leading)
                Text(show.name)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? BSColor.Stage.heroIvory : BSColor.Stage.foreground.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isCurrent {
                    FootprintEqualizer(isAnimating: !reduceMotion)
                } else {
                    Text(FootprintTextNormalizer.nonEmptyTrimmed(show.city) ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.Stage.dim)
                }
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func trackCode(_ index: Int, total: Int) -> String {
        let half = (total + 1) / 2
        return index < half ? "A\(index + 1)" : "B\(index - half + 1)"
    }
}

// MARK: - Record parts

/// A pressed record: grooves, track gaps and a centre label.
struct FootprintRecordDisc<Label: View>: View {
    let diameter: CGFloat
    let labelDiameter: CGFloat
    var grooves = 0
    @ViewBuilder let label: Label

    var body: some View {
        ZStack {
            Canvas { canvas, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                canvas.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(FootprintRoomPalette.vinyl))
                var radius = size.width / 2 - 2
                while radius > labelDiameter / 2 + 4 {
                    canvas.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                                  with: .color(Color.white.opacity(0.035)), lineWidth: 0.6)
                    radius -= 2.4
                }
                guard grooves > 1 else { return }
                let outer = size.width / 2 - 5, inner = labelDiameter / 2 + 8
                for gap in 1..<grooves {
                    let r = outer - (outer - inner) * CGFloat(gap) / CGFloat(grooves)
                    canvas.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                  with: .color(FootprintRoomPalette.groove), lineWidth: 1.8)
                }
            }
            label
                .frame(width: labelDiameter, height: labelDiameter)
                .background(FootprintRoomPalette.marqueePaper)
                .clipShape(Circle())
            Circle().fill(BSColor.Stage.background).frame(width: max(4, labelDiameter * 0.07))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Spins on its own clock so switching tracks never stutters the platter.
private struct FootprintSpinningRecord<Content: View>: View {
    let isSpinning: Bool
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.animation(paused: !isSpinning)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            content.rotationEffect(.degrees(isSpinning ? (seconds / 5.4).truncatingRemainder(dividingBy: 1) * 360 : 0))
        }
    }
}

/// Fixed light reflection: the record turns underneath it.
private struct FootprintRecordSheen: View {
    var body: some View {
        Circle().fill(AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0.10), location: 0.08),
                .init(color: .clear, location: 0.17),
                .init(color: .clear, location: 0.5),
                .init(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0.07), location: 0.59),
                .init(color: .clear, location: 0.68)
            ],
            center: .center,
            angle: .degrees(20)
        ))
    }
}

private struct FootprintTonearm: View {
    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(FootprintRoomPalette.brass)
                .frame(width: 3.5, height: 228)
                .offset(y: 20)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.12))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(FootprintRoomPalette.brass, lineWidth: 1))
                .frame(width: 18, height: 24)
                .offset(y: 236)
            Circle()
                .fill(Color(white: 0.1))
                .overlay(Circle().stroke(Color(white: 0.3), lineWidth: 1))
                .frame(width: 36, height: 36)
            Circle().fill(FootprintRoomPalette.brass).frame(width: 7, height: 7).offset(y: 14.5)
        }
        .accessibilityHidden(true)
    }
}

private struct FootprintEqualizer: View {
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { bar in
                    Capsule()
                        .fill(BSColor.Stage.accent)
                        .frame(width: 2, height: isAnimating ? 4 + 8 * abs(sin(t * 3 + Double(bar) * 1.1)) : 8)
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
