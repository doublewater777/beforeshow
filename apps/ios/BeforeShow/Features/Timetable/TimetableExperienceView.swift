import Foundation
import SwiftData
import SwiftUI

enum TimetableViewMode: String, CaseIterable, Identifiable {
    case timeline
    case stageMatrix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline:
            return BSLocalization.text("时间流")
        case .stageMatrix:
            return BSLocalization.text("舞台矩阵")
        }
    }
}

struct TimetableExperienceView: View {
    let timetable: Timetable
    let show: Show?
    var onInspectOrEdit: () -> Void = {}
    var onViewOriginalImages: () -> Void = {}
    var originalImagesCount: Int = 0

    @Environment(\.modelContext) private var modelContext

    @State private var selectedDayID: UUID
    @State private var viewMode: TimetableViewMode = .timeline
    @State private var periodFilter: TimetablePeriodFilter = .all
    @State private var selectedStageID: UUID?
    @State private var listenedArtistNames: Set<String> = []
    @State private var referenceNow: Date = Date()

    init(
        timetable: Timetable,
        show: Show?,
        onInspectOrEdit: @escaping () -> Void = {},
        onViewOriginalImages: @escaping () -> Void = {},
        originalImagesCount: Int = 0
    ) {
        self.timetable = timetable
        self.show = show
        self.onInspectOrEdit = onInspectOrEdit
        self.onViewOriginalImages = onViewOriginalImages
        self.originalImagesCount = originalImagesCount

        let days = timetable.orderedDays
        var initialDayID = days.first?.id ?? UUID()
        var initialViewMode: TimetableViewMode = .timeline
        var initialPeriod: TimetablePeriodFilter = .all

        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--timetable-view-stage") {
            initialViewMode = .stageMatrix
        }
        if args.contains("--timetable-filter-interested") {
            initialPeriod = .interested
        }
        if args.contains("--timetable-day-2"), days.count > 1 {
            initialDayID = days[1].id
        }
        #endif

        _selectedDayID = State(initialValue: initialDayID)
        _viewMode = State(initialValue: initialViewMode)
        _periodFilter = State(initialValue: initialPeriod)
    }

    private var currentDay: TimetableDay? {
        timetable.orderedDays.first { $0.id == selectedDayID } ?? timetable.orderedDays.first
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
    }

    private var currentDayPerformances: [TimetablePerformance] {
        guard let day = currentDay else { return [] }
        return day.performances
    }

    private var interestedPerformances: [TimetablePerformance] {
        currentDayPerformances.filter(\.isInterested)
    }

    // MARK: - Clashes Calculation

    private var clashMap: [UUID: [TimetableClashInfo]] {
        guard let day = currentDay else { return [:] }
        let stageNameMap = Dictionary(uniqueKeysWithValues: day.orderedStages.map { ($0.id, $0.name) })
        let artistNameMap = Dictionary(uniqueKeysWithValues: currentDayPerformances.map { ($0.id, $0.artistName) })

        let timings = day.stages.flatMap { stage in
            stage.performances.map {
                TimetablePerformanceTiming(
                    id: $0.id,
                    stageID: stage.id,
                    startsAt: $0.startsAt,
                    endsAt: $0.endsAt
                )
            }
        }
        let interestedIDs = Set(interestedPerformances.map(\.id))
        let clashes = TimetableClashPolicy.detectClashes(
            performances: timings,
            interestedIDs: interestedIDs,
            artistNames: artistNameMap,
            stageNames: stageNameMap
        )
        return TimetableClashPolicy.clashMap(from: clashes)
    }

    private var totalClashesCount: Int {
        let total = clashMap.values.reduce(0) { $0 + $1.count }
        return total / 2
    }

    // MARK: - Filtered Performances

    private var filteredPerformances: [TimetablePerformance] {
        let all = currentDayPerformances

        return all.filter { perf in
            if viewMode == .stageMatrix {
                if let stageID = selectedStageID {
                    return perf.stage?.id == stageID
                }
                return true
            }

            return TimetablePeriodPolicy.matches(
                startsAt: perf.startsAt,
                endsAt: perf.endsAt,
                isInterested: perf.isInterested,
                filter: periodFilter,
                timeZone: timeZone,
                referenceDate: referenceNow
            )
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: BSSpacing.md) {
                TimetableControlsHeader(
                    days: timetable.orderedDays,
                    selectedDayID: $selectedDayID,
                    viewMode: $viewMode,
                    periodFilter: $periodFilter,
                    selectedStageID: $selectedStageID,
                    currentDayStages: currentDay?.orderedStages ?? [],
                    interestedCount: interestedPerformances.count
                )

                if viewMode == .stageMatrix {
                    TimetableStageMatrixView(
                        day: currentDay,
                        referenceNow: referenceNow,
                        timeZone: timeZone,
                        onToggleInterested: toggleInterested
                    )
                } else {
                    if totalClashesCount > 0 {
                        clashSummaryBanner
                    }

                    if filteredPerformances.isEmpty {
                        emptyFilterView
                    } else {
                        performanceList
                    }
                }
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, BSSpacing.sm)
        }
        .task {
            listenedArtistNames = TimetableListeningSignals.resolveListenedArtistNames(for: show, in: modelContext)
            referenceNow = Date()
        }
    }

    // MARK: - Subviews

    private var clashSummaryBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(BSColor.Accent.warm)
                .font(.system(size: 14))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(BSLocalization.format("发现 %d 处想看演出时间重叠", totalClashesCount))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BSColor.Accent.warm)
                Text(BSLocalization.text("撞场仅作提醒，不会自动取舍演出，可按现场喜好安排"))
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.textSecondary)
            }
            Spacer()
        }
        .padding(10)
        .background(BSColor.Accent.warm.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
    }

    private var performanceList: some View {
        LazyVStack(spacing: 10) {
            ForEach(filteredPerformances, id: \.id) { perf in
                let stageName = perf.stage?.name ?? ""
                let isNow = TimetablePeriodPolicy.isNow(
                    startsAt: perf.startsAt,
                    endsAt: perf.endsAt,
                    at: referenceNow
                )
                let hasListening = TimetableListeningPolicy.hasListeningEvidence(
                    artistName: perf.artistName,
                    listenedArtistNames: listenedArtistNames
                )
                let clashes = clashMap[perf.id] ?? []

                TimetablePerformanceCard(
                    performance: perf,
                    stageName: stageName,
                    isNow: isNow,
                    hasListeningEvidence: hasListening,
                    clashes: clashes,
                    onToggleInterested: {
                        toggleInterested(for: perf)
                    }
                )
            }
        }
    }

    private var emptyFilterView: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer().frame(height: 24)
            Image(systemName: emptyFilterIcon)
                .font(.system(size: 36))
                .foregroundColor(BSColor.textTertiary)

            Text(emptyFilterTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(BSColor.textSecondary)

            Text(emptyFilterSubtitle)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BSSpacing.lg)
            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(BSSpacing.lg)
        .background(BSColor.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
    }

    // MARK: - Actions & Helpers

    private func toggleInterested(for performance: TimetablePerformance) {
        performance.isInterested.toggle()
        try? modelContext.save()
    }

    private var emptyFilterIcon: String {
        switch periodFilter {
        case .now: return "clock"
        case .upNext: return "hourglass"
        case .evening: return "moon.stars"
        case .interested: return "heart"
        case .all: return "calendar.badge.exclamationmark"
        }
    }

    private var emptyFilterTitle: String {
        switch periodFilter {
        case .now: return BSLocalization.text("此时段无正在进行的演出")
        case .upNext: return BSLocalization.text("近期无即将开始的演出")
        case .evening: return BSLocalization.text("未安排晚间演出")
        case .interested: return BSLocalization.text("暂无标记想看的演出")
        case .all: return BSLocalization.text("暂无演出安排")
        }
    }

    private var emptyFilterSubtitle: String {
        switch periodFilter {
        case .now: return BSLocalization.text("可切换至「接下来」或「全部」查看后续演出安排")
        case .upNext: return BSLocalization.text("可切换至「晚上」或「全部」查看全天安排")
        case .evening: return BSLocalization.text("该日期没有 18:00 之后的晚间场次")
        case .interested: return BSLocalization.text("点击演出卡片上的心标，即可标记想看的演出")
        case .all: return BSLocalization.text("该舞台或日期下没有演出数据")
        }
    }
}
