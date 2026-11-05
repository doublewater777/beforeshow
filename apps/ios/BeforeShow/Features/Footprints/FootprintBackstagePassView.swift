import SwiftUI

/// The lifetime stats as an earned AAA pass; milestones are pins on the lanyard.
struct FootprintBackstagePassView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    @State private var selectedPinID: String?
    @State private var motion = FootprintTiltMotion()
    @State private var dragTilt: CGSize = .zero
    @State private var counted = false
    @State private var clinks = 0
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pins = FootprintMilestoneBuilder.make(shows: archive.shows)
        let selected = pins.first { $0.id == selectedPinID } ?? pins.last { !$0.isLocked }
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                lanyard(pins: pins, selected: selected)
                card
                    .padding(.top, 126)
                    .keyframeAnimator(initialValue: reduceMotion ? 0.0 : 9.0, trigger: settled) { content, angle in
                        content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: -0.05))
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(-6, duration: 0.5)
                            SpringKeyframe(3.5, duration: 0.45)
                            SpringKeyframe(-1.6, duration: 0.4)
                            SpringKeyframe(0, duration: 0.5)
                        }
                    }
            }
            .frame(height: 580)
            if let selected {
                caption(for: selected)
                    .id(selected.id)
                    .transition(.opacity)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [Color(white: 0.08), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [FootprintRoomPalette.bulbGlow.opacity(0.14), .clear], center: .init(x: 0.2, y: 0.05), startRadius: 0, endRadius: 320)
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("现场护照")) } }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: clinks)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: settled) { _, done in done }
        .onAppear {
            if !reduceMotion { motion.start() }
            settled = true
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.3).delay(0.9)) { counted = true }
        }
        .onDisappear { motion.stop() }
    }

    // MARK: Lanyard

    private func lanyard(pins: [FootprintMilestone], selected: FootprintMilestone?) -> some View {
        ZStack(alignment: .top) {
            strap(angle: -44, x: -100)
            strap(angle: 44, x: 100)
            ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                pinButton(pin, isSelected: pin.id == selected?.id)
                    .offset(pinOffset(index: index, total: pins.count))
            }
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55), Color(white: 0.8)], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 24)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 3)
                .offset(y: 104)
        }
        .frame(maxWidth: .infinity)
    }

    private func strap(angle: Double, x: CGFloat) -> some View {
        Rectangle()
            .fill(Color(white: 0.08))
            .overlay(alignment: .leading) { Rectangle().fill(FootprintRoomPalette.brass.opacity(0.6)).frame(width: 2) }
            .overlay(alignment: .trailing) { Rectangle().fill(FootprintRoomPalette.brass.opacity(0.6)).frame(width: 2) }
            .overlay {
                Text(BSLocalization.text("ALL ACCESS · BEFORESHOW · ALL ACCESS"))
                    .font(.system(size: 9, weight: .medium).width(.condensed))
                    .tracking(3)
                    .foregroundStyle(BSColor.Stage.heroWarmGold)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
            }
            .clipped()
            .frame(width: 24, height: 150)
            .rotationEffect(.degrees(angle), anchor: .top)
            .offset(x: x, y: -16)
            .accessibilityHidden(true)
    }

    /// Pins run down the left strap to the clip, then back up the right one.
    private func pinOffset(index: Int, total: Int) -> CGSize {
        let leftCount = (total + 1) / 2
        let onLeft = index < leftCount
        let slot = onLeft ? index : index - leftCount
        let count = onLeft ? leftCount : total - leftCount
        let step = count > 1 ? Double(slot) / Double(count - 1) : 0.5
        // t is the distance along a strap from its top (0) to the clip (1).
        let t = onLeft ? 0.2 + 0.56 * step : 0.76 - 0.56 * step
        let x = (onLeft ? -100 : 100) * (1 - t)
        // Straps start at y -16 and meet the clip at y 88; the 44pt pin hangs from its centre.
        return CGSize(width: x, height: -16 + 104 * t - 22)
    }

    private func pinButton(_ pin: FootprintMilestone, isSelected: Bool) -> some View {
        Button {
            selectedPinID = pin.id
            guard !pin.isLocked else { return }
            clinks += 1
            FootprintSoundPlayer.shared.play(.clink)
        } label: {
            Text(glyph(for: pin))
                .font(.system(size: 13, weight: .black).width(.compressed))
                .foregroundStyle(pin.isLocked ? BSColor.Stage.heroWarmGold.opacity(0.5) : BSColor.Stage.heroWarmGold)
                .frame(width: 32, height: 32)
                .background {
                    if pin.isLocked {
                        Circle().strokeBorder(BSColor.Stage.heroWarmGold.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    } else {
                        Circle()
                            .fill(RadialGradient(colors: [Color(red: 0.23, green: 0.18, blue: 0.11), Color(red: 0.09, green: 0.07, blue: 0.05)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 22))
                            .overlay(Circle().strokeBorder(FootprintRoomPalette.brass, lineWidth: 2))
                            .shadow(color: .black.opacity(0.6), radius: 3, y: 3)
                    }
                }
                .scaleEffect(isSelected ? 1.18 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption(for: pin, part: \.title))
    }

    // MARK: Card

    private var card: some View {
        let latest = archive.shows.first
        let tilt = CGSize(
            width: dragTilt.width != 0 ? dragTilt.width : motion.roll,
            height: dragTilt.height != 0 ? dragTilt.height : motion.pitch
        )
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.115), Color(white: 0.055)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color.black.opacity(0.9)).frame(width: 46, height: 9).frame(maxWidth: .infinity).padding(.top, 12)
                HStack {
                    Text(BSLocalization.text("ALL ACCESS"))
                        .font(.system(size: 11, weight: .medium).width(.condensed))
                        .tracking(4)
                        .foregroundStyle(BSColor.Stage.heroWarmGold)
                    Spacer()
                    Text(BSLocalization.text("AAA"))
                        .font(.system(size: 44, weight: .black).width(.compressed))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.62, green: 0.49, blue: 0.26), Color(red: 1, green: 0.95, blue: 0.81), Color(red: 0.62, green: 0.49, blue: 0.26)], startPoint: UnitPoint(x: 0.5 - tilt.width * 0.5, y: 0), endPoint: UnitPoint(x: 1.5 - tilt.width * 0.5, y: 1)))
                }
                .padding(.horizontal, 18)
                .frame(height: 64)
                .overlay(alignment: .top) { Rectangle().fill(BSColor.Stage.accent.opacity(0.3)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(BSColor.Stage.accent.opacity(0.3)).frame(height: 1) }
                .padding(.top, 9)
                HStack(alignment: .top, spacing: 14) {
                    if let latest {
                        FootprintResolvedCoverImage(show: latest, cover: covers[latest.id])
                            .frame(width: 76, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        field(BSLocalization.text("HOLDER 持证人"), BSLocalization.text("你"))
                        field(BSLocalization.text("VALID 有效期"), "\(archive.firstShow.map { footprintFullDateText($0.effectiveDate, calendar: $0.timingCalendar()) } ?? "—") — ∞")
                        field(BSLocalization.text("PASS NO."), String(format: "%04d", archive.shows.count), accent: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                stats.padding(.horizontal, 18).padding(.top, 18)
                Spacer(minLength: 0)
            }
            FootprintHologramSheen(phase: 0.5 + tilt.width * 0.5)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)
        }
        .frame(width: 300, height: 430)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08)))
        .rotation3DEffect(.degrees(tilt.width * 8), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(-tilt.height * 6), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .shadow(color: .black.opacity(0.7), radius: 30, y: 30)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragTilt = CGSize(width: max(-1, min(1, value.translation.width / 120)), height: max(-1, min(1, -value.translation.height / 160)))
            }
            .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { dragTilt = .zero } })
        .accessibilityElement(children: .combine)
    }

    private var stats: some View {
        let hours = archive.totalDurationMinutes / 60
        return VStack(spacing: 0) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    stat(archive.shows.count, BSLocalization.text("SHOWS 场"))
                    stat(archive.artists.count, BSLocalization.text("ARTISTS 艺人"), leadingRule: true)
                }
                GridRow {
                    stat(archive.cities.count, BSLocalization.text("CITIES 城市"))
                    stat(archive.venues.count, BSLocalization.text("VENUES 场馆"), leadingRule: true)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
            HStack(alignment: .lastTextBaseline) {
                Text("\(counted ? hours : 0)")
                    .font(.system(size: 22, weight: .black).width(.compressed))
                    .foregroundStyle(BSColor.Stage.accent)
                    .contentTransition(.numericText())
                Text(BSLocalization.text("HRS ON THE FLOOR"))
                    .font(.system(size: 10, weight: .medium).width(.condensed))
                    .tracking(2)
                    .foregroundStyle(BSColor.Stage.muted)
                Spacer()
                FootprintBarcode().frame(width: 92, height: 30)
            }
            .padding(.top, 14)
        }
    }

    private func stat(_ value: Int, _ label: String, leadingRule: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(counted ? value : 0)")
                .font(.system(size: 30, weight: .black).width(.compressed))
                .foregroundStyle(BSColor.Stage.foreground)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .medium).width(.condensed))
                .tracking(2)
                .foregroundStyle(BSColor.Stage.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.leading, leadingRule ? 14 : 0)
        .overlay(alignment: .leading) { if leadingRule { Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1) } }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
    }

    private func field(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium).width(.condensed))
                .tracking(2)
                .foregroundStyle(BSColor.Stage.dim)
            Text(value)
                .font(.system(size: 14, weight: .medium).width(.condensed).monospacedDigit())
                .foregroundStyle(accent ? BSColor.Stage.accent : BSColor.Stage.foreground)
        }
    }

    // MARK: Pin copy

    private struct PinCopy { let kicker: String; let title: String; let detail: String }

    private func glyph(for pin: FootprintMilestone) -> String {
        switch pin.kind {
        case .first: return BSLocalization.text("1ST")
        case let .ordinal(value), let .latest(value): return "\(value)"
        case .firstAway: return BSLocalization.text("城")
        case let .peakYear(year, _): return "'\(year % 100)"
        case let .locked(target, _): return "\(target)"
        }
    }

    private func copy(for pin: FootprintMilestone) -> PinCopy {
        let show = pin.showID.flatMap { archive.shows(for: [$0]).first }
        let dated: (String) -> String = { suffix in
            [show.map { footprintFullDateText($0.effectiveDate, calendar: $0.timingCalendar()) }, suffix].compactMap { $0 }.joined(separator: " · ")
        }
        switch pin.kind {
        case .first:
            return PinCopy(kicker: BSLocalization.text("MILESTONE"), title: BSLocalization.text("第 1 场"), detail: dated(show?.name ?? ""))
        case let .ordinal(value):
            return PinCopy(kicker: BSLocalization.text("MILESTONE"), title: BSLocalization.format("第 %lld 场", value), detail: dated(show?.name ?? ""))
        case let .firstAway(city):
            return PinCopy(kicker: BSLocalization.text("FIRST AWAY"), title: BSLocalization.text("第一次跨城"), detail: dated(city))
        case let .peakYear(year, count):
            return PinCopy(kicker: BSLocalization.text("PEAK YEAR"), title: BSLocalization.text("最满的一年"), detail: BSLocalization.format("%@ · %lld 场", String(year), count))
        case let .latest(value):
            return PinCopy(kicker: BSLocalization.text("LATEST"), title: BSLocalization.format("第 %lld 场", value), detail: dated(show?.name ?? ""))
        case let .locked(target, remaining):
            return PinCopy(kicker: BSLocalization.text("LOCKED"), title: BSLocalization.format("第 %lld 场", target), detail: BSLocalization.format("还差 %lld 场", remaining))
        }
    }

    private func caption(for pin: FootprintMilestone, part: KeyPath<PinCopy, String>) -> String {
        copy(for: pin)[keyPath: part]
    }

    private func caption(for pin: FootprintMilestone) -> some View {
        let text = copy(for: pin)
        return VStack(spacing: 6) {
            Text(text.kicker)
                .font(.system(size: 11, weight: .medium).width(.condensed))
                .tracking(3)
                .foregroundStyle(BSColor.Stage.dim)
            Text(text.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(pin.isLocked ? BSColor.Stage.muted : BSColor.Stage.heroIvory)
            Text(text.detail)
                .font(.system(size: 13))
                .foregroundStyle(BSColor.Stage.muted)
                .lineLimit(1)
            if let song = Self.songNumber(for: pin).flatMap(FootprintNumberSongs.song(for:)) {
                FootprintNumberRecord(song: song, diameter: 52)
                    .fixedSize()
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 24)
    }

    /// The count a pin stands for, if it stands for one.
    private static func songNumber(for pin: FootprintMilestone) -> Int? {
        switch pin.kind {
        case .first: 1
        case let .ordinal(number), let .latest(number): number
        case .firstAway, .peakYear, .locked: nil
        }
    }
}

/// Rainbow foil that slides with the viewing angle; `phase` runs 0...1.
struct FootprintHologramSheen: View {
    let phase: Double

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.3),
                .init(color: Color(red: 1, green: 0.55, blue: 0.75).opacity(0.5), location: 0.42),
                .init(color: Color(red: 0.55, green: 0.86, blue: 1).opacity(0.5), location: 0.5),
                .init(color: Color(red: 1, green: 0.94, blue: 0.67).opacity(0.5), location: 0.58),
                .init(color: .clear, location: 0.7)
            ],
            startPoint: UnitPoint(x: -0.6 + phase * 1.2, y: 0),
            endPoint: UnitPoint(x: 0.4 + phase * 1.2, y: 1)
        )
        .blendMode(.colorDodge)
        .opacity(0.16)
    }
}

private struct FootprintBarcode: View {
    var body: some View {
        Canvas { canvas, size in
            let widths: [CGFloat] = [2, 1, 1, 3, 1, 2, 1, 1, 2, 3, 1, 1, 2, 1, 3, 1, 2, 1, 1, 2, 1, 3, 2, 1, 1, 2, 1, 3, 1, 1]
            var x: CGFloat = 0
            for (index, width) in widths.enumerated() where x < size.width {
                if index % 2 == 0 {
                    canvas.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(Color(white: 0.9)))
                }
                x += width + 1
            }
        }
        .accessibilityHidden(true)
    }
}
