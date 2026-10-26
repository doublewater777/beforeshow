import SwiftUI
import simd

/// One row of standing CD cases. Swiping browses, tapping the pulled-out case opens its details,
/// holding it lets its disc be dragged into the player,
/// and the name plate unfolds that artist's discs in place or scrubs the row when dragged.
struct ListeningRackView: View {
    @Bindable var room: ListeningRoomCoordinator
    let groups: [ListeningRackGroup]
    let scale: CGFloat
    let onConnect: (Int, String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: ListeningRackPosition
    @State private var revealedID: String?
    @State private var placeholderGroupID: String?
    @State private var scrubOrigin: Int?
    @State private var carriedDisc: ListeningDisc?
    @State private var carriedFrame = CGRect.zero
    @State private var carryScale: CGFloat = 1
    @State private var carryOffset: CGSize = .zero
    /// Cases the row has travelled under the finger, fractional while a swipe is in flight.
    @State private var dragShift: Double = 0

    init(room: ListeningRoomCoordinator, groups: [ListeningRackGroup], scale: CGFloat,
         onConnect: @escaping (Int, String) -> Void) {
        self.room = room
        self.groups = groups
        self.scale = scale
        self.onConnect = onConnect
        _position = State(initialValue: ListeningRackPosition(showID: room.show?.id))
    }

    private typealias L = ListeningRackLayout

    private struct Entry: Identifiable {
        let id: String
        let groupIndex: Int
        let index: Int
        let group: ListeningRackGroup
        let disc: ListeningDisc?
        let isPlaceholder: Bool
    }

    // MARK: Model

    private var openIndex: Int? {
        groups.firstIndex { $0.id == position.expandedGroupID }
    }

    /// A single-artist show lays every disc on the row; there is nothing to unfold.
    private var flatArtist: ListeningRackGroup? {
        let artists = groups.filter { if case .artist = $0.kind { true } else { false } }
        return artists.count == 1 ? artists[0] : nil
    }

    private func showsPlaceholders(_ group: ListeningRackGroup) -> Bool {
        (group.id == position.expandedGroupID || group.id == flatArtist?.id) && group.catalogStatus == .loading && group.discs.count <= 1
    }

    private func headID(for group: ListeningRackGroup) -> String? {
        guard let index = group.discs.firstIndex(where: { $0.id == group.head?.id }) else { return nil }
        return "\(group.id)#\(index)"
    }

    /// Every case that could be on screen; ids are positional so a blank case turns into the album that fills it.
    private var entries: [Entry] {
        groups.enumerated().flatMap { gi, group in
            var discs: [ListeningDisc?] = group.discs.isEmpty ? [nil] : group.discs
            let real = discs.count
            if showsPlaceholders(group) { discs += Array(repeating: nil, count: L.placeholderCount) }
            return discs.enumerated().map { index, disc in
                Entry(id: "\(group.id)#\(index)", groupIndex: gi, index: index, group: group, disc: disc, isPlaceholder: index >= real)
            }
        }
    }

    /// The row in view: one head per group, or the open group's discs.
    private func row(_ entries: [Entry]) -> [Entry] {
        if flatArtist != nil {
            return entries.filter { !$0.isPlaceholder || placeholderGroupID == $0.group.id }
        }
        guard let open = openIndex else {
            return entries.filter { $0.id == headID(for: $0.group) || ($0.group.head == nil && $0.index == 0) }
        }
        return entries.filter { $0.groupIndex == open && (!$0.isPlaceholder || placeholderGroupID == position.expandedGroupID) }
    }

    private func focusableCount(_ row: [Entry]) -> Int {
        row.filter { !$0.isPlaceholder }.count
    }

    private func focusIndex(_ row: [Entry]) -> Int {
        row.firstIndex { $0.id == position.focusedID } ?? 0
    }

    private func isLoaded(_ disc: ListeningDisc?) -> Bool {
        guard let disc else { return false }
        let hardware = room.display.hardware
        return hardware.discID == disc.id && hardware.position != .stored
    }

    private func discOut(_ entry: Entry?) -> Bool {
        guard let entry, let disc = entry.disc else { return false }
        return !isLoaded(disc)
    }

    private func title(_ entry: Entry) -> String {
        guard !entry.isPlaceholder else { return "" }
        return openIndex == nil && flatArtist == nil ? entry.group.name : entry.disc?.title ?? entry.group.name
    }

    private func pose(_ entry: Entry, row: [Entry], focus c: Int, discOut: Bool) -> ListeningRackPose {
        var pose: ListeningRackPose
        if let pos = row.firstIndex(where: { $0.id == entry.id }) {
            pose = L.pose(following: Double(pos - c) + dragShift, discOut: discOut)
            if pos == c, dragShift == 0, revealedID == entry.id, discOut { pose.peek = L.peekOut }
            return pose
        }
        if let open = openIndex, entry.groupIndex != open {
            pose = L.away(side: entry.groupIndex < open ? -1 : 1)
        } else {
            let head = openIndex == nil ? entry.groupIndex : 0
            pose = L.pose(at: head - c, discOut: discOut)
            pose.opacity = 0
        }
        pose.z -= 40
        return pose
    }

    /// Cases near the focus, plus the ones about to fly out or unfold, so they persist across the change.
    private func rendered(_ entries: [Entry], row: [Entry], focus c: Int) -> [Entry] {
        let rowIDs = Dictionary(row.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let focusGroup = row.indices.contains(c) ? row[c].groupIndex : nil
        let anchor = openIndex ?? focusGroup ?? 0
        return entries.filter { entry in
            if let pos = rowIDs[entry.id] { return abs(pos - c) <= L.renderReach }
            if openIndex != nil { return entry.id == headID(for: entry.group) && abs(entry.groupIndex - anchor) <= L.renderReach }
            return entry.groupIndex == focusGroup && (entry.id == headID(for: entry.group) || entry.index <= L.renderReach)
        }
    }

    private var motion: Animation? {
        reduceMotion ? nil : scrubOrigin == nil ? L.motion : L.scrubMotion
    }

    // MARK: Body

    var body: some View {
        let entries = entries
        let row = row(entries)
        let c = focusIndex(row)
        let focused = row.indices.contains(c) ? row[c] : nil
        let out = carriedDisc != nil || discOut(focused)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    ListeningRackFloor(width: width)
                    ForEach(rendered(entries, row: row, focus: c)) { entry in
                        let pose = pose(entry, row: row, focus: c, discOut: out)
                        ListeningRackCase(
                            pose: pose,
                            content: ListeningRackCaseContent(
                                disc: entry.disc,
                                title: title(entry),
                                artworkURL: entry.group.artworkURL,
                                isLive: entry.group.kind == .live,
                                isPlaceholder: entry.isPlaceholder,
                                marked: entry.id == headID(for: entry.group) && openIndex == entry.groupIndex && entry.group.discs.count > 1,
                                showsDisc: entry.id == focused?.id && out && carriedDisc == nil
                            ),
                            width: width,
                            show: room.show
                        )
                        .modifier(ListeningRackBreathing(isActive: entry.isPlaceholder && !reduceMotion))
                        .zIndex(100 - abs(Double((row.firstIndex { $0.id == entry.id } ?? 50) - c) + dragShift))
                    }
                    if let disc = focused?.disc, out {
                        slotMarker(for: disc, width: width, focus: c, row: row)
                    }
                }
                .animation(motion, value: entries.map(\.id))
                .animation(motion, value: out)
                .frame(width: width, height: proxy.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(swipeGesture(row: row, focus: c))
                .modifier(carryGesture(width: width, focused: focused,
                                      pose: focused.map { pose($0, row: row, focus: c, discOut: out) }))
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                        guard carriedDisc == nil else { return }
                        tap(atX: value.location.x - width / 2, row: row, focus: c, discOut: out, halfWidth: width / 2)
                    }
                )
            }
            .frame(height: L.canvasHeight)
            .modifier(ListeningRackEdgeFade())
            .overlay(alignment: .topLeading) {
                GeometryReader { _ in
                    if isSwapCarry, let disc = carriedDisc {
                        let geometry = room.hardwareGeometry
                        let diameter = geometry.discDiameter * scale
                        ListeningDiscArtwork(disc: disc, image: room.playerConfiguration.assets.disc)
                            .frame(width: diameter, height: diameter)
                            .scaleEffect(x: carryScale, y: carryScale * cos(geometry.tiltDegrees * .pi / 180))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 4)
                            .position(x: carriedFrame.midX + carryOffset.width,
                                      y: carriedFrame.midY + carryOffset.height)
                            .allowsHitTesting(false)
                            .onAppear {
                                withAnimation(reduceMotion ? nil : L.motion) { carryScale = 1 }
                            }
                    }
                }
            }
            .zIndex(isSwapCarry ? 1 : 0)

            if let focused {
                plate(for: focused, row: row, focus: c)
            }
        }
        .zIndex(isSwapCarry ? 1 : 0)
        .sensoryFeedback(.selection, trigger: position.focusedID)
        .onChange(of: row.map(\.id), initial: true) { _, ids in
            guard position.focusedID == nil || !ids.contains(position.focusedID ?? "") else { return }
            position.focusedID = initialFocusID(in: row)
            revealedID = position.focusedID
        }
        .onChange(of: groups.map(\.id)) { _, ids in
            // A rematched artist takes a new identity; fall back to the shelf of heads.
            guard let id = position.expandedGroupID, !ids.contains(id) else { return }
            withAnimation(reduceMotion ? nil : L.motion) {
                position.expandedGroupID = nil
                room.selectScope(.all)
            }
        }
        .onAppear {
            position.refreshDayIfNeeded()
            if position.focusedID == nil { position.focusedID = initialFocusID(in: row) }
            if case .artist = room.browser.scope,
               let group = groups.first(where: { $0.scope == room.browser.scope }) {
                position.expandedGroupID = group.id
            } else if let group = groups.first(where: { $0.id == position.expandedGroupID }) {
                room.selectScope(group.scope)
            }
            revealedID = position.focusedID
        }
        .onChange(of: room.browser.scope) { _, scope in
            guard case .artist = scope else {
                position.expandedGroupID = nil
                return
            }
            guard let group = groups.first(where: { $0.scope == scope }) else { return }
            guard position.expandedGroupID != group.id else { return }
            position.expandedGroupID = group.id
            position.focusedID = headID(for: group) ?? "\(group.id)#0"
            revealedID = position.focusedID
        }
        .onChange(of: position.focusedID) { _, id in
            withAnimation(reduceMotion ? nil : L.motion.delay(L.discDelay)) { revealedID = id }
        }
        .task(id: position.focusedID) { await prefetch(focused) }
        .task(id: position.expandedGroupID ?? flatArtist?.id) {
            placeholderGroupID = nil
            if let flatArtist, flatArtist.isConnectedArtist, case let .artist(id, _, _) = flatArtist.kind {
                room.loadArtistCatalogIfNeeded(id)
            }
            guard let id = position.expandedGroupID ?? flatArtist?.id else { return }
            try? await Task.sleep(for: L.placeholderDelay)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : L.motion) { placeholderGroupID = id }
        }
        .accessibilityIdentifier("listening.rack")
    }

    /// Reports where the pulled-out disc sits, so the player can fly it in from there.
    private func slotMarker(for disc: ListeningDisc, width: CGFloat, focus c: Int, row: [Entry]) -> some View {
        var pose = L.pose(at: 0, discOut: true)
        pose.peek = L.peekOut
        let transform = ListeningRackProjector(width: width).box(pose) * ListeningRackFace.disc(peek: pose.peek)
        let rect = ListeningRackProjector.bounds(transform, size: CGSize(width: L.discSize, height: L.discSize)) ?? .zero
        return Color.clear
            .frame(width: rect.width, height: rect.height)
            .listeningFrame("slot:\(disc.id)")
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }

    // MARK: Plate

    private func plate(for entry: Entry, row: [Entry], focus c: Int) -> some View {
        let group = entry.group
        let expanded = openIndex != nil
        let showsCatalogStatus = expanded || group.id == flatArtist?.id
        let scrubbing = scrubOrigin != nil
        return HStack(spacing: 6) {
            if expanded { chevron("chevron.left") }
            Text(group.name).lineLimit(1)
            if !expanded, flatArtist == nil, group.canExpand { chevron("chevron.right") }
            if case .artist(_, _, false) = group.kind { chevron("link") }
            if showsCatalogStatus, group.catalogStatus == .loading {
                ProgressView().controlSize(.mini).tint(BSColor.Stage.accent)
            }
            if showsCatalogStatus, group.catalogStatus == .failed, case let .artist(id, _, _) = group.kind {
                Button {
                    room.retryArtistCatalog(id)
                } label: {
                    chevron("arrow.clockwise").padding(BSSpacing.xs).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-BSSpacing.xs)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(ListeningStyle.plateInk)
        .padding(.horizontal, 12)
        .frame(height: L.plateHeight)
        .background(Capsule().fill(LinearGradient(colors: [ListeningStyle.plateTop, ListeningStyle.plateBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(BSColor.Stage.accent.opacity(scrubbing ? 0.6 : 0.22), lineWidth: 1))
        .overlay(Capsule().inset(by: 1).stroke(.white.opacity(0.06), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
        .background(Capsule().inset(by: -4).fill(BSColor.Stage.accent.opacity(scrubbing ? 0.1 : 0)))
        .shadow(color: .black.opacity(0.45), radius: 9, y: 8)
        .overlay(alignment: .leading) { chevron("chevron.left").offset(x: -16).opacity(scrubbing ? 0.9 : 0) }
        .overlay(alignment: .trailing) { chevron("chevron.right").offset(x: 16).opacity(scrubbing ? 0.9 : 0) }
        .scaleEffect(scrubbing ? 1.06 : 1)
        .animation(.easeOut(duration: 0.2), value: scrubbing)
        .frame(height: BSLayout.minTouchTarget)
        .contentShape(Rectangle())
        .onTapGesture { togglePlate(group) }
        .gesture(scrubGesture(row: row, focus: c))
        .contextMenu {
            if case let .artist(_, slotIndex, true) = group.kind {
                Button(BSLocalization.text("重新匹配艺人"), systemImage: "arrow.triangle.2.circlepath") {
                    onConnect(slotIndex, group.name)
                }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("listening.rack.plate")
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(BSColor.Stage.accent)
    }

    private func togglePlate(_ group: ListeningRackGroup) {
        if openIndex != nil {
            withAnimation(reduceMotion ? nil : L.motion) {
                position.focusedID = headID(for: group) ?? "\(group.id)#0"
                position.expandedGroupID = nil
                room.selectScope(.all)
            }
            return
        }
        if case let .artist(_, slotIndex, false) = group.kind {
            onConnect(slotIndex, group.name)
            return
        }
        guard flatArtist == nil, group.canExpand else { return }
        withAnimation(reduceMotion ? nil : L.motion) {
            position.expandedGroupID = group.id
            position.focusedID = headID(for: group) ?? "\(group.id)#0"
            room.selectScope(group.scope)
        }
    }

    // MARK: Gestures

    /// With a CD already seated, the case's disc follows the finger itself until dropped.
    private var isSwapCarry: Bool { carriedDisc != nil && room.pendingCabinetSwap != nil }

    /// The row follows the finger at the mock's 44pt per case, then settles with a little of the flick.
    private func swipeGesture(row: [Entry], focus c: Int) -> some Gesture {
        DragGesture(minimumDistance: L.followThreshold)
            .onChanged { value in
                guard carriedDisc == nil,
                      dragShift != 0 || abs(value.translation.width) > abs(value.translation.height) else { return }
                let shift = L.followShift(from: c, translation: value.translation.width, count: focusableCount(row))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragShift = shift == 0 ? .ulpOfOne : shift }
            }
            .onEnded { value in
                guard carriedDisc == nil, dragShift != 0 else { return }
                let index = L.swipeIndex(
                    from: c,
                    translation: value.translation.width,
                    predicted: value.predictedEndTranslation.width,
                    count: focusableCount(row)
                )
                withAnimation(reduceMotion ? nil : L.motion) {
                    dragShift = 0
                    if row.indices.contains(index) { position.focusedID = row[index].id }
                }
            }
    }

    private func scrubGesture(row: [Entry], focus c: Int) -> some Gesture {
        DragGesture(minimumDistance: L.scrubThreshold)
            .onChanged { value in
                let origin = scrubOrigin ?? c
                if scrubOrigin == nil { scrubOrigin = origin }
                let index = L.scrubIndex(from: origin, translation: value.translation.width, count: focusableCount(row))
                guard row.indices.contains(index), row[index].id != position.focusedID else { return }
                withAnimation(reduceMotion ? nil : L.scrubMotion) { position.focusedID = row[index].id }
            }
            .onEnded { _ in scrubOrigin = nil }
    }

    /// Only the exposed part of the CD can be picked up; the case stays on the shelf.
    private func carryGesture(width: CGFloat, focused: Entry?, pose: ListeningRackPose?) -> ListeningRackCarryRecognizer {
        ListeningRackCarryRecognizer(
            onBegan: { location in
                guard let pose, let disc = focused?.disc, !isLoaded(disc) else { return }
                let box = ListeningRackProjector(width: width).box(pose)
                guard let discBounds = ListeningRackProjector.bounds(
                    box * ListeningRackFace.disc(peek: pose.peek),
                    size: CGSize(width: L.discSize, height: L.discSize)
                ), let coverBounds = ListeningRackProjector.bounds(
                    box * ListeningRackFace.right,
                    size: CGSize(width: L.caseSize, height: L.caseSize)
                ), !coverBounds.contains(location),
                      ListeningDiscDetailTapPolicy.contains(location,
                          center: CGPoint(x: discBounds.midX, y: discBounds.midY), size: discBounds.size),
                      room.beginCabinetDragIfNeeded(disc) else { return }
                carriedFrame = discBounds
                carryScale = discBounds.width / (room.hardwareGeometry.discDiameter * scale)
                carryOffset = .zero
                carriedDisc = disc
            },
            onChanged: { translation in
                guard let disc = carriedDisc else { return }
                if isSwapCarry { carryOffset = translation }
                room.updateCabinetDrag(of: disc, translation: translation, scale: scale)
            },
            onEnded: { cancelled in
                guard let disc = carriedDisc else { return }
                room.endCabinetDrag(of: disc, cancelled: cancelled)
                carriedDisc = nil
                withAnimation(reduceMotion ? nil : L.motion) { carryOffset = .zero }
            }
        )
    }

    private func tap(atX x: CGFloat, row: [Entry], focus c: Int, discOut: Bool, halfWidth: CGFloat) {
        guard let d = L.tapOffset(atX: x, focus: c, count: row.count, discOut: discOut, halfWidth: halfWidth) else { return }
        let entry = row[c + d]
        guard !entry.isPlaceholder else { return }
        guard d == 0 else {
            withAnimation(reduceMotion ? nil : L.motion) { position.focusedID = entry.id }
            return
        }
        if let disc = entry.disc {
            room.browser.open(disc)
        } else if case let .artist(_, slotIndex, false) = entry.group.kind {
            onConnect(slotIndex, entry.group.name)
        } else if openIndex == nil {
            togglePlate(entry.group)
        }
    }

    /// Resting on an artist starts their catalog, so unfolding is usually instant.
    private func prefetch(_ entry: Entry?) async {
        guard openIndex == nil, let group = entry?.group,
              group.isConnectedArtist, !group.hasCatalog,
              case let .artist(id, _, _) = group.kind else { return }
        try? await Task.sleep(for: L.prefetchDelay)
        guard !Task.isCancelled else { return }
        room.loadArtistCatalogIfNeeded(id)
    }

    private func initialFocusID(in row: [Entry]) -> String? {
        if let discID = room.display.hardware.discID,
           let match = row.first(where: { $0.disc?.id == discID }) {
            return match.id
        }
        if let oldGroupID = position.focusedID?.split(separator: "#").first,
           let sameGroup = row.first(where: { $0.group.id == String(oldGroupID) }) {
            return sameGroup.id
        }
        if let flatArtist, let featured = headID(for: flatArtist),
           row.contains(where: { $0.id == featured }) {
            return featured
        }
        return row.first?.id
    }
}

/// Blank cases breathe while their albums are on the way.
private struct ListeningRackBreathing: ViewModifier {
    let isActive: Bool
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && dim ? 0.55 : 1)
            .animation(isActive ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: dim)
            .onAppear { dim = true }
    }
}

/// A UIKit long press keeps taps and horizontal swipes on the row responsive.
@available(iOS 18, *)
private struct ListeningRackNativeCarryRecognizer: UIGestureRecognizerRepresentable {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: (Bool) -> Void

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
        case .ended:
            let origin = context.coordinator.origin
            onChanged(CGSize(width: location.x - origin.x, height: location.y - origin.y))
            onEnded(false)
        case .cancelled, .failed:
            onEnded(true)
        default:
            break
        }
    }
}

private struct ListeningRackCarryRecognizer: ViewModifier {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: (Bool) -> Void
    @State private var carrying = false
    @GestureState private var gestureActive = false

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.gesture(ListeningRackNativeCarryRecognizer(
                onBegan: onBegan, onChanged: onChanged, onEnded: onEnded
            ))
        } else {
            content.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3, maximumDistance: 10)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($gestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        guard case .second(true, let drag) = value, let drag else { return }
                        if !carrying {
                            carrying = true
                            onBegan(drag.startLocation)
                        }
                        onChanged(drag.translation)
                    }
                    .onEnded { value in
                        guard carrying else { return }
                        if case .second(true, let drag) = value {
                            if let drag { onChanged(drag.translation) }
                            onEnded(false)
                        } else {
                            onEnded(true)
                        }
                        carrying = false
                    }
            )
            .onChange(of: gestureActive) { _, active in
                guard !active, carrying else { return }
                onEnded(true)
                carrying = false
            }
            .onDisappear {
                if carrying { onEnded(true) }
                carrying = false
            }
        }
    }
}
