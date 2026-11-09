import MapKit
import SwiftData
import SwiftUI

/// The show's tools and records in phase order. A card with little to say is a half card and
/// pairs with the next one; a card with something to look at takes the row.
struct CurrentShowActionModules: View {
    let show: Show
    let actions: [CurrentShowQuickAction]
    let companion: CompanionQuickActionPresentation
    var now: Date = .now
    /// Before doors the route is the job of the day: a full map. Once there, a slim card.
    var routeIsProminent = false
    /// Live mode already lists who's next; the timetable card moves first and is just the way in.
    var timetableIsLive = false
    var recordPhase: HomeShowPhase = .pre
    let perform: (CurrentShowQuickAction) -> Void

    @Query private var assets: [ShowAsset]
    @Query private var setlist: [ShowSetlistMemory]
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
        _setlist = Query(filter: #Predicate<ShowSetlistMemory> { $0.showID == showID })
    }

    var body: some View {
        let modules = CurrentShowModuleOrder.modules(actions: actions, phase: recordPhase, timetableIsLive: timetableIsLive)
        let facts = ShowRecordCard.facts(show: show, setlist: setlist)
        ShowModuleGrid(items: modules.map { ($0, width($0, facts: facts)) }) { module in
            switch module {
            case .action(let action):
                actionModule(action)
            case .record(let kind):
                ShowRecordCard(show: show, kind: kind, phase: recordPhase, surface: .glass)
            }
        }
        .memoryCapture($memoryCaptureSource, show: show) { saved in
            UINotificationFeedbackGenerator().notificationOccurred(saved ? .success : .error)
        }
    }

    private func width(_ module: CurrentShowModule, facts: CurrentShowRecordFacts) -> ShowModuleWidth {
        switch module {
        case .record(let kind):
            CurrentShowRecordKit.width(kind, phase: recordPhase, facts: facts)
        case .action(.ticket), .action(.companion), .action(.dispersal):
            .half
        case .action(.timetable):
            timetableIsLive || !upcomingPerformances.isEmpty ? .full : .half
        case .action:
            .full
        }
    }

    @ViewBuilder
    private func actionModule(_ action: CurrentShowQuickAction) -> some View {
        switch action {
        case .memoryFragments:
            memoryCard
        default:
            Button { perform(action) } label: { label(action) }
                .buttonStyle(.plain)
                .accessibilityLabel(action == .companion ? companion.accessibilityLabel : action.title)
        }
    }

    @ViewBuilder
    private func label(_ action: CurrentShowQuickAction) -> some View {
        switch action {
        case .ticket:
            ShowAssetPhotoCard(kind: .ticket, asset: assets.first { $0.kind == .ticket }, surface: .glass)
        case .timetable:
            if timetableIsLive {
                fullCard(ShowModuleHeader(
                    title: action.title,
                    status: BSLocalization.format("%lld 个舞台", Set(show.timetable?.orderedDays.flatMap(\.orderedStages).map(\.name) ?? []).count),
                    action: "›",
                    emphasizesAction: false
                ))
            } else if !upcomingPerformances.isEmpty {
                upcomingCard
            } else {
                ShowAssetPhotoCard(kind: .timetable, asset: assets.first { $0.kind == .timetable }, hasContentWithoutImage: show.timetable != nil, tilt: 4, surface: .glass)
            }
        case .companion:
            ShowCompanionCard(names: companion.companionNames, surface: .glass)
        case .dispersal(let completed):
            ShowModuleIconCard(
                title: action.title,
                status: BSLocalization.text(completed ? "已记下" : "这一场怎么样"),
                action: "›",
                emphasizesAction: !completed,
                iconName: action.iconName,
                surface: .glass
            )
        case .route:
            if routeIsProminent {
                CurrentShowRouteModule(show: show)
            } else {
                fullCard(ShowModuleHeader(title: action.title, status: show.venueName ?? show.city, action: BSLocalization.text("路线")))
            }
        case .endShow:
            fullCard(
                ShowModuleHeader(title: action.title, status: BSLocalization.text("记下散场时间"), action: "›", emphasizesAction: false, titleColor: BSColor.Stage.liveTitle),
                tint: BSColor.Stage.live.opacity(0.12)
            )
        case .memoryFragments:
            EmptyView()
        }
    }

    private func fullCard(_ header: ShowModuleHeader, tint: Color? = nil) -> some View {
        header
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64)
            .showModuleCard(.glass, tint: tint)
    }

    // MARK: Timetable

    private var upcomingPerformances: [TimetablePerformance] {
        Array((show.timetable?.orderedDays.flatMap(\.performances) ?? [])
            .filter { $0.endsAt > now }
            .sorted(by: TimetablePerformance.chronologicalOrder)
            .prefix(3))
    }

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShowModuleHeader(title: CurrentShowQuickAction.timetable.title, action: "›", emphasizesAction: false)
            ForEach(upcomingPerformances) { perf in
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .showModuleCard(.glass)
    }

    // MARK: Memory

    /// The latest frames of the night, and the three ways to add one without leaving the page.
    private var memoryCard: some View {
        let moments = MemoryMomentTimeline.moments(from: show.memoryFragments)
        let recent = Array(moments.suffix(4).reversed())
        return VStack(alignment: .leading, spacing: 12) {
            Button { perform(.memoryFragments) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    ShowModuleHeader(
                        title: CurrentShowQuickAction.memoryFragments.title,
                        status: moments.isEmpty ? nil : MemoryMomentTimeline.countText(moments.count),
                        action: "›",
                        emphasizesAction: false
                    )
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
            .accessibilityLabel(CurrentShowQuickAction.memoryFragments.title)
            MemoryCaptureBar { memoryCaptureSource = $0 }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .showModuleCard(.glass)
    }

    private func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: show.timetable?.timeZoneIdentifier ?? "") ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// The venue on an Apple map before doors; tapping opens the route chooser.
private struct CurrentShowRouteModule: View {
    let show: Show
    @State private var coordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            map.frame(height: 130).clipped()
            HStack(alignment: .center, spacing: 12) {
                venue
                Spacer(minLength: 8)
                Text(BSLocalization.text("路线"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.75))
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .showModuleCard(.glass)
        .task(id: "\(show.city ?? "")|\(show.venueAddress ?? show.venueName ?? "")") {
            guard let found = try? await MapKitGeocoding().resolve(city: show.city, address: show.venueAddress ?? show.venueName) else { return }
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

    private var venue: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(show.venueName ?? show.city ?? show.name)
                .font(BSFont.Editorial.serif(19))
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
