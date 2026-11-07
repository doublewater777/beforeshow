import SwiftData
import SwiftUI

/// A lit glass display case: one shelf per year, your own photos standing on the glass.
struct FootprintMerchCabinetView: View {
    let archive: FootprintArchiveSnapshot
    let shelves: [FootprintMerchShelf]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: UUID?
    @State private var lightLevel: Double = 0
    @State private var editing: MerchItem?
    @State private var detailTarget: FootprintDetailDestination?

    private var items: [MerchItem] { shelves.flatMap(\.items) }

    var body: some View {
        let selected = items.first { $0.id == selectedID } ?? items.first
        ScrollView {
            cabinet(selectedID: selected?.id)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .bsAdaptiveContentWidth()
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            if let selected { card(selected).id(selected.id).transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 14))) }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.8), value: selected?.id)
        .background { FootprintRoomPalette.cabinetRoom.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                FootprintArchiveTitle(
                    title: BSLocalization.text("周边柜"),
                    subtitle: BSLocalization.format("%1$lld 件 · 来自 %2$lld 场", items.count, Set(items.map(\.showID)).count)
                )
            }
        }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sheet(item: $editing) { MerchEditSheet(item: $0) }
        .sensoryFeedback(.selection, trigger: selectedID)
        .task { await switchOnLight() }
    }

    /// Fluorescent tube catching: a flash, a dip, then steady.
    private func switchOnLight() async {
        guard lightLevel == 0 else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { lightLevel = 1 }
            return
        }
        FootprintSoundPlayer.shared.play(.neon)
        for (level, ms) in [(0.6, 360), (0.2, 120), (1.0, 700)] {
            withAnimation(.easeOut(duration: Double(ms) / 1000)) { lightLevel = level }
            try? await Task.sleep(for: .milliseconds(ms))
        }
    }

    private func cabinet(selectedID: UUID?) -> some View {
        VStack(spacing: 0) {
            ForEach(shelves) { shelf in
                shelfRow(shelf, selectedID: selectedID)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
        .padding(.horizontal, 7)
        .background {
            ZStack(alignment: .top) {
                LinearGradient(colors: [FootprintRoomPalette.cabinetTop, FootprintRoomPalette.cabinetBottom], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [FootprintRoomPalette.cabinetLight.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                    .opacity(lightLevel)
            }
        }
        .overlay {
            LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .white.opacity(0.05), location: 0.36), .init(color: .clear, location: 0.44)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(FootprintRoomPalette.cabinetFrame, lineWidth: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.6), radius: 20, y: 20)
    }

    private func shelfRow(_ shelf: FootprintMerchShelf, selectedID: UUID?) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(shelf.items) { item in
                        itemButton(item, isSelected: item.id == selectedID)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .frame(minWidth: 300, alignment: .center)
            }
            Rectangle()
                .fill(LinearGradient(colors: [FootprintRoomPalette.glassShelf.opacity(0.22), FootprintRoomPalette.glassShelf.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                .frame(height: 12)
                .shadow(color: .black.opacity(0.5), radius: 5, y: 6)
            Text(String(shelf.year))
                .font(.system(size: 10, weight: .medium).width(.condensed))
                .tracking(3)
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)
                .padding(.top, 4)
                .padding(.bottom, 14)
        }
        .brightness((lightLevel - 1) * 0.25)
    }

    private func itemButton(_ item: MerchItem, isSelected: Bool) -> some View {
        let hasCutout = item.cutoutRelativePath != nil
        return Button { self.selectedID = item.id } label: {
            FootprintLocalPhoto(url: item.photoURL(cutout: true), contentMode: hasCutout ? .fit : .fill)
                .frame(width: 76, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: hasCutout ? 0 : 10, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 6, y: 8)
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FootprintRoomPalette.highlighter.opacity(isSelected ? 0.7 : 0), lineWidth: 1.5)
                }
                .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1, anchor: .bottom)
                .offset(y: isSelected && !reduceMotion ? -6 : 0)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editing = item } label: { Label(BSLocalization.text("编辑"), systemImage: "pencil") }
            Button(role: .destructive) { delete(item) } label: { Label(BSLocalization.text("删除"), systemImage: "trash") }
        }
        .accessibilityLabel(BSLocalization.format("%1$@，%2$@", item.displayName, archive.shows(for: [item.showID]).first?.name ?? ""))
    }

    private func card(_ item: MerchItem) -> some View {
        let show = archive.shows(for: [item.showID]).first
        return FootprintArchiveCard(fill: Color(white: 0.083)) {
            HStack(spacing: 14) {
                FootprintLocalPhoto(url: item.photoURL(cutout: false))
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.system(size: 19, weight: .black, design: .serif))
                        .foregroundStyle(BSColor.Stage.foreground)
                    if let show {
                        Button { detailTarget = FootprintDetailDestination(show: show) } label: {
                            Text(FootprintArchiveShowLine.place(show))
                                .font(.system(size: 13))
                                .foregroundStyle(BSColor.Stage.foreground.opacity(0.85))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Text(footprintFullDateText(show.effectiveDate, calendar: show.timingCalendar()))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(BSColor.Stage.foreground.opacity(0.5))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func delete(_ item: MerchItem) {
        if selectedID == item.id { selectedID = nil }
        Task { @MainActor in try? await MerchCaptureCoordinator.delete(item, in: modelContext) }
    }
}
