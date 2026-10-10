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

    @Environment(\.modelContext) private var modelContext
    @State private var wantOnly: Bool
    @State private var isSharing = false
    @State private var canReturnToNow = false
    @State private var returnToNowRequest = 0
    @State private var inspectingPerformance: TimetablePerformance?
    @State private var stageToRename: TimetableStage?
    @State private var isRenamingStagePresented = false
    @State private var renameStageText = ""
    @State private var stageToDelete: TimetableStage?
    @State private var isConfirmingDeleteStage = false
    @State private var isAddingStagePresented = false
    @State private var newStageText = ""
    @Namespace private var dockIndicator

    init(
        timetable: Timetable,
        show: Show?,
        selectedDayID: Binding<UUID>,
        linker: TimetableArtistLinker,
        addPerformanceRequest: Int = 0,
        avatarURL: @escaping (TimetablePerformance) -> URL?
    ) {
        self.timetable = timetable
        self.show = show
        _selectedDayID = selectedDayID
        self.linker = linker
        self.addPerformanceRequest = addPerformanceRequest
        self.avatarURL = avatarURL
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
                    onRenameStage: { stage in
                        stageToRename = stage
                        renameStageText = stage.name
                        isRenamingStagePresented = true
                    },
                    onDeleteStage: { stage in
                        stageToDelete = stage
                        isConfirmingDeleteStage = true
                    },
                    onAddStage: {
                        newStageText = ""
                        isAddingStagePresented = true
                    }
                )
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
                    onDelete: {
                        deletePerformance(perf)
                    }
                )
                .bsSystemGlassSheet(detents: [.fraction(0.74), .large])
            }
        }
        .sheet(isPresented: $isSharing) {
            TimetableShareSheet(timetable: timetable, show: show, avatarURL: avatarURL)
        }
        .alert(
            BSLocalization.text("重命名舞台"),
            isPresented: $isRenamingStagePresented,
            presenting: stageToRename
        ) { stage in
            TextField(BSLocalization.text("舞台名称"), text: $renameStageText)
            Button(BSLocalization.text("保存")) {
                let trimmed = renameStageText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try? stage.updateName(trimmed)
                    try? modelContext.save()
                }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        }
        .alert(
            BSLocalization.text("删除舞台"),
            isPresented: $isConfirmingDeleteStage,
            presenting: stageToDelete
        ) { stage in
            Button(BSLocalization.text("删除舞台及演出"), role: .destructive) {
                deleteStage(stage)
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: { stage in
            Text(BSLocalization.format("确认删除「%@」及其全部演出吗？", stage.name))
        }
        .alert(
            BSLocalization.text("新增舞台"),
            isPresented: $isAddingStagePresented
        ) {
            TextField(BSLocalization.text("舞台名称"), text: $newStageText)
            Button(BSLocalization.text("添加")) {
                let trimmed = newStageText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let day = currentDay {
                    _ = try? day.addStage(
                        name: trimmed,
                        placeholderArtistName: BSLocalization.text("待定演出")
                    )
                    try? modelContext.save()
                }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
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

    private func toggleInterested(_ performance: TimetablePerformance) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            performance.isInterested.toggle()
        }
        try? modelContext.save()
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
        do {
            let newPerf = try TimetablePerformance(
                artistName: BSLocalization.text("新演出"),
                startsAt: start,
                endsAt: end
            )
            modelContext.insert(newPerf)
            newPerf.stage = stage
            try modelContext.save()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            inspectingPerformance = newPerf
        } catch {}
    }

    private func deletePerformance(_ performance: TimetablePerformance) {
        if TimetablePreviewPlayer.shared.activePerformanceID == performance.id {
            TimetablePreviewPlayer.shared.stop()
        }
        inspectingPerformance = nil
        modelContext.delete(performance)
        try? modelContext.save()
    }

    private func deleteStage(_ stage: TimetableStage) {
        if stage.performances.contains(where: { $0.id == TimetablePreviewPlayer.shared.activePerformanceID }) {
            TimetablePreviewPlayer.shared.stop()
        }
        stageToDelete = nil
        try? currentDay?.removeStage(stage)
        modelContext.delete(stage)
        try? modelContext.save()
    }
}
