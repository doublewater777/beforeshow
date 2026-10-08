import SwiftUI

/// One row of standing CD cases. Swiping browses, tapping the pulled-out case opens its details,
/// holding it lets its disc be dragged into the player,
/// and the name plate unfolds that artist's discs in place or scrubs the row when dragged.
struct ListeningRackView: View {
    @Bindable var room: ListeningRoomCoordinator
    let groups: [ListeningRackGroup]
    let scale: CGFloat
    let onConnect: (Int, String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedGroupID: String?
    @State private var focusedID: String?
    @State private var dragOffset: CGFloat = 0
    @State private var scrubOrigin: Int?
    @State private var isDragging = false
    @State private var carriedDisc: ListeningDisc?

    private struct Item: Identifiable {
        let id: String
        let group: ListeningRackGroup
        let disc: ListeningDisc?
        let title: String
    }

    private var expandedGroup: ListeningRackGroup? {
        groups.first { $0.id == expandedGroupID }
    }

    private var items: [Item] {
        if let group = expandedGroup {
            guard !group.discs.isEmpty else { return [headItem(group)] }
            return group.discs.map { Item(id: "\(group.id)/\($0.id)", group: group, disc: $0, title: $0.title) }
        }
        return groups.map(headItem)
    }

    private func headItem(_ group: ListeningRackGroup) -> Item {
        Item(id: "\(group.id)/\(group.head?.id ?? "empty")", group: group, disc: group.head, title: group.name)
    }

    private var focusIndex: Int {
        items.firstIndex { $0.id == focusedID } ?? 0
    }

    private var progress: CGFloat {
        CGFloat(focusIndex) - dragOffset / ListeningRackLayout.step
    }

    private var focused: Item? {
        items.indices.contains(focusIndex) ? items[focusIndex] : nil
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    var body: some View {
        VStack(spacing: BSSpacing.xs) {
            GeometryReader { proxy in
                let mid = proxy.size.width / 2
                ZStack(alignment: .bottom) {
                    ListeningRackFloor()
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let d = CGFloat(index) - progress
                        if abs(d) < ListeningRackLayout.visibleRange {
                            ListeningRackCase(
                                disc: item.disc,
                                title: item.title,
                                artworkURL: item.group.artworkURL,
                                isLive: item.group.kind == .live,
                                isLoaded: isLoaded(item.disc),
                                showsDisc: index == focusIndex && !isDragging && scrubOrigin == nil && carriedDisc == nil,
                                show: room.show,
                                d: d
                            )
                            .zIndex(Double(100 - abs(d) * 10))
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(browseGesture)
                .gesture(carryGesture(mid: mid))
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                        guard carriedDisc == nil, !isDragging else { return }
                        tap(at: value.location.x - mid)
                    }
                )
            }
            .frame(height: ListeningRackLayout.rackHeight)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.1),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            plate
        }
        .sensoryFeedback(.selection, trigger: focusedID)
        .onChange(of: items.map(\.id), initial: true) { _, ids in
            if focusedID == nil || !ids.contains(focusedID ?? "") {
                focusedID = initialFocusID(in: ids)
            }
        }
        .accessibilityIdentifier("listening.rack")
    }

    // MARK: Plate

    @ViewBuilder
    private var plate: some View {
        if let item = focused {
            let group = item.group
            HStack(spacing: BSSpacing.xs) {
                if expandedGroup != nil {
                    Image(systemName: "chevron.left").foregroundStyle(BSColor.Stage.accent)
                }
                Text(group.name)
                    .lineLimit(1)
                if expandedGroup == nil, group.canExpand || isLoadingArtist(group) {
                    Image(systemName: "chevron.right").foregroundStyle(BSColor.Stage.accent)
                }
                if case let .artist(_, _, isConnected) = group.kind, !isConnected {
                    Image(systemName: "link").foregroundStyle(BSColor.Stage.accent)
                }
            }
            .font(ListeningRackLayout.plateFont)
            .tracking(0.6)
            .imageScale(.small)
            .foregroundStyle(ListeningStyle.plateInk)
            .padding(.horizontal, BSSpacing.compact + 2)
            .frame(height: ListeningRackLayout.plateHeight)
            .background(
                Capsule().fill(LinearGradient(colors: [ListeningStyle.plateTop, ListeningStyle.plateBottom], startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(scrubOrigin == nil ? 0.22 : 0.6), lineWidth: 1))
            .overlay(Capsule().inset(by: 1).stroke(.white.opacity(0.06), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
            .shadow(color: .black.opacity(0.45), radius: 9, y: 8)
            .scaleEffect(scrubOrigin == nil ? 1 : 1.06)
            .animation(.easeOut(duration: 0.18), value: scrubOrigin == nil)
            .frame(minHeight: BSLayout.minTouchTarget)
            .contentShape(Rectangle())
            .onTapGesture { togglePlate(group) }
            .gesture(scrubGesture)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("listening.rack.plate")
        }
    }

    private func togglePlate(_ group: ListeningRackGroup) {
        if expandedGroup != nil {
            withAnimation(motion) {
                expandedGroupID = nil
                focusedID = headItem(group).id
            }
            room.selectScope(.all)
            return
        }
        if case let .artist(_, slotIndex, isConnected) = group.kind, !isConnected {
            onConnect(slotIndex, group.name)
            return
        }
        guard group.canExpand || isLoadingArtist(group) else { return }
        withAnimation(motion) { expandedGroupID = group.id }
        room.selectScope(group.scope)
    }

    private func isLoadingArtist(_ group: ListeningRackGroup) -> Bool {
        if case let .artist(_, _, isConnected) = group.kind { return isConnected && group.discs.isEmpty }
        return false
    }

    // MARK: Gestures

    private var browseGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard carriedDisc == nil else { return }
                if !isDragging { isDragging = true }
                dragOffset = rubberBanded(value.translation.width)
            }
            .onEnded { value in
                guard carriedDisc == nil else { return }
                isDragging = false
                let target = CGFloat(focusIndex) - value.predictedEndTranslation.width / ListeningRackLayout.step
                let index = min(max(Int(target.rounded()), 0), max(items.count - 1, 0))
                withAnimation(motion) {
                    focusedID = items.indices.contains(index) ? items[index].id : focusedID
                    dragOffset = 0
                }
            }
    }

    /// Press and hold the pulled-out case, then drag its disc down into the player.
    private func carryGesture(mid: CGFloat) -> ListeningRackCarryRecognizer {
        ListeningRackCarryRecognizer(
            onBegan: { location in
                guard abs(location.x - mid) < ListeningRackLayout.caseSize / 2,
                      let disc = focused?.disc, !isLoaded(disc),
                      room.beginCabinetDragIfNeeded(disc) else { return }
                carriedDisc = disc
                dragOffset = 0
            },
            onChanged: { translation in
                guard let disc = carriedDisc else { return }
                room.updateCabinetDrag(of: disc, translation: translation, scale: scale)
            },
            onEnded: {
                guard let disc = carriedDisc else { return }
                room.endCabinetDrag(of: disc)
                carriedDisc = nil
            }
        )
    }

    /// Past either end the row resists instead of sliding into empty shelf.
    private func rubberBanded(_ translation: CGFloat) -> CGFloat {
        let step = ListeningRackLayout.step
        let position = CGFloat(focusIndex) - translation / step
        let last = CGFloat(max(items.count - 1, 0))
        let overshoot = position < 0 ? position : position > last ? position - last : 0
        guard overshoot != 0 else { return translation }
        let damped = overshoot / (1 + abs(overshoot) * 2)
        return (CGFloat(focusIndex) - (position - overshoot + damped)) * step
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let origin = scrubOrigin ?? focusIndex
                if scrubOrigin == nil { scrubOrigin = origin }
                let index = min(max(origin + Int((value.translation.width / ListeningRackLayout.scrubStep).rounded()), 0), max(items.count - 1, 0))
                guard items.indices.contains(index), items[index].id != focusedID else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.9)) {
                    focusedID = items[index].id
                }
            }
            .onEnded { _ in scrubOrigin = nil }
    }

    private func tap(at x: CGFloat) {
        let candidates = items.indices.filter { abs(CGFloat($0) - progress) < 3.5 }
        guard let index = candidates.min(by: {
            abs(ListeningRackLayout.visualCenter(CGFloat($0) - progress) - x)
                < abs(ListeningRackLayout.visualCenter(CGFloat($1) - progress) - x)
        }) else { return }
        guard index == focusIndex else {
            withAnimation(motion) { focusedID = items[index].id }
            return
        }
        let item = items[index]
        if let disc = item.disc {
            room.browser.open(disc)
        } else if case let .artist(_, slotIndex, isConnected) = item.group.kind, !isConnected {
            onConnect(slotIndex, item.group.name)
        } else {
            room.selectScope(item.group.scope)
        }
    }

    private func isLoaded(_ disc: ListeningDisc?) -> Bool {
        guard let disc else { return false }
        let hardware = room.display.hardware
        return hardware.discID == disc.id && hardware.position != .stored
    }

    private func initialFocusID(in ids: [String]) -> String? {
        if let discID = room.display.hardware.discID,
           let match = items.first(where: { $0.disc?.id == discID }) {
            return match.id
        }
        return ids.first
    }
}

// MARK: - Layout

enum ListeningRackLayout {
    static let caseSize: CGFloat = 124
    static let spine: CGFloat = 18
    static let rackHeight: CGFloat = 148
    static let slotHeight: CGFloat = rackHeight + BSSpacing.xs + BSLayout.minTouchTarget
    static let step: CGFloat = 52
    static let scrubStep: CGFloat = 12
    static let visibleRange: CGFloat = 4.5
    static let peek: CGFloat = 30
    static let sideScale: CGFloat = 0.88
    static let lift: CGFloat = 10
    static let lipHeight: CGFloat = 9
    static let floorDepth: CGFloat = 26
    static let plateHeight: CGFloat = 28
    static let plateFont = Font.system(size: 12, weight: .semibold)

    /// Spine x for a case `d` positions away from the focus; the first neighbour clears the pulled-out cover.
    static func x(_ d: CGFloat) -> CGFloat {
        let a = abs(d), side: CGFloat = d < 0 ? -1 : 1
        let first = caseSize / 2 + spine + 22 + (d > 0 ? peek : 0)
        let value = a <= 1 ? first * a : first + (a - 1) * (56 + (a - 1) * 4)
        return side * value
    }

    static func angle(_ d: CGFloat) -> Double {
        let a = Double(abs(d))
        return a <= 1 ? 58 * a : max(42, 58 - (a - 1) * 6)
    }

    static func visualCenter(_ d: CGFloat) -> CGFloat {
        abs(d) < 0.5 ? 0 : x(d) - (d < 0 ? -1 : 1) * min(abs(x(d)) * 0.12, 22)
    }
}

// MARK: - Case

private struct ListeningRackCase: View {
    let disc: ListeningDisc?
    let title: String
    let artworkURL: URL?
    let isLive: Bool
    let isLoaded: Bool
    let showsDisc: Bool
    let show: Show?
    let d: CGFloat
    @State private var tone: UIColor?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias L = ListeningRackLayout

    private var toneURL: URL? { disc?.artworkURL ?? artworkURL }

    var body: some View {
        let a = abs(d)
        let c = max(0, 1 - a)
        let side: CGFloat = d < 0 ? -1 : 1
        let x = L.x(d)
        let size = L.caseSize
        let coverCenter = x - side * (L.spine / 2 + size / 2) * (1 - c)
        let angle = L.angle(d) * Double(side < 0 ? 1 : -1)

        ZStack {
            if let disc, !isLoaded, c > 0.5 {
                ListeningPeekingDisc(disc: disc, size: size * 0.9)
                    .offset(x: coverCenter + (showsDisc ? L.peek : -size * 0.3))
                    .opacity(showsDisc ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82).delay(showsDisc ? 0.12 : 0), value: showsDisc)
            }

            cover
                .frame(width: size, height: size)
                .overlay { sideShade(side: side).opacity(Double(min(a, 1))) }
                .overlay { ListeningJewelCaseFinish().opacity(Double(c)) }
                .rotation3DEffect(
                    .degrees(angle),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: side < 0 ? .leading : .trailing,
                    perspective: 0.55
                )
                .modifier(CaseShadow(isActive: c > 0.5))
                .modifier(SlotFrame(id: c > 0.5 ? disc?.id : nil))
                .offset(x: coverCenter)

            spineView
                .frame(width: L.spine * (1 - c), height: size)
                .offset(x: x)
                .opacity(Double(min(a * 1.6, 1)))
        }
        .scaleEffect(L.sideScale + (1 - L.sideScale) * c, anchor: .bottom)
        .offset(y: -L.lift * c - L.lipHeight)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .task(id: toneURL) {
            tone = ListeningArtworkTone.cached(toneURL)
            if tone == nil, let toneURL { tone = await ListeningArtworkTone.tone(for: toneURL) }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let disc {
            ListeningDiscCover(disc: disc, show: show)
        } else {
            ListeningArtwork(url: artworkURL, title: title)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
        }
    }

    /// The far edge of a standing case falls into the shelf's shadow.
    private func sideShade(side: CGFloat) -> some View {
        LinearGradient(
            colors: [.black.opacity(0.05), .black.opacity(0.55)],
            startPoint: side < 0 ? .leading : .trailing,
            endPoint: side < 0 ? .trailing : .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
    }

    private var spineStyle: (fill: Color, ink: Color) {
        if isLive { return (ListeningStyle.liveSpine, BSColor.Stage.accent) }
        guard let tone else { return (BSColor.Stage.surfaceRaised, BSColor.Stage.foreground.opacity(0.86)) }
        let spine = ListeningArtworkTone.spine(for: tone)
        return (Color(uiColor: spine.fill), spine.isLight ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(0.92))
    }

    private var spineView: some View {
        let style = spineStyle
        return Rectangle()
            .fill(style.fill)
            .overlay {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(style.ink)
                    .lineLimit(1)
                    .frame(width: L.caseSize - 28)
                    .rotationEffect(.degrees(90))
            }
            .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.18)).frame(height: 6) }
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.18)).frame(height: 6) }
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.22)).frame(width: 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(.black.opacity(0.35)).frame(width: 1) }
            .clipped()
    }
}

/// A UIKit long press keeps taps and horizontal swipes on the row responsive.
struct ListeningRackCarryRecognizer: UIGestureRecognizerRepresentable {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    final class Coordinator {
        var origin: CGPoint = .zero
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.3
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began:
            context.coordinator.origin = location
            onBegan(location)
        case .changed:
            let origin = context.coordinator.origin
            onChanged(CGSize(width: location.x - origin.x, height: location.y - origin.y))
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}

private struct CaseShadow: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        if isActive {
            content.shadow(color: .black.opacity(0.55), radius: 18, y: 12)
        } else {
            content
        }
    }
}

private struct SlotFrame: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id {
            content.listeningFrame("slot:\(id)")
        } else {
            content
        }
    }
}

/// Receding shelf floor and its front lip.
struct ListeningRackFloor: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [ListeningStyle.rackFloorBack, ListeningStyle.rackFloorFront],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay {
                RadialGradient(
                    colors: [ListeningStyle.rackLight.opacity(0.1), .clear],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: 180
                )
            }
            .frame(height: ListeningRackLayout.floorDepth)
            LinearGradient(colors: [ListeningStyle.rackLipTop, ListeningStyle.rackLipBottom], startPoint: .top, endPoint: .bottom)
                .frame(height: ListeningRackLayout.lipHeight)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
        }
        .allowsHitTesting(false)
    }
}

/// Loading stand-in with the rack's own geometry: an empty shelf, blank cases and a blank plate.
struct ListeningRackSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    private typealias L = ListeningRackLayout

    var body: some View {
        VStack(spacing: BSSpacing.xs) {
            ZStack(alignment: .bottom) {
                ListeningRackFloor()
                ForEach([-3, -2, -1, 1, 2, 3], id: \.self) { d in
                    Rectangle()
                        .fill(BSColor.Stage.surfaceRaised)
                        .frame(width: L.spine, height: L.caseSize)
                        .scaleEffect(L.sideScale, anchor: .bottom)
                        .offset(x: L.x(CGFloat(d)), y: -L.lipHeight)
                }
                RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                    .fill(BSColor.Stage.surfaceRaised)
                    .frame(width: L.caseSize, height: L.caseSize)
                    .offset(y: -L.lift - L.lipHeight)
            }
            .frame(height: L.rackHeight, alignment: .bottom)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.1),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            Capsule()
                .fill(BSColor.Stage.surfaceRaised)
                .frame(width: 96, height: L.plateHeight)
                .frame(height: BSLayout.minTouchTarget)
        }
        .opacity(dim ? 0.55 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityHidden(true)
    }
}
