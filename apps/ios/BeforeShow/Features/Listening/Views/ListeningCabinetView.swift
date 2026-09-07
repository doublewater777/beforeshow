import SwiftUI

struct ListeningCabinetView: View {
    @Bindable var room: ListeningRoomCoordinator
    let scale: CGFloat
    let showAll: () -> Void
    let showDetails: (ListeningDisc) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack {
                Text(BSLocalization.text("唱片柜")).font(BSFont.headline)
                Spacer()
                Button(action: showAll) {
                    HStack(spacing: BSSpacing.xs) {
                        Text(BSLocalization.text("全部"))
                        Image(systemName: "chevron.right")
                    }.font(BSFont.caption)
                        .frame(minHeight: BSLayout.minTouchTarget)
                }
                .foregroundStyle(BSColor.Stage.muted)
                .accessibilityLabel(BSLocalization.text("全部唱片"))
                .accessibilityIdentifier("listening.allDiscs")
            }
            ListeningShelf {
                ForEach(Array(room.discs.enumerated()), id: \.element.id) { index, disc in
                    ListeningCompartment(showsLeadingDivider: index == 0) {
                        ListeningSleeve(disc: disc,
                                        isLoaded: room.mechanism.disc?.id == disc.id && room.mechanism.position != .stored,
                                        registersSlot: true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showDetails(disc) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(disc.title)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { showDetails(disc) }
                    .accessibilityAction(named: BSLocalization.text("装入 CD")) { room.loadDisc(disc) }
                }
            }
            .listeningFrame("cabinet")
        }
        .disabled(room.mechanism.isAutomatic)
    }
}

/// A compartmentalized cubby with vertical wooden partitions.
struct ListeningCompartment<Content: View>: View {
    let showsLeadingDivider: Bool
    @ViewBuilder let content: () -> Content

    init(showsLeadingDivider: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.showsLeadingDivider = showsLeadingDivider
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsLeadingDivider {
                divider
            }
            content()
                .frame(width: ListeningStyle.compartmentWidth)
            divider
        }
    }

    private var divider: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ListeningStyle.woodHighlight,
                    ListeningStyle.woodEdge,
                    ListeningStyle.woodShadow
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            // Subtle vertical inner shadow on the wood divider sides
            LinearGradient(
                colors: [Color.black.opacity(0.65), Color.clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: ListeningStyle.dividerWidth)
        .frame(maxHeight: .infinity)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 0.75),
            alignment: .leading
        )
    }
}

/// One recessed wooden bay, shared by the player's cabinet and the artist shelves.
struct ListeningShelf<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 0, content: content)
                .padding(.horizontal, BSSpacing.sm)
                .padding(.top, BSSpacing.lg)
                .padding(.bottom, ListeningStyle.shelfLip + BSSpacing.compact)
        }
        .frame(height: ListeningStyle.shelfHeight)
        .background {
            // Cabinet cavity interior depth with rich wood backing
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: ListeningStyle.woodBack, location: 0.0),
                        .init(color: ListeningStyle.woodShadow, location: 0.4),
                        .init(color: ListeningStyle.woodFace.opacity(0.9), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Top ambient occlusion from the overhead shelf overhang
                LinearGradient(
                    colors: [Color.black.opacity(0.92), Color.black.opacity(0.40), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxHeight: .infinity, alignment: .top)

                // Left and right side-panel depth shadows
                HStack {
                    LinearGradient(colors: [Color.black.opacity(0.7), Color.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                    Spacer()
                    LinearGradient(colors: [Color.clear, Color.black.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                }

                // Bottom back ledge shadow where sleeves rest
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
        .overlay {
            // Outer beveled cabinet frame
            RoundedRectangle(cornerRadius: BSRadius.sm)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            ListeningStyle.woodHighlight,
                            ListeningStyle.woodEdge,
                            ListeningStyle.woodFace,
                            ListeningStyle.woodShadow
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: ListeningStyle.shelfFrame
                )
        }
        .overlay(alignment: .bottom) {
            // Solid front retention lip (wooden rail with brass highlight bead)
            VStack(spacing: 0) {
                // Brass/gold top lip edge catch light
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.6), ListeningStyle.woodHighlight, Color.black.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1.5)

                ZStack {
                    LinearGradient(
                        colors: [ListeningStyle.woodHighlight.opacity(0.75), ListeningStyle.woodEdge, ListeningStyle.woodShadow],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Canvas { context, size in
                        for row in stride(from: CGFloat(2), to: size.height, by: 2.5) {
                            var grain = Path()
                            grain.move(to: CGPoint(x: 0, y: row))
                            grain.addQuadCurve(
                                to: CGPoint(x: size.width, y: row),
                                control: CGPoint(x: size.width * 0.55, y: row + 1.8)
                            )
                            context.stroke(grain, with: .color(ListeningStyle.caseShadow.opacity(0.4)), lineWidth: 0.5)
                        }
                    }
                }
            }
            .frame(height: ListeningStyle.shelfLip)
            .padding(.horizontal, ListeningStyle.shelfFrame)
            .padding(.bottom, ListeningStyle.shelfFrame)
        }
        .shadow(color: Color.black.opacity(0.75), radius: 14, y: 8)
    }
}

/// A paper sleeve in front of a partly exposed, circular CD.
struct ListeningSleeve: View {
    let disc: ListeningDisc
    let isLoaded: Bool
    var registersSlot = false
    var body: some View {
        VStack(alignment: .center, spacing: BSSpacing.xs) {
            ZStack(alignment: .bottomLeading) {
                // CD disc exposed from the top-right of the sleeve (peeking out)
                Group {
                    if registersSlot {
                        discArtwork.listeningFrame("slot:\(disc.id)")
                    } else { discArtwork }
                }
                .offset(
                    x: ListeningStyle.sleeveWidth - ListeningStyle.shelfDiscSize - 2,
                    y: -BSSpacing.compact - 4
                )
                .opacity(isLoaded ? 0 : 1)

                // Front album cardboard jacket / sleeve
                ZStack {
                    ListeningArtwork(url: disc.artworkURL, title: disc.title)
                        .frame(width: ListeningStyle.sleeveSize, height: ListeningStyle.sleeveSize)

                    // Cardboard spine left fold crease
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.black.opacity(0.5),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Diagonal paper sheen / satin laminate finish
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.12), location: 0.0),
                            .init(color: Color.clear, location: 0.35),
                            .init(color: Color.clear, location: 0.85),
                            .init(color: Color.black.opacity(0.20), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Right slot cutout rim (where disc slides out)
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
                .frame(width: ListeningStyle.sleeveSize, height: ListeningStyle.sleeveSize)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                )
                // Jacket cast shadow onto shelf backdrop and neighboring records
                .shadow(color: Color.black.opacity(0.75), radius: 6, x: 2, y: 5)
            }
            .frame(width: ListeningStyle.sleeveWidth, height: ListeningStyle.sleeveHeight, alignment: .bottomLeading)

            HStack(spacing: BSSpacing.xs) {
                if isLoaded {
                    Circle()
                        .fill(BSColor.Stage.accent)
                        .frame(width: 5, height: 5)
                }
                Text(disc.title)
                    .font(BSFont.V3.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(BSColor.Stage.heroIvory)
            }
            .frame(maxWidth: ListeningStyle.sleeveWidth, alignment: .center)
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    private var discArtwork: some View {
        ListeningDiscArtwork(disc: disc)
            .frame(width: ListeningStyle.shelfDiscSize, height: ListeningStyle.shelfDiscSize)
            .shadow(color: Color.black.opacity(0.8), radius: 5, x: 2, y: 3)
    }
}
