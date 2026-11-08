import MapKit
import SwiftData
import SwiftUI

/// Wide modules take a row. Square ones pair up where the first one stands; a square with no
/// partner becomes a slim strip in its own place, so the lifecycle order stays as given.
enum CurrentShowInlineLayout {
    enum Row: Hashable {
        case wide(CurrentShowQuickAction)
        case strip(CurrentShowQuickAction)
        case pair(CurrentShowQuickAction, CurrentShowQuickAction)
    }

    static func rows(for actions: [CurrentShowQuickAction]) -> [Row] {
        var rows: [Row] = []
        var used = Set<Int>()
        for (index, action) in actions.enumerated() where !used.contains(index) {
            if isWide(action) {
                rows.append(.wide(action))
            } else if let partner = actions.indices.first(where: { $0 > index && !used.contains($0) && !isWide(actions[$0]) }) {
                used.insert(partner)
                rows.append(.pair(action, actions[partner]))
            } else {
                rows.append(.strip(action))
            }
        }
        return rows
    }

    private static func isWide(_ action: CurrentShowQuickAction) -> Bool {
        switch action {
        case .route, .timetable, .endShow, .ticket, .memoryFragments: true
        default: false
        }
    }
}

/// The show's tools, each its own glass module carrying its own content: the ticket screenshot,
/// who's coming, the latest memories. Wide modules take a row; the rest pair up.
struct CurrentShowActionModules: View {
    let show: Show
    let actions: [CurrentShowQuickAction]
    let companion: CompanionQuickActionPresentation
    var now: Date = .now
    /// Before doors the route is the job of the day: a full map. Once there, a slim strip.
    var routeIsProminent = false
    /// Live mode already lists who's next; the timetable module is then just the way in.
    var timetableIsLive = false
    /// 模块下方接「歌单 / 此刻 / 留下的东西」记录行。
    var recordPhase: HomeShowPhase = .pre
    let perform: (CurrentShowQuickAction) -> Void

    @Query private var assets: [ShowAsset]
    @State private var memoryCaptureSource: MemoryCreateSourceOption?

    init(show: Show, actions: [CurrentShowQuickAction], companion: CompanionQuickActionPresentation, now: Date = .now, routeIsProminent: Bool = false, timetableIsLive: Bool = false, recordPhase: HomeShowPhase = .pre, perform: @escaping (CurrentShowQuickAction) -> Void) {
        self.timetableIsLive = timetableIsLive
        self.recordPhase = recordPhase
        self.show = show
        self.actions = actions
        self.companion = companion
        self.now = now
        self.routeIsProminent = routeIsProminent
        self.perform = perform
        let showID = show.id
        _assets = Query(filter: #Predicate<ShowAsset> { $0.showID == showID })
    }

    private var rows: [CurrentShowInlineLayout.Row] {
        let ordered = timetableIsLive ? actions.filter { $0 == .timetable } + actions.filter { $0 != .timetable } : actions
        return CurrentShowInlineLayout.rows(for: ordered)
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                switch row {
                case .wide(let action):
                    module(action)
                case .strip(let action):
                    stripModule(action)
                case .pair(let first, let second):
                    HStack(spacing: 12) {
                        module(first)
                        module(second)
                    }
                }
            }
            CurrentShowRecordSection(show: show, phase: recordPhase)
                .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func module(_ action: CurrentShowQuickAction) -> some View {
        if action == .memoryFragments {
            memoryModule
                .frame(maxWidth: .infinity, alignment: .leading)
                .bsGlassCard(cornerRadius: 24)
        } else {
            tappableModule(action)
        }
    }

    private func tappableModule(_ action: CurrentShowQuickAction) -> some View {
        Button { perform(action) } label: {
            Group {
                switch action {
                case .ticket: ticketModule
                case .timetable: timetableModule
                case .endShow: endModule
                case .companion: companionModule
                case .memoryFragments: EmptyView()
                case .route: CurrentShowRouteModule(show: show, isProminent: routeIsProminent)
                case .dispersal(let completed):
                    square(action, value: BSLocalization.text(completed ? "已记下" : "这一场怎么样"), note: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .bsGlassCard(cornerRadius: 24, tint: action == .endShow ? BSColor.Stage.live.opacity(0.12) : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action == .companion ? companion.accessibilityLabel : action.title)
    }

    private func stripModule(_ action: CurrentShowQuickAction) -> some View {
        let value: String = switch action {
        case .companion: companion.showsAvatars ? (companion.companionName ?? companion.displayTitle) : companion.displayTitle
        case .dispersal(let completed): BSLocalization.text(completed ? "已记下" : "这一场怎么样")
        default: ""
        }
        return Button { perform(action) } label: {
            HStack(spacing: 12) {
                if action == .companion, companion.showsAvatars {
                    CompanionAvatarStack(names: companion.companionNames)
                } else {
                    Image(systemName: action.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(0.85))
                        .frame(width: 30)
                }
                Text(action.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BSColor.Stage.dim)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .bsGlassCard(cornerRadius: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action == .companion ? companion.accessibilityLabel : action.title)
    }

    private func header(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(BSFont.Editorial.caps(13))
                .tracking(1.5)
                .foregroundStyle(BSColor.Stage.foreground)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(BSColor.Stage.muted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BSColor.Stage.dim)
        }
    }

    // MARK: Ticket

    private var ticketModule: some View {
        let ticket = assets.first { $0.kind == .ticket }
        return assetStrip(title: BSLocalization.text("票根"), isSaved: ticket != nil) {
            if let ticket {
                CurrentShowTicketThumbnail(asset: ticket)
            } else {
                Image(systemName: "ticket")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
            }
        }
    }

    /// Ticket and an empty timetable share one slim row: thumbnail, name, saved or not.
    private func assetStrip<Thumb: View>(title: String, isSaved: Bool, @ViewBuilder thumb: () -> Thumb) -> some View {
        HStack(spacing: 12) {
            thumb()
                .frame(width: 30, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: isSaved ? [] : [3, 3])))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            Spacer()
            Text(isSaved ? BSLocalization.text("已保存") : BSLocalization.text("存一张"))
                .font(.system(size: 12))
                .foregroundStyle(BSColor.Stage.muted)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BSColor.Stage.dim)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }

    // MARK: Timetable

    @ViewBuilder
    private var timetableModule: some View {
        if timetableIsLive {
            HStack(spacing: 12) {
                Image(systemName: CurrentShowQuickAction.timetable.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(BSColor.Stage.accent)
                    .frame(width: 30)
                Text(BSLocalization.text("完整时刻表"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                Text(BSLocalization.format("%lld 个舞台", Set(show.timetable?.orderedDays.flatMap(\.orderedStages).map(\.name) ?? []).count))
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BSColor.Stage.dim)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
        } else {
            upcomingTimetableModule
        }
    }

    @ViewBuilder
    private var upcomingTimetableModule: some View {
        let next = (show.timetable?.orderedDays.flatMap(\.performances) ?? [])
            .filter { $0.endsAt > now }
            .sorted(by: TimetablePerformance.chronologicalOrder)
            .prefix(3)
        if next.isEmpty {
            assetStrip(
                title: BSLocalization.text("时刻表"),
                isSaved: show.timetable != nil || assets.contains { $0.kind == .timetable }
            ) {
                Image(systemName: CurrentShowQuickAction.timetable.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
            }
        } else {
            upcomingPerformances(Array(next))
        }
    }

    private func upcomingPerformances(_ next: [TimetablePerformance]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(BSLocalization.text("时刻表"))
            ForEach(next) { perf in
                HStack(spacing: 10) {
                    Text(clock(perf.startsAt))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(BSColor.Stage.muted)
                    Text(perf.artistName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
    }

    // MARK: End show

    private var endModule: some View {
        HStack {
            Image(systemName: CurrentShowQuickAction.endShow.iconName)
                .foregroundStyle(BSColor.Stage.live)
            Text(CurrentShowQuickAction.endShow.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BSColor.Stage.liveTitle)
            Spacer()
            Text(BSLocalization.text("记下散场时间"))
                .font(.system(size: 12))
                .foregroundStyle(BSColor.Stage.muted)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BSColor.Stage.dim)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }

    // MARK: Squares

    private var companionModule: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(BSLocalization.text("同行"))
            Spacer(minLength: 12)
            if companion.showsAvatars {
                CompanionAvatarStack(names: companion.companionNames).scaleEffect(1.3, anchor: .leading)
            } else {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(BSColor.Stage.muted)
            }
            Spacer(minLength: 12)
            Text(companion.showsAvatars ? (companion.companionName ?? companion.displayTitle) : companion.displayTitle)
                .font(BSFont.Editorial.serif(19))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(1)
        }
        .padding(16)
        .frame(minHeight: 140)
    }

    /// The latest frames of the night, and the three ways to add one without leaving the page.
    private var memoryModule: some View {
        let moments = MemoryMomentTimeline.moments(from: show.memoryFragments)
        let recent = Array(moments.suffix(4).reversed())
        return VStack(alignment: .leading, spacing: 12) {
            Button { perform(.memoryFragments) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    header(BSLocalization.text("记忆碎片"), trailing: moments.isEmpty ? nil : MemoryMomentTimeline.countText(moments.count))
                    if !recent.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { index in
                                Group {
                                    if index < recent.count {
                                        MemoryMomentCell(moment: recent[index])
                                    } else {
                                        Color.white.opacity(0.06).aspectRatio(3 / 4, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            MemoryCaptureBar { memoryCaptureSource = $0 }
        }
        .padding(16)
        .memoryCapture($memoryCaptureSource, show: show) { saved in
            UINotificationFeedbackGenerator().notificationOccurred(saved ? .success : .error)
        }
    }

    private func square(_ action: CurrentShowQuickAction, value: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(action.title)
            Spacer(minLength: 12)
            Image(systemName: action.iconName)
                .font(.system(size: 20))
                .foregroundStyle(BSColor.Stage.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(BSFont.Editorial.serif(19))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(1)
            if let note, note != value {
                Text(note).font(.system(size: 12)).foregroundStyle(BSColor.Stage.muted).lineLimit(1)
            }
        }
        .padding(16)
        .frame(minHeight: 140)
    }

    private func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: show.timetable?.timeZoneIdentifier ?? "") ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// The venue on an Apple map; tapping opens the route chooser.
private struct CurrentShowRouteModule: View {
    let show: Show
    let isProminent: Bool
    @State private var coordinate: CLLocationCoordinate2D?

    var body: some View {
        Group {
            if isProminent {
                VStack(alignment: .leading, spacing: 0) {
                    map.frame(height: 150).clipped()
                    HStack(alignment: .center, spacing: 12) {
                        venue(size: 20)
                        Spacer(minLength: 8)
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            Text(BSLocalization.text("路线"))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.background)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(BSColor.Stage.foreground, in: Capsule())
                    }
                    .padding(16)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    venue(size: 15, serif: false)
                    Spacer(minLength: 8)
                    Text(BSLocalization.text("路线"))
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.Stage.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BSColor.Stage.dim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task(id: "\(show.city ?? "")|\(show.venueAddress ?? show.venueName ?? "")|\(isProminent)") {
            guard isProminent, let found = try? await MapKitGeocoding().resolve(city: show.city, address: show.venueAddress ?? show.venueName) else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                coordinate = CLLocationCoordinate2D(latitude: found.latitude, longitude: found.longitude)
            }
        }
    }

    private var map: some View {
        ZStack {
            Color.white.opacity(0.04)
            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1600, longitudinalMeters: 1600)), interactionModes: []) {
                    Marker(show.venueName ?? show.name, coordinate: coordinate).tint(BSColor.Stage.live)
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .transition(.opacity)
            } else {
                Image(systemName: "map")
                    .font(.system(size: 22))
                    .foregroundStyle(BSColor.Stage.dim)
            }
        }
    }

    private func venue(size: CGFloat, serif: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(show.venueName ?? show.city ?? show.name)
                .font(serif ? BSFont.Editorial.serif(size) : .system(size: size, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(1)
            if let detail = show.venueAddress ?? show.city {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
        }
    }
}

/// The saved ticket screenshot, small, as the stub.
private struct CurrentShowTicketThumbnail: View {
    let asset: ShowAsset
    @State private var image: UIImage?

    var body: some View {
        Color.white.opacity(0.06)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .bsMaskUserContent()
            .task(id: asset.relativePath) {
                guard let url = try? await ShowAssetMediaStore.shared.absoluteURL(for: asset.relativePath, showID: asset.showID, kind: .ticket) else { return }
                image = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 200, height: 260))
                }.value
            }
    }
}
