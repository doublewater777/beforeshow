import SwiftUI

/// Artists as a night sky: brighter stars were seen more often, lines are shared bills.
struct FootprintConstellationView: View {
    let archive: FootprintArchiveSnapshot

    @State private var selectedName: String?
    /// Stars under a finger right now, by finger.
    @State private var held: [Int: String] = [:]
    /// Notes tapped since the last pause, in the order played.
    @State private var phrase: [String] = []
    /// The phrase ringing out together as a chord after the fingers rest.
    @State private var ringing: [String] = []
    @State private var resolving: Task<Void, Never>?
    private let synth = FootprintStarSynth.shared
    @State private var linesDrawn = false
    @State private var detailTarget: FootprintDetailDestination?
    @State private var isShowingGuide = false
    @State private var isShowingPaywall = false
    @AppStorage(FootprintSkyScale.storageKey) private var scaleRawValue = FootprintSkyScale.pentatonic.rawValue
    @AppStorage(FootprintSkyShape.storageKey) private var shapeRawValue = FootprintSkyShape.free.rawValue
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var song: Task<Void, Never>?
    /// The star the song is on right now.
    @State private var songKey: String?
    /// The accompaniment chord sounding now and the stars it lights.
    @State private var songChord: (name: String, keys: Set<String>)?
    @State private var interrupted: InterruptedListening?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sky = shape.apply(to: FootprintConstellationBuilder.make(shows: archive.shows))
        let notes = Self.notes(for: sky, scale: scale)
        let selected = sky.stars.first { $0.name == selectedName }
        let pressed = Set(held.values).union(ringing).union(songKey.map { [$0] } ?? []).union(songChord?.keys ?? [])
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    FootprintStarDust(count: sky.dustCount, isTwinkling: !reduceMotion)
                    pressedDust(sky, lit: pressed, notes: notes, size: size)
                    if let selected { spotlight(on: point(selected.position, in: size)) }
                    lines(sky, selected: selected, size: size)
                    groupLabels(sky, size: size)
                    let neighbours = Self.neighbours(of: selected?.name, in: sky)
                    ForEach(sky.stars) { star in
                        starView(
                            star,
                            note: notes[star.name],
                            isSelected: star.name == selected?.name,
                            isPressed: pressed.contains(star.name),
                            showsName: star.count > 1 || neighbours.contains(star.name) || star.name == songKey
                        )
                        .position(point(star.position, in: size))
                    }
                    FootprintStarKeys(
                        keys: sky.stars.map { .init(name: $0.name, point: point($0.position, in: size)) }
                            + FootprintStarDust.points(count: sky.dustCount).enumerated().map {
                                .init(name: Self.dustKey($0.offset), point: dustPoint($0.element, in: size), isDust: true)
                            },
                        onPress: { finger, name in press(finger, name, sky: sky, notes: notes) },
                        onRelease: { release($0, notes: notes) }
                    )
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) { chordReadout(notes: notes) }
            // The card's room is kept from the start so the first tap doesn't move the stars.
            ZStack {
                if let selected {
                    card(for: selected)
                        .id(selected.name)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(height: 214)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background {
            LinearGradient(colors: [FootprintRoomPalette.skyTop, FootprintRoomPalette.skyBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    FootprintNavigationTitle(title: BSLocalization.text("你的星空"))
                    Text(BSLocalization.format("%lld 位艺人", archive.artists.count))
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { song == nil ? playSong(notes: notes, stars: Set(sky.stars.map(\.name))) : stopSong() } label: {
                    Image(systemName: song == nil ? "play.circle" : "stop.circle")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(song == nil ? BSLocalization.format("弹一首《%@》", FootprintStarSong.song(for: scale).title) : BSLocalization.text("停止"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                FootprintSkyMenu(
                    scale: scale,
                    shape: shape,
                    isPro: isPro,
                    onScale: { scaleRawValue = $0.rawValue },
                    onShape: { shapeRawValue = $0.rawValue },
                    onLocked: { isShowingPaywall = true }
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingGuide = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel(BSLocalization.text("怎么玩"))
                    .popover(isPresented: $isShowingGuide) {
                        FootprintConstellationGuide()
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sheet(isPresented: $isShowingPaywall) { ProPaywallView() }
        .onChange(of: scale) { resetPlaying() }
        .onChange(of: shape) { resetPlaying() }
        .sensoryFeedback(.impact(weight: .light), trigger: held.count)
        .sensoryFeedback(.impact(weight: .medium), trigger: ringing.isEmpty) { _, isEmpty in !isEmpty }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.6).delay(0.3)) { linesDrawn = true }
        }
        .onDisappear {
            stopSong()
            resolving?.cancel()
            synth.stop()
            restoreInterruptedListening()
        }
    }

    // MARK: Scale and shape

    private var isPro: Bool { ProEntitlementStorage.decode(entitlementRawValue).isProActive }

    private var scale: FootprintSkyScale { .effective(scaleRawValue, isPro: isPro) }

    private var shape: FootprintSkyShape { .effective(shapeRawValue, isPro: isPro) }

    private func resetPlaying() {
        stopSong()
        resolving?.cancel()
        phrase = []
        ringing = []
    }

    // MARK: Playing

    /// Every point of light's note, tuned by how far across the sky it sits, like a keyboard.
    private static func notes(for sky: FootprintConstellation, scale: FootprintSkyScale) -> [String: Int] {
        var notes = Dictionary(uniqueKeysWithValues: sky.stars.map { ($0.name, FootprintStarScale.note(across: $0.position.x, scale: scale)) })
        for (index, unit) in FootprintStarDust.points(count: sky.dustCount).enumerated() {
            notes[dustKey(index)] = FootprintStarScale.note(across: unit.x, scale: scale)
        }
        return notes
    }

    private static func dustKey(_ index: Int) -> String { "dust:\(index)" }

    /// Dust is spread over the whole sky, not the inset the named stars keep to.
    private func dustPoint(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }

    private func press(_ finger: Int, _ name: String, sky: FootprintConstellation, notes: [String: Int]) {
        guard let note = notes[name] else { return }
        rememberInterruptedListening()
        stopSong()
        let star = sky.stars.first { $0.name == name }
        // Artists seen once still ring clearly; the brightest carry the most overtone.
        synth.press(finger, note: note, brightness: star.map { $0.count >= 3 ? 1 : $0.count == 2 ? 0.8 : 0.6 } ?? 0.55, timbre: scale.timbre)
        held[finger] = name
        resolving?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if star != nil { selectedName = name }
            // A new note after a chord has rung starts the next phrase.
            if !ringing.isEmpty {
                ringing = []
                phrase = []
            }
            if !phrase.contains(name) {
                phrase.append(name)
                if phrase.count > Self.phraseLimit { phrase.removeFirst() }
            }
        }
    }

    /// The sky plays this scale's song by itself, lighting the nearest star on each note. A finger takes over.
    private func playSong(notes: [String: Int], stars: Set<String>) {
        rememberInterruptedListening()
        stopSong()
        let tune = FootprintStarSong.song(for: scale)
        let timbre = scale.timbre
        song = Task { @MainActor in
            async let accompaniment: Void = playChords(tune, timbre: timbre, notes: notes, stars: stars)
            await playMelody(tune, timbre: timbre, notes: notes, stars: stars)
            await accompaniment
            guard !Task.isCancelled else { return }
            song = nil
        }
    }

    private func rememberInterruptedListening() {
        if interrupted == nil { interrupted = InterruptedListening.capture() }
    }

    private func restoreInterruptedListening() {
        defer { interrupted = nil }
        interrupted?.resume()
    }

    private func playMelody(_ tune: FootprintStarSong, timbre: FootprintStarSynth.Timbre, notes: [String: Int], stars: Set<String>) async {
        for step in tune.steps {
            let length = step.beats * tune.beat
            synth.press(Self.songVoice, note: step.note, brightness: 0.8, timbre: timbre)
            withAnimation(.easeOut(duration: 0.12)) { songKey = FootprintStarSong.key(for: step.note, notes: notes, stars: stars) }
            try? await Task.sleep(for: .seconds(length * 0.85))
            guard !Task.isCancelled else { return }
            synth.release(Self.songVoice)
            withAnimation(.easeOut(duration: 0.2)) { songKey = nil }
            try? await Task.sleep(for: .seconds(length * 0.15))
            guard !Task.isCancelled else { return }
        }
    }

    /// The accompaniment: each chord strummed low to high under the melody, its stars lit while it sounds.
    private func playChords(_ tune: FootprintStarSong, timbre: FootprintStarSynth.Timbre, notes: [String: Int], stars: Set<String>) async {
        for chord in tune.chords {
            let keys = Set(chord.notes.compactMap { FootprintStarSong.key(for: $0, notes: notes, stars: stars) })
            withAnimation(.easeOut(duration: 0.15)) { songChord = chord.notes.isEmpty ? nil : (chord.name, keys) }
            for (index, note) in chord.notes.enumerated() {
                synth.press(Self.songChordVoice + index, note: note, brightness: 0.5, timbre: timbre, gain: 0.45)
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 25))
            }
            try? await Task.sleep(for: .seconds(chord.beats * tune.beat - (reduceMotion ? 0 : 0.025) * Double(chord.notes.count)))
            for index in chord.notes.indices { synth.release(Self.songChordVoice + index) }
            guard !Task.isCancelled else { return }
        }
        withAnimation(.easeOut(duration: 0.3)) { songChord = nil }
    }

    private func stopSong() {
        guard let song else { return }
        song.cancel()
        self.song = nil
        synth.release(Self.songVoice)
        for index in 0..<4 { synth.release(Self.songChordVoice + index) }
        songKey = nil
        songChord = nil
    }

    /// Voice ids for the song's melody and accompaniment, clear of finger and chord ids.
    private static let songVoice = 2_000_000
    private static let songChordVoice = 2_000_100

    /// More than this many notes stops sounding like one chord.
    private static let phraseLimit = 6
    /// How long the fingers rest before the phrase rings out together.
    private static let pause: Duration = .milliseconds(1200)

    private func release(_ finger: Int, notes: [String: Int]) {
        synth.release(finger)
        held[finger] = nil
        guard held.isEmpty else { return }
        resolving?.cancel()
        resolving = Task { @MainActor in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            await ringOut(notes: notes)
        }
    }

    /// Plays the phrase back as one chord, strummed low to high, then lets it fade.
    private func ringOut(notes: [String: Int]) async {
        let keys = phrase.filter { notes[$0] != nil }.sorted { notes[$0]! < notes[$1]! }
        guard keys.count >= 2 else {
            phrase = []
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { ringing = keys }
        for (index, key) in keys.enumerated() {
            guard !Task.isCancelled, let note = notes[key] else { break }
            synth.press(Self.chordVoice + index, note: note, brightness: 0.85, timbre: scale.timbre)
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 35))
        }
        try? await Task.sleep(for: .milliseconds(1500))
        for index in keys.indices { synth.release(Self.chordVoice + index) }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.6)) {
            ringing = []
            phrase = []
        }
    }

    /// Voice ids for the chord, well clear of finger ids.
    private static let chordVoice = 1_000_000

    /// A ring and the note name on any dust under a finger.
    private func pressedDust(_ sky: FootprintConstellation, lit: Set<String>, notes: [String: Int], size: CGSize) -> some View {
        let points = FootprintStarDust.points(count: sky.dustCount)
        let pressed = lit.filter { $0.hasPrefix("dust:") }.sorted().compactMap { key in
            Int(key.dropFirst(5)).flatMap { points.indices.contains($0) ? (key, points[$0]) : nil }
        }
        return ForEach(pressed, id: \.0) { key, unit in
            VStack(spacing: 4) {
                if let note = notes[key] {
                    Text(verbatim: FootprintStarScale.name(of: note))
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(FootprintRoomPalette.spotlight)
                }
                Circle()
                    .stroke(FootprintRoomPalette.spotlight.opacity(0.8), lineWidth: 1.2)
                    .frame(width: 18, height: 18)
            }
            .position(dustPoint(unit, in: size).applying(.init(translationX: 0, y: -8)))
            .transition(.opacity)
        }
        .allowsHitTesting(false)
    }

    /// The notes gathered so far, then the chord they make once it rings.
    @ViewBuilder
    private func chordReadout(notes: [String: Int]) -> some View {
        let isRinging = !ringing.isEmpty
        let playing = (isRinging ? ringing : phrase).compactMap { notes[$0] }
        if song != nil {
            VStack(spacing: 2) {
                Text(verbatim: "《\(FootprintStarSong.song(for: scale).title)》 · \(scale.title)")
                    .font(.system(size: 13, design: .serif))
                    .tracking(2)
                    .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.75))
                if let chord = songChord?.name {
                    Text(verbatim: chord)
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(FootprintRoomPalette.spotlight)
                        .contentTransition(.opacity)
                }
            }
            .padding(.top, 8)
            .transition(.opacity)
            .allowsHitTesting(false)
        } else if !playing.isEmpty {
            VStack(spacing: 2) {
                if isRinging, let chord = FootprintStarScale.chord(of: playing) {
                    Text(verbatim: chord)
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(FootprintRoomPalette.spotlight)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Text(verbatim: (isRinging ? playing.sorted() : playing).map(FootprintStarScale.name(of:)).joined(separator: " · "))
                    .font(.system(size: 13, design: .serif))
                    .tracking(2)
                    .foregroundStyle(isRinging ? FootprintRoomPalette.spotlight.opacity(0.9) : FootprintRoomPalette.starlight.opacity(0.75))
            }
            .padding(.top, 8)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func point(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: 24 + unit.y * (size.height - 48))
    }

    private func lines(_ sky: FootprintConstellation, selected: FootprintConstellation.Star?, size: CGSize) -> some View {
        let byName = Dictionary(uniqueKeysWithValues: sky.stars.map { ($0.name, $0) })
        return ForEach(Array(sky.edges.enumerated()), id: \.offset) { _, edge in
            if let a = byName[edge.from], let b = byName[edge.to] {
                let hot = edge.from == selected?.name || edge.to == selected?.name
                Path { path in
                    path.move(to: point(a.position, in: size))
                    path.addLine(to: point(b.position, in: size))
                }
                .trim(from: 0, to: linesDrawn ? 1 : 0)
                .stroke(hot ? BSColor.Stage.accent.opacity(0.85) : FootprintRoomPalette.starlight.opacity(0.32), lineWidth: hot ? 1.4 : 0.8)
                .animation(.easeOut(duration: 0.3), value: hot)
            }
        }
        .allowsHitTesting(false)
    }

    private func groupLabels(_ sky: FootprintConstellation, size: CGSize) -> some View {
        ForEach(sky.groups, id: \.brightest) { group in
            Text(group.title ?? BSLocalization.format("%@座", group.brightest))
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.45))
                .position(point(group.labelAnchor, in: size).applying(.init(translationX: 0, y: 40)))
                .allowsHitTesting(false)
        }
    }

    private func spotlight(on target: CGPoint) -> some View {
        Path { path in
            path.move(to: CGPoint(x: target.x - 8, y: 0))
            path.addLine(to: CGPoint(x: target.x + 8, y: 0))
            path.addLine(to: CGPoint(x: target.x + 70, y: target.y))
            path.addLine(to: CGPoint(x: target.x - 70, y: target.y))
            path.closeSubpath()
        }
        .fill(LinearGradient(colors: [FootprintRoomPalette.spotlight.opacity(0), FootprintRoomPalette.spotlight.opacity(0.13)], startPoint: .top, endPoint: .bottom))
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: target)
        .allowsHitTesting(false)
    }

    /// Single-show stars stay unnamed unless they share a line with the selected star.
    private static func neighbours(of name: String?, in sky: FootprintConstellation) -> Set<String> {
        guard let name else { return [] }
        return Set(sky.edges.flatMap { edge -> [String] in
            edge.from == name ? [edge.to] : edge.to == name ? [edge.from] : []
        })
    }

    private func starView(_ star: FootprintConstellation.Star, note: Int?, isSelected: Bool, isPressed: Bool, showsName: Bool) -> some View {
        let core: CGFloat = star.count >= 3 ? 8 : star.count == 2 ? 6 : 3.5
        let halo: CGFloat = star.count >= 3 ? 34 : star.count == 2 ? 22 : 12
        // Names hug the inside of the sky near its edges instead of running off screen.
        let labelAlignment: Alignment = star.position.x > 0.75 ? .bottomTrailing : star.position.x < 0.25 ? .bottomLeading : .bottom
        return ZStack {
                FootprintBreathingHalo(
                    diameter: halo,
                    color: isSelected ? FootprintRoomPalette.spotlight : FootprintRoomPalette.starlight,
                    strength: star.count == 1 ? 0.35 : 0.55,
                    isBreathing: !reduceMotion
                )
                if star.count >= 3 {
                    Rectangle().fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .top, endPoint: .bottom)).frame(width: 1.5, height: 30)
                    Rectangle().fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)).frame(width: 30, height: 1.5)
                }
                if isPressed {
                    Circle()
                        .stroke(FootprintRoomPalette.spotlight.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                Circle()
                    .fill(isSelected || isPressed ? FootprintRoomPalette.spotlight : .white)
                    .frame(width: core, height: core)
                    .shadow(color: .white, radius: 3)
                    .scaleEffect(isPressed ? 1.6 : 1)
            }
            .frame(width: 44, height: 44)
            .overlay(alignment: .top) {
                if isPressed, let note {
                    Text(verbatim: FootprintStarScale.name(of: note))
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(FootprintRoomPalette.spotlight)
                        .fixedSize()
                        .offset(y: -12)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .overlay(alignment: labelAlignment) {
                if showsName || isSelected {
                    Text(star.name)
                        .font(.system(size: star.count >= 2 ? 12 : 10, weight: star.count >= 3 ? .semibold : .regular))
                        .foregroundStyle(isSelected ? BSColor.Stage.accent : FootprintRoomPalette.starlight.opacity(star.count >= 2 ? 0.85 : 0.5))
                        .fixedSize()
                        .offset(y: 14)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
    }

    private func card(for star: FootprintConstellation.Star) -> some View {
        let shows = FootprintArchiveRankingBuilder.chronological(archive.shows.filter { $0.artistNames.contains(star.name) })
        let partners = Self.billPartners(of: star.name, in: shows)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(star.name)
                    .font(.system(size: 22, weight: .heavy, design: .serif))
                    .foregroundStyle(BSColor.Stage.heroIvory)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(BSLocalization.format("看过 %lld 场", star.count))
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.accent)
            }
            ForEach(shows.suffix(3)) { show in
                Button { detailTarget = FootprintDetailDestination(show: show) } label: {
                    HStack(spacing: 12) {
                        Text(footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.55))
                        Text([FootprintTextNormalizer.nonEmptyTrimmed(show.venueName), show.name].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(BSColor.Stage.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(Color.white.opacity(0.08))
            Text(partners.isEmpty
                 ? BSLocalization.text("孤星：每次都是专场")
                 : BSLocalization.format("同台过 %lld 位：%@", partners.count, partners.prefix(6).joined(separator: "、")))
                .font(.system(size: 12))
                .foregroundStyle(FootprintRoomPalette.starlight.opacity(0.6))
                .lineLimit(2)
        }
        .padding(18)
        // A fixed height keeps the sky still while fingers move between stars.
        .frame(height: 214, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(FootprintRoomPalette.skyBottom.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(FootprintRoomPalette.starlight.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    static func billPartners(of name: String, in shows: [Show]) -> [String] {
        var seen = Set([name])
        return shows.flatMap(\.artistNames).filter { seen.insert($0).inserted }
    }
}

private struct FootprintBreathingHalo: View {
    let diameter: CGFloat
    let color: Color
    let strength: Double
    let isBreathing: Bool
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(strength), .clear], center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .scaleEffect(expanded ? 1.18 : 1)
            .onAppear {
                guard isBreathing else { return }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { expanded = true }
            }
    }
}

/// One faint point for every artist seen once and never on a shared bill.
private struct FootprintStarDust: View {
    let count: Int
    let isTwinkling: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 10, paused: !isTwinkling)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                for grain in Self.grains(count: count) {
                    let x = grain.point.x * size.width, y = grain.point.y * size.height
                    let alpha = isTwinkling ? 0.35 + 0.45 * (0.5 + 0.5 * sin(t * 1.6 + grain.phase)) : 0.6
                    canvas.fill(Path(ellipseIn: CGRect(x: x - grain.radius, y: y - grain.radius, width: grain.radius * 2, height: grain.radius * 2)),
                                with: .color(FootprintRoomPalette.starlight.opacity(alpha)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Where each point of dust sits, as a fraction of the sky; the same every time it is drawn.
    static func points(count: Int) -> [CGPoint] { grains(count: count).map(\.point) }

    private static func grains(count: Int) -> [(point: CGPoint, radius: CGFloat, phase: Double)] {
        var seed: UInt64 = 7
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt32.max >> 1)
        }
        return (0..<count).map { _ in
            let point = CGPoint(x: next(), y: next())
            let radius: CGFloat = next() < 0.85 ? 0.5 : 0.8
            return (point, radius, next() * 6.28)
        }
    }
}
