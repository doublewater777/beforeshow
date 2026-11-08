import SwiftUI

/// Every night's setlist merged onto one sheet of paper taped to the floor.
/// A ringed number means you heard the song live more than once.
struct FootprintSetlistView: View {
    let archive: FootprintArchiveSnapshot
    let songs: [FootprintSetlistSong]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: FootprintSetlistTab = .most
    @State private var selectedID: String?
    @State private var isTaped = false
    @State private var detailTarget: FootprintDetailDestination?

    static let handwriting = Font.custom("Noteworthy-Bold", size: 22)

    var body: some View {
        let rows = FootprintSetlistArchive.list(songs, tab: tab)
        let selected = rows.first { $0.id == selectedID } ?? rows.first
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                tabs
                paper(rows: rows, selectedID: selected?.id)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .bsAdaptiveContentWidth()
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            if let selected { card(selected).id(selected.id).transition(cardTransition) }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85), value: selected?.id)
        .background { FootprintRoomPalette.setlistFloor.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                FootprintArchiveTitle(
                    title: BSLocalization.text("听过的歌"),
                    subtitle: BSLocalization.format("%1$lld 首 · 来自 %2$lld 场", songs.count, Set(songs.flatMap(\.showIDs)).count)
                )
            }
        }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.selection, trigger: selectedID)
        .sensoryFeedback(.impact(weight: .light), trigger: isTaped)
        .task {
            guard !isTaped else { return }
            try? await Task.sleep(for: .milliseconds(150))
            if !reduceMotion { FootprintSoundPlayer.shared.play(.tear) }
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.7)) { isTaped = true }
        }
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 14))
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(FootprintSetlistTab.allCases, id: \.self) { item in
                let isOn = item == tab
                Button {
                    tab = item
                    selectedID = nil
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? FootprintRoomPalette.setlistFloor : BSColor.Stage.foreground.opacity(0.7))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(isOn ? AnyShapeStyle(FootprintRoomPalette.setlistPaper) : AnyShapeStyle(Color.white.opacity(0.07)), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func paper(rows: [FootprintSetlistSong], selectedID: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption)
                .font(.system(size: 11, weight: .medium).width(.condensed))
                .tracking(3)
                .foregroundStyle(FootprintRoomPalette.setlistInk.opacity(0.5))
            if rows.isEmpty {
                Text(BSLocalization.text("每首都听过不止一次"))
                    .font(Self.handwriting)
                    .foregroundStyle(FootprintRoomPalette.setlistInk.opacity(0.5))
                    .padding(.vertical, 20)
            }
            VStack(spacing: 0) {
                ForEach(rows) { song in
                    row(song, isSelected: song.id == selectedID)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FootprintRoomPalette.setlistPaper, in: RoundedRectangle(cornerRadius: 2))
        .shadow(color: .black.opacity(0.6), radius: 20, y: 18)
        .overlay(alignment: .topLeading) { tape(angle: -6, delay: 0).offset(x: -14, y: -10) }
        .overlay(alignment: .topTrailing) { tape(angle: 8, delay: 0.12).offset(x: 12, y: -8) }
        .rotationEffect(.degrees(-1.2))
    }

    private var caption: String {
        switch tab {
        case .most: return "SETLIST · ALL NIGHTS"
        case .once: return BSLocalization.text("只在一个晚上出现过")
        case .artist: return "BY ARTIST"
        }
    }

    private func tape(angle: Double, delay: Double) -> some View {
        Rectangle()
            .fill(FootprintRoomPalette.tape.opacity(0.85))
            .frame(width: 88, height: 26)
            .rotationEffect(.degrees(angle))
            .scaleEffect(isTaped || reduceMotion ? 1 : 1.25)
            .opacity(isTaped ? 1 : 0)
            .animation((reduceMotion ? Animation.easeOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.6)).delay(delay), value: isTaped)
            .accessibilityHidden(true)
    }

    private func row(_ song: FootprintSetlistSong, isSelected: Bool) -> some View {
        Button { selectedID = song.id } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(song.title)
                    .font(Self.handwriting)
                    .foregroundStyle(FootprintRoomPalette.setlistInk)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(song.artistName)
                    .font(.system(size: 11))
                    .foregroundStyle(FootprintRoomPalette.setlistInk.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                countMark(song.count)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
            .frame(minHeight: 50)
            .background(isSelected ? FootprintRoomPalette.highlighter.opacity(0.28) : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(FootprintRoomPalette.setlistInk.opacity(0.12)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.format("%1$@，%2$@，现场听过 %3$lld 次", song.title, song.artistName, song.count))
    }

    private func countMark(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 14, weight: count > 1 ? .semibold : .regular).width(.condensed))
            .foregroundStyle(FootprintRoomPalette.setlistInk.opacity(count > 1 ? 1 : 0.45))
            .frame(width: 26, height: 26)
            .overlay { if count > 1 { Circle().stroke(FootprintRoomPalette.setlistInk, lineWidth: 1.5) } }
    }

    private func card(_ song: FootprintSetlistSong) -> some View {
        FootprintArchiveCard {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(song.title)
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(BSLocalization.format("现场听过 %lld 次", song.count))
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.accent)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(archive.shows(for: song.showIDs)) { show in
                    FootprintArchiveShowLine(show: show) { detailTarget = FootprintDetailDestination(show: $0) }
                }
            }
            .padding(.top, 10)
        }
    }
}
