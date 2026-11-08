import SwiftUI

/// One fabric wristband per companion; the longer the band, the more nights together.
struct FootprintCompanionBandsView: View {
    let archive: FootprintArchiveSnapshot
    let bands: [FootprintCompanionBand]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    @State private var hasArrived = false
    @State private var detailTarget: FootprintDetailDestination?

    var body: some View {
        let selected = bands.first { $0.id == selectedID } ?? bands.first
        let maxCount = max(1, bands.first?.count ?? 1)
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                        bandButton(band, index: index, isSelected: band.id == selected?.id, width: strapWidth(band.count, max: maxCount, available: geometry.size.width))
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
                .bsAdaptiveContentWidth()
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            if let selected { card(selected).id(selected.id).transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 14))) }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85), value: selected?.id)
        .background { BSColor.Stage.background.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                FootprintArchiveTitle(
                    title: BSLocalization.text("一起去的人"),
                    subtitle: BSLocalization.format("%1$lld 位 · 一起 %2$lld 场", bands.count, Set(bands.flatMap(\.showIDs)).count)
                )
            }
        }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.impact(weight: .light), trigger: selectedID)
        .onAppear { hasArrived = true }
    }

    private func strapWidth(_ count: Int, max maxCount: Int, available: CGFloat) -> CGFloat {
        let longest = min(available - 90, 320)
        let shortest = longest * 0.55
        return shortest + (longest - shortest) * CGFloat(count) / CGFloat(maxCount)
    }

    private func bandButton(_ band: FootprintCompanionBand, index: Int, isSelected: Bool, width: CGFloat) -> some View {
        let color = FootprintRoomPalette.wristbands[index % FootprintRoomPalette.wristbands.count]
        return Button {
            selectedID = band.id
            FootprintSoundPlayer.shared.play(.clink)
        } label: {
            HStack(spacing: 0) {
                HStack {
                    Text("+1 · ADMIT TWO")
                        .font(.system(size: 10, weight: .medium).width(.condensed))
                        .tracking(3)
                        .opacity(0.7)
                    Spacer(minLength: 8)
                    Text(band.name)
                        .font(.system(size: 20, weight: .black, design: .serif))
                        .lineLimit(1)
                }
                .foregroundStyle(FootprintRoomPalette.wristbandText)
                .padding(.leading, 20)
                .padding(.trailing, 14)
                .frame(width: width, height: 44)
                .background(color)
                .overlay(weave)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6))
                .overlay {
                    UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6)
                        .stroke(FootprintRoomPalette.highlighter.opacity(isSelected ? 0.7 : 0), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.5), radius: 8, y: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [FootprintRoomPalette.claspShade, FootprintRoomPalette.clasp, FootprintRoomPalette.claspShade], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 30, height: 40)
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 4)
                Spacer(minLength: 0)
                Text("\(band.count)")
                    .font(.system(size: 26, weight: .black).width(.compressed))
                    .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.Stage.foreground.opacity(0.55))
                    .padding(.trailing, 20)
            }
            .frame(height: 56)
            .opacity(isSelected ? 1 : 0.62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: hasArrived || reduceMotion ? 0 : -40)
        .opacity(hasArrived ? 1 : 0)
        .animation((reduceMotion ? Animation.easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.75)).delay(Double(index) * 0.08), value: hasArrived)
        .accessibilityLabel(BSLocalization.format("和%1$@一起 %2$lld 场", band.name, band.count))
    }

    /// Woven fabric: fine vertical threads.
    private var weave: some View {
        Canvas { canvas, size in
            var x: CGFloat = 0
            while x < size.width {
                canvas.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(.white.opacity(0.08)))
                x += 6
            }
        }
        .allowsHitTesting(false)
    }

    private func card(_ band: FootprintCompanionBand) -> some View {
        let shows = archive.shows(for: band.showIDs)
        let first = shows.last
        return FootprintArchiveCard {
            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.format("和 %@", band.name))
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(BSLocalization.format("一起 %lld 场", band.count))
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.accent)
            }
            HStack(spacing: 10) {
                fact(
                    BSLocalization.text("第一次一起"),
                    value: first.map { footprintFullDateText($0.effectiveDate, calendar: $0.timingCalendar()) } ?? "—",
                    detail: first.map(FootprintArchiveShowLine.place) ?? ""
                )
                fact(
                    BSLocalization.text("一起看得最多"),
                    value: band.topArtist ?? "—",
                    detail: band.topArtist == nil ? "" : BSLocalization.format("%lld 场", band.topArtistCount)
                )
            }
            .padding(.top, 12)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shows.prefix(3)) { show in
                    FootprintArchiveShowLine(show: show) { detailTarget = FootprintDetailDestination(show: $0) }
                }
            }
            .padding(.top, 12)
            NavigationLink {
                FootprintShowListView(title: BSLocalization.format("和 %@", band.name), shows: shows, archive: archive)
            } label: {
                Text(BSLocalization.format("看你们的 %lld 场", band.count))
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    private func fact(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(BSColor.Stage.foreground.opacity(0.5))
            Text(value).font(.system(size: 14).monospacedDigit()).foregroundStyle(BSColor.Stage.foreground)
            Text(detail).font(.system(size: 12)).foregroundStyle(BSColor.Stage.foreground.opacity(0.65))
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
