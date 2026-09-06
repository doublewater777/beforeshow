import SwiftUI

struct ListeningCabinetView: View {
    @Bindable var room: ListeningRoomCoordinator
    let scale: CGFloat
    let showDetails: (ListeningDisc) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.text("唱片柜")).font(BSFont.headline)
                Spacer()
                Text(String(format: "%02d", room.discs.count)).font(BSFont.V3.caption).monospacedDigit().foregroundStyle(BSColor.Stage.dim)
            }.padding(.top, BSSpacing.lg).padding(.bottom, BSSpacing.sm)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: BSSpacing.lg) {
                    ForEach(room.discs) { disc in
                        VStack(spacing: BSSpacing.xs) {
                            ZStack {
                                ListeningDiscArtwork(disc: disc)
                                    .frame(width: ListeningStyle.shelfDiscSize, height: ListeningStyle.shelfDiscSize)
                                    .scaleEffect(x: 1, y: cos(room.mechanism.configuration.geometry.tiltDegrees * .pi / 180))
                                    .opacity(room.mechanism.disc?.id == disc.id && room.mechanism.position != .stored ? 0 : 1)
                                    .listeningFrame("slot:\(disc.id)")
                                    .offset(x: BSSpacing.sm, y: -BSSpacing.sm)
                                ListeningArtwork(url: disc.artworkURL, title: disc.title)
                                    .frame(width: ListeningStyle.sleeveSize, height: ListeningStyle.sleeveSize)
                                    .overlay(alignment: .leading) {
                                        LinearGradient(colors: [.white.opacity(0.15), .black.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 7)
                                    }
                                    .overlay(Rectangle().stroke(.white.opacity(0.16)))
                                    .shadow(color: .black.opacity(0.65), radius: 8, x: 4, y: 8)

                            }
                            .frame(width: ListeningStyle.sleeveSize, height: ListeningStyle.sleeveSize + BSSpacing.md)
                            .contentShape(Rectangle())
                            .onTapGesture { showDetails(disc) }
                            // A short hold separates pulling a record from horizontal
                            // browsing of a cabinet with many albums.
                            .highPriorityGesture(LongPressGesture(minimumDuration: 0.18)
                                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("listeningRoom")))
                                .onChanged { value in
                                    guard case let .second(true, drag?) = value else { return }
                                    if !room.mechanism.isCabinetDragging { room.mechanism.beginCabinetDrag(disc) }
                                    guard room.mechanism.isCabinetDragging else { return }
                                    room.mechanism.dragDisc(CGSize(width: drag.translation.width / scale,
                                        height: drag.translation.height / scale / cos(room.mechanism.configuration.geometry.tiltDegrees * .pi / 180)))
                                }.onEnded { _ in room.mechanism.endDiscDrag() })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(disc.title)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { showDetails(disc) }
                            .accessibilityAction(named: BSLocalization.text("装入 CD")) { room.loadDisc(disc) }
                            HStack(spacing: BSSpacing.xs) {
                                if room.mechanism.disc?.id == disc.id { Circle().fill(BSColor.Stage.accent).frame(width: 4, height: 4) }
                                Text(disc.title).font(BSFont.V3.caption).lineLimit(1)
                            }.frame(width: ListeningStyle.sleeveSize, alignment: .leading).padding(.top, BSSpacing.sm)
                        }
                    }
                }.padding(.horizontal, BSSpacing.md).padding(.top, BSSpacing.sm).padding(.bottom, BSSpacing.md)
            }
            .frame(height: ListeningStyle.shelfHeight)
            .background(LinearGradient(colors: [BSColor.Stage.background, ListeningStyle.woodShadow], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottom) {
                Rectangle().fill(LinearGradient(colors: [ListeningStyle.woodEdge, ListeningStyle.woodShadow], startPoint: .top, endPoint: .bottom)).frame(height: BSSpacing.compact)
            }
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
            
            .listeningFrame("cabinet")
        }
        .disabled(room.mechanism.isAutomatic)
    }
}
