import SwiftData
import SwiftUI

/// Main timetable screen: the stage matrix plus a floating dock for the
/// "想看" filter and sharing.
struct TimetableExperienceView: View {
    let timetable: Timetable
    let show: Show?
    @Binding var selectedDayID: UUID
    let linker: TimetableArtistLinker
    let addPerformanceRequest: Int
    let avatarURL: (TimetablePerformance) -> URL?
    let onManage: () -> Void
    let allowsSharing: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var wantOnly: Bool
    @State private var isSharing = false
    @State private var canReturnToNow = false
    @State private var returnToNowRequest = 0
    @State private var inspectingPerformance: TimetablePerformance?
    @State private var addingSlot: AddSlot?
    @Namespace private var dockIndicator

    init(
        timetable: Timetable,
        show: Show?,
        selectedDayID: Binding<UUID>,
        linker: TimetableArtistLinker,
        addPerformanceRequest: Int = 0,
        avatarURL: @escaping (TimetablePerformance) -> URL?,
        onManage: @escaping () -> Void,
        allowsSharing: Bool = true
    ) {
        self.timetable = timetable
        self.show = show
        _selectedDayID = selectedDayID
        self.linker = linker
        self.addPerformanceRequest = addPerformanceRequest
        self.avatarURL = avatarURL
        self.onManage = onManage
        self.allowsSharing = allowsSharing
        var wantOnly = false
        #if DEBUG
        wantOnly = ProcessInfo.processInfo.arguments.contains("--timetable-filter-interested")
        #endif
        _wantOnly = State(initialValue: wantOnly)
    }

    private var currentDay: TimetableDay? {
        timetable.orderedDays.first { $0.id == selectedDayID } ?? timetable.orderedDays.first
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
    }

    private var interestedCount: Int {
        currentDay?.performances.filter(\.isInterested).count ?? 0
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let day = currentDay {
                TimetableStageMatrixView(
                    day: day,
                    now: context.date,
                    timeZone: timeZone,
                    wantOnly: wantOnly,
                    canReturnToNow: $canReturnToNow,
                    returnToNowRequest: returnToNowRequest,
                    avatarURL: avatarURL,
                    onSelectPerformance: { performance in
                        inspectingPerformance = performance
                    },
                    onToggleInterested: toggleInterested,
                    onAddPerformance: { stage, date in
                        addPerformance(to: stage, at: date)
                    },
                    onManage: onManage,
                    onRenameStage: renameStage
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let show {
                TimetableDateConfirmationNotice(timetable: timetable, show: show, onManage: onManage)
            }
        }
        .overlay(alignment: .bottom) { dock }
        .sheet(item: $inspectingPerformance) { perf in
            if let day = currentDay {
                TimetablePerformanceInspectorSheet(
                    performance: perf,
                    day: day,
                    avatarURL: avatarURL(perf),
                    linker: linker,
                    timeZone: timeZone,
                    onPerformanceChanged: {
                        notifyShowMutation()
                    },
                    onDelete: {
                        deletePerformance(perf)
                    }
                )
                .bsSystemGlassSheet(detents: [.fraction(0.68), .large])
            }
        }
        .sheet(isPresented: $isSharing) {
            TimetableShareSheet(timetable: timetable, show: show, avatarURL: avatarURL)
        }
        .sheet(item: $addingSlot) { slot in
            if let day = currentDay, let stage = day.stages.first(where: { $0.id == slot.stageID }) {
                TimetableAddPerformanceSheet(
                    day: day,
                    stage: stage,
                    start: slot.start,
                    end: slot.end,
                    linker: linker,
                    avatarURL: avatarURL,
                    timeZone: timeZone
                )
                .bsSystemGlassSheet(detents: [.fraction(0.74), .large])
            }
        }
        .onChange(of: addPerformanceRequest) { _, _ in
            if let stage = currentDay?.orderedStages.first {
                addPerformance(to: stage)
            }
        }
        .onChange(of: selectedDayID) { _, _ in
            TimetablePreviewPlayer.shared.stop()
        }
    }

    // MARK: - Dock

    private var dock: some View {
        ZStack {
            HStack(spacing: 0) {
                dockOption(isOn: !wantOnly, tint: Color.white.opacity(0.10)) {
                    Text(BSLocalization.text("全部"))
                        .foregroundStyle(wantOnly ? TimetableStyle.muted : TimetableStyle.foreground)
                }
                .frame(width: 76)
                .onTapGesture { setWantOnly(false) }

                dockOption(isOn: wantOnly, tint: TimetableStyle.mine) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(wantOnly ? TimetableStyle.background : TimetableStyle.mine)
                        Text(BSLocalization.text("想看"))
                        Text("\(interestedCount)").font(TimetableStyle.mono(14, weight: .semibold))
                    }
                    .foregroundStyle(wantOnly ? TimetableStyle.background : TimetableStyle.muted)
                }
                .frame(width: 112)
                .onTapGesture { setWantOnly(true) }
            }
            .font(.system(size: 14, weight: .bold))
            .padding(4)
            .glassEffect(.clear, in: Capsule())

            if canReturnToNow {
                Button {
                    returnToNowRequest += 1
                } label: {
                    Image(systemName: "scope")
                        .font(TimetableStyle.dockActionFont)
                        .foregroundStyle(TimetableStyle.foreground)
                        .frame(width: TimetableStyle.dockActionSize, height: TimetableStyle.dockActionSize)
                }
                .buttonStyle(TimetablePressStyle())
                .glassEffect(.clear, in: Circle())
                .accessibilityLabel(BSLocalization.text("回到现在"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, BSSpacing.roomy)
            }

            if allowsSharing {
                Button {
                    isSharing = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(TimetableStyle.dockActionFont)
                        .foregroundStyle(TimetableStyle.foreground)
                        .frame(width: TimetableStyle.dockActionSize, height: TimetableStyle.dockActionSize)
                }
                .buttonStyle(TimetablePressStyle())
                .glassEffect(.clear, in: Circle())
                .accessibilityLabel(BSLocalization.text("分享"))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
            }
        }
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: wantOnly)
    }

    private func dockOption<Label: View>(isOn: Bool, tint: Color, @ViewBuilder label: () -> Label) -> some View {
        label()
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isOn {
                    Capsule().fill(tint).matchedGeometryEffect(id: "dock", in: dockIndicator)
                }
            }
            .contentShape(Capsule())
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func setWantOnly(_ value: Bool) {
        withAnimation(TimetableStyle.pressSpring) { wantOnly = value }
    }

    // MARK: - Actions

    private func notifyShowMutation() {
        show?.updatedAt = Date()
        try? modelContext.save()
        let container = modelContext.container
        Task {
            await LocalNotificationCenter.shared.reconcilePortfolio(in: ModelContext(container))
        }
    }

    private func toggleInterested(_ performance: TimetablePerformance) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            performance.isInterested.toggle()
        }
        notifyShowMutation()
    }

    private func renameStage(_ stage: TimetableStage, to name: String) {
        do {
            try stage.updateName(name)
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }

    private func addPerformance(to stage: TimetableStage, at tappedDate: Date? = nil) {
        guard let day = currentDay else { return }
        let start: Date
        let end: Date
        if let tappedDate {
            let seconds = tappedDate.timeIntervalSinceReferenceDate
            let roundedSeconds = (seconds / 300.0).rounded() * 300.0
            let targetStart = Date(timeIntervalSinceReferenceDate: roundedSeconds)

            // If tapped right around or inside an existing performance's end, start immediately after it
            let overlappingPrev = stage.performances.filter { $0.startsAt < targetStart && $0.endsAt > targetStart }
            if let maxPrevEnd = overlappingPrev.map(\.endsAt).max() {
                start = maxPrevEnd
            } else {
                start = targetStart
            }

            let defaultEnd = start.addingTimeInterval(45 * 60)
            let nextStarts = stage.performances.map(\.startsAt).filter { $0 > start }.sorted()
            if let nextStart = nextStarts.first, nextStart < defaultEnd, nextStart.timeIntervalSince(start) >= 15 * 60 {
                end = nextStart
            } else {
                end = max(start.addingTimeInterval(15 * 60), defaultEnd)
            }
        } else {
            let lastEnd = stage.performances.map(\.endsAt).max()
                ?? day.performances.map(\.endsAt).max()
                ?? day.date.addingTimeInterval(14 * 3600)
            start = lastEnd.addingTimeInterval(15 * 60)
            end = start.addingTimeInterval(45 * 60)
        }
        addingSlot = AddSlot(stageID: stage.id, start: start, end: end)
    }

    private func deletePerformance(_ performance: TimetablePerformance) {
        if TimetablePreviewPlayer.shared.activePerformanceID == performance.id {
            TimetablePreviewPlayer.shared.stop()
        }
        inspectingPerformance = nil
        modelContext.delete(performance)
        notifyShowMutation()
    }
}

/// A proposed new set: where and when the add form opens. Nothing is saved yet.
private struct AddSlot: Identifiable {
    let stageID: UUID
    let start: Date
    let end: Date
    var id: String { "\(stageID)-\(start.timeIntervalSinceReferenceDate)" }
}
