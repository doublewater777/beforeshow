import SwiftUI

struct ListeningCabinetSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var matchingSlotIndex: Int?
    @State private var matchingArtistName = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: BSSpacing.sm), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    ListeningArtistSelector(
                        artists: room.browseArtists,
                        selection: room.browser.scope,
                        select: room.selectScope,
                        onConnect: { index, name in
                            matchingSlotIndex = index
                            matchingArtistName = name
                        }
                    )
                    if room.libraryDiscs.isEmpty || room.display.recoveryAction != nil {
                        ListeningCabinetAvailabilityView(room: room) {
                            if let artist = room.browseArtists.first(where: { !$0.isConnected }) {
                                matchingSlotIndex = artist.slotIndex
                                matchingArtistName = artist.name
                            }
                        }
                    }
                    LazyVGrid(columns: columns, spacing: BSSpacing.lg) {
                        ForEach(room.libraryDiscs) { disc in
                            ListeningCabinetDiscCell(
                                disc: disc, show: room.show,
                                presentation: room.discPresentation(for: disc),
                                isLoaded: room.mechanism.disc?.id == disc.id && room.mechanism.hasDisc
                            ) {
                                room.selectCabinetDisc(disc)
                            }
                        }
                    }
                }
                .padding(BSSpacing.roomy)
            }
            .background(BSColor.Stage.background)
            .foregroundStyle(BSColor.Stage.foreground)
            .navigationTitle(BSLocalization.text("唱片柜"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BSChromeToolbarCloseButton { dismiss() } }
            .sheet(isPresented: Binding(
                get: { matchingSlotIndex != nil },
                set: { if !$0 { matchingSlotIndex = nil } }
            )) {
                if let slot = matchingSlotIndex {
                    ListeningArtistMatchSheet(room: room, slotIndex: slot, query: matchingArtistName)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listening.cabinet")
    }
}
