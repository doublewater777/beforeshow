import SwiftUI

/// Fifty numbered records, one per show count. Each show you go to presses the next one;
/// the rest wait in the dark.
struct FootprintRecordWallView: View {
    let archive: FootprintArchiveSnapshot

    @State private var selected: Int?
    @State private var controller = FootprintNumberSongPlayer.shared
    @State private var detailTarget: FootprintDetailDestination?
    @Environment(\.openURL) private var openURL

    private static let disc: CGFloat = 76

    /// The show that unlocked each count, oldest first.
    private var ordered: [Show] { FootprintArchiveRankingBuilder.chronological(archive.shows) }

    var body: some View {
        let ordered = ordered
        let shelf = FootprintNumberSongs.shelf(showCount: ordered.count)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(shelf)
                    .padding(.top, 12)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 20) {
                    ForEach(1...shelf.total, id: \.self) { number in
                        slot(number, show: ordered.indices.contains(number - 1) ? ordered[number - 1] : nil, next: shelf.next?.number)
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, BSSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selected {
                card(selected, show: ordered.indices.contains(selected - 1) ? ordered[selected - 1] : nil, showCount: ordered.count)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: selected)
        .background {
            ZStack {
                LinearGradient(colors: [Color(white: 0.07), Color(white: 0.03)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [FootprintRoomPalette.bulbGlow.opacity(0.12), .clear], center: .init(x: 0.5, y: 0.05), startRadius: 0, endRadius: 360)
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("数字唱片")) } }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.selection, trigger: selected)
        .task { await controller.load(shelf.unlocked) }
        .onDisappear { controller.stopAll() }
    }

    /// Your current count's record up front, bigger, with how far the shelf has filled.
    private func header(_ shelf: FootprintRecordShelf) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                if let latest = shelf.unlocked.first {
                    Button { pick(latest.number, isUnlocked: true) } label: {
                        FootprintNumberDisc(
                            number: latest.number,
                            diameter: 136,
                            isPlaying: controller.isPlaying(latest.number),
                            artworkURL: controller.previews[latest.number]?.artworkURL
                        )
                    }
                    .buttonStyle(BSPressStyle())
                    .accessibilityLabel(BSLocalization.format("第 %lld 张数字唱片", latest.number))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(shelf.unlocked.count))
                            .font(.system(size: 56, weight: .black).width(.compressed))
                            .foregroundStyle(FootprintRoomPalette.bulb)
                        Text("/ \(shelf.total)")
                            .font(.system(size: 22, weight: .bold).width(.compressed))
                            .foregroundStyle(BSColor.Stage.dim)
                    }
                    if let latest = shelf.unlocked.first {
                        let preview = controller.previews[latest.number]
                        Text(preview?.title ?? latest.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(BSColor.Stage.foreground)
                            .lineLimit(2)
                        Text(preview?.artist ?? latest.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                    if let next = shelf.next {
                        Text(BSLocalization.format("下一张 · 第 %lld 场", next.number))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BSColor.Stage.accent)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            GeometryReader { proxy in
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [FootprintRoomPalette.brass, FootprintRoomPalette.bulb], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * CGFloat(shelf.unlocked.count) / CGFloat(max(shelf.total, 1)))
                            .shadow(color: FootprintRoomPalette.bulbGlow.opacity(0.6), radius: 4)
                    }
            }
            .frame(height: 6)
        }
    }

    // MARK: Slots

    private func slot(_ number: Int, show: Show?, next: Int?) -> some View {
        let isNext = number == next
        let isSelected = number == selected
        return Button { pick(number, isUnlocked: show != nil) } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let show {
                        FootprintNumberDisc(number: number, diameter: Self.disc, isPlaying: controller.isPlaying(number), artworkURL: controller.previews[number]?.artworkURL)
                    } else if isNext {
                        Circle()
                            .strokeBorder(BSColor.Stage.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .overlay {
                                Text("?")
                                    .font(.system(size: 22, weight: .black).width(.compressed))
                                    .foregroundStyle(BSColor.Stage.accent)
                            }
                            .frame(width: Self.disc, height: Self.disc)
                            .phaseAnimator([0.45, 1.0]) { ring, opacity in ring.opacity(opacity) } animation: { _ in .easeInOut(duration: 1.1) }
                    } else {
                        // Not pressed yet: a blank disc with the number engraved.
                        Circle()
                            .fill(Color(white: 0.075))
                            .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .overlay(Circle().fill(Color(white: 0.05)).frame(width: Self.disc * 0.42, height: Self.disc * 0.42))
                            .frame(width: Self.disc, height: Self.disc)
                    }
                }
                .frame(width: Self.disc, height: Self.disc)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(BSColor.Stage.accent, lineWidth: 2)
                            .frame(width: Self.disc + 8, height: Self.disc + 8)
                    }
                }
                Text(String(format: "%02d", number))
                    .font(.system(size: 11, weight: .semibold).width(.condensed).monospacedDigit())
                    .foregroundStyle(show != nil ? BSColor.Stage.foreground.opacity(0.85) : isNext ? BSColor.Stage.accent : Color(white: 0.28))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(show == nil
            ? BSLocalization.format("第 %lld 场解锁", number)
            : BSLocalization.format("第 %lld 张数字唱片", number))
    }

    /// Picking a record plays it (one already playing keeps going); picking it again pauses or resumes.
    /// The card closes only with its ×, and the music carries on.
    private func pick(_ number: Int, isUnlocked: Bool) {
        guard isUnlocked, let song = FootprintNumberSongs.song(for: number) else {
            selected = selected == number ? nil : number
            return
        }
        if selected == number {
            Task { await controller.toggle(song) }
            return
        }
        controller.stopAll(resumeListening: false)
        selected = number
        Task { await controller.start(song) }
    }

    // MARK: Card

    private func card(_ number: Int, show: Show?, showCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            HStack(alignment: .top, spacing: 16) {
                if let show, let song = FootprintNumberSongs.song(for: number) {
                    unlockedCard(song, show: show)
                } else {
                    sealedCard(number, remaining: number - showCount)
                }
                Spacer(minLength: 0)
                BSRoundIconButton(systemName: "xmark", label: BSLocalization.text("关闭")) {
                    selected = nil
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .padding(.bottom, BSSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.09), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func unlockedCard(_ song: FootprintNumberSong, show: Show) -> some View {
        let isPlaying = controller.isPlaying(song.number)
        let preview = controller.previews[song.number]
        return HStack(alignment: .top, spacing: 16) {
            Button {
                Task { await controller.toggle(song) }
            } label: {
                FootprintNumberDisc(number: song.number, diameter: 112, isPlaying: isPlaying, artworkURL: preview?.artworkURL)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? BSLocalization.format("暂停 %@", song.title) : BSLocalization.format("试听 %@", song.title))
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: "No. %02d", song.number))
                    .font(.system(size: 11, weight: .semibold).width(.condensed))
                    .tracking(2)
                    .foregroundStyle(BSColor.Stage.accent)
                Text(preview?.title ?? song.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(2)
                Text(preview?.artist ?? song.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
                ForEach(Self.details(preview), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.Stage.dim)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Button { Task { await controller.toggle(song) } } label: {
                        Image(systemName: isPlaying || controller.isPreparing(song.number) ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BSColor.Stage.background)
                            .frame(width: 28, height: 28)
                            .background(BSColor.Stage.foreground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? BSLocalization.text("暂停") : BSLocalization.text("播放"))
                    FootprintNumberSongStatus(number: song.number)
                }
                .padding(.top, 6)
                HStack(spacing: 8) {
                    Button { detailTarget = FootprintDetailDestination(show: show) } label: {
                        Text(BSLocalization.format("第 %lld 场 · %@", song.number, show.name))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                    if let link = preview?.storeURL {
                        Button { openURL(link) } label: {
                            Image(systemName: "arrow.up.right")
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.07), in: Circle())
                        }
                        .accessibilityLabel(BSLocalization.text("在 Apple Music 中打开"))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.85))
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    /// "Album · 2006", "Alternative · 4:28" when the store knows them.
    private static func details(_ preview: SongPreview?) -> [String] {
        guard let preview else { return [] }
        let album = [preview.album, preview.releaseYear.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        let length = preview.duration.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) }
        let genre = [preview.genre, length].compactMap { $0 }.joined(separator: " · ")
        return [album, genre].filter { !$0.isEmpty }
    }

    private func sealedCard(_ number: Int, remaining: Int) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Circle()
                .strokeBorder(BSColor.Stage.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .overlay {
                    Text("?")
                        .font(.system(size: 34, weight: .black).width(.compressed))
                        .foregroundStyle(BSColor.Stage.accent)
                }
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "No. %02d", number))
                    .font(.system(size: 11, weight: .semibold).width(.condensed))
                    .tracking(2)
                    .foregroundStyle(BSColor.Stage.accent)
                Text(BSLocalization.format("第 %lld 场解锁", number))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Text(BSLocalization.format("还差 %lld 场", remaining))
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.muted)
            }
        }
    }
}
