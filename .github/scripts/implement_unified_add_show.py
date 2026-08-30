#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]

def read(rel):
    return (ROOT / rel).read_text()

def write(rel, text):
    (ROOT / rel).write_text(text)

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 exact match, got {count}")
    return text.replace(old, new, 1)

def replace_between(text, start, end, new, label):
    i = text.find(start)
    if i < 0:
        raise RuntimeError(f"{label}: start marker missing")
    j = text.find(end, i)
    if j < 0:
        raise RuntimeError(f"{label}: end marker missing")
    return text[:i] + new + text[j:]

def patch_tests():
    rel = "apps/ios/BeforeShowTests/OpeningMemoryWindowTests.swift"
    text = read(rel)
    old = '''    func testNotificationBackfillsTenMinutesWhenAddedInsideWindow() {
        let now = start.addingTimeInterval(20 * 60)
        XCTAssertEqual(
            OpeningMemoryWindow.notificationFireDate(
                now: now,
                showStart: start,
                hasConfirmedEnd: false
            ),
            now.addingTimeInterval(10 * 60)
        )
    }
'''
    new = '''    func testNotificationDoesNotBackfillWhenAddedInsideWindow() {
        let now = start.addingTimeInterval(20 * 60)
        XCTAssertNil(
            OpeningMemoryWindow.notificationFireDate(
                now: now,
                showStart: start,
                hasConfirmedEnd: false
            )
        )
    }
'''
    text = replace_once(text, old, new, "OpeningMemoryWindow test")
    write(rel, text)

    rel = "apps/ios/BeforeShowTests/LocalNotificationSchedulingTests.swift"
    text = read(rel)
    text = text.replace(
        "func testOpeningMemoryBackfillsWhenAddedInsideWindow()",
        "func testOpeningMemoryDoesNotBackfillWhenAddedInsideWindow()",
        1
    )
    old_snippet = '''        let opening = requests.first { $0.identifier.hasSuffix(".openingMemory") }
        XCTAssertNotNil(opening)
        XCTAssertEqual(
            opening?.fireDate.timeIntervalSince(now) ?? 0,
            OpeningMemoryWindow.fallbackDelay,
            accuracy: 0.5
        )
'''
    if old_snippet in text:
        text = replace_once(
            text,
            old_snippet,
            '''        XCTAssertFalse(requests.contains { $0.identifier.hasSuffix(".openingMemory") })
''',
            "LocalNotification opening-memory assertion"
        )
    write(rel, text)

    rel = "apps/ios/BeforeShowTests/FootprintArchiveTests.swift"
    text = read(rel)
    start = "    func testEmptyStateOffersFootprintBackfill() {"
    end = "    func testArchiveIncludesOnlyEndedScheduledShows() throws {"
    replacement = r'''    func testFootprintEmptyStateUsesUnifiedAddShowAction() {
        let withCurrentShow = FootprintEmptyStateCopy.content(hasCurrentShow: true)
        let withoutCurrentShow = FootprintEmptyStateCopy.content(hasCurrentShow: false)

        XCTAssertEqual(withCurrentShow.actionTitle, "添加现场")
        XCTAssertEqual(withoutCurrentShow.actionTitle, "添加现场")
    }

    func testUnifiedAddMethodsKeepLinkScreenshotManualOrder() {
        XCTAssertEqual(AddShowConfiguration.methodOrder, [.link, .screenshot, .manual])
    }

    func testUnifiedManualDraftDefaultsToTodayAtEightPM() {
        let now = date(2026, 8, 29, 10)
        let draft = AddShowConfiguration.initialManualDraft(now: now, calendar: calendar)

        XCTAssertEqual(draft.date, date(2026, 8, 29))
        XCTAssertEqual(draft.startTime, date(2026, 8, 29, 20))
    }

    func testAddLifecycleAsksWhenTodayShowHasStarted() throws {
        let now = date(2026, 8, 29, 21)
        let show = try Show(
            name: "正在现场",
            date: date(2026, 8, 29),
            startTime: date(2026, 8, 29, 20)
        )

        XCTAssertEqual(
            AddShowLifecyclePolicy.resolution(for: show, now: now, calendar: calendar),
            .needsEndConfirmation
        )
    }

    func testAddLifecycleAsksAfterEstimatedEndWhileStillInRetention() throws {
        let now = date(2026, 8, 30, 1)
        let show = try Show(
            name: "刚散场待确认",
            date: date(2026, 8, 29),
            startTime: date(2026, 8, 29, 20)
        )

        XCTAssertEqual(
            AddShowLifecyclePolicy.resolution(for: show, now: now, calendar: calendar),
            .needsEndConfirmation
        )
    }

    func testAddLifecycleTreatsClearlyOldShowAsEndedWithoutPrompt() throws {
        let now = date(2026, 8, 29, 12)
        let show = try Show(
            name: "旧现场",
            date: date(2026, 8, 1),
            startTime: date(2026, 8, 1, 20)
        )

        XCTAssertEqual(
            AddShowLifecyclePolicy.resolution(for: show, now: now, calendar: calendar),
            .ended
        )
    }

'''
    text = replace_between(text, start, end, replacement, "Footprint unified top tests")

    start = "    func testHistoricalBackfillPreservesCurrentSelectionAndNotificationFocus() throws {"
    end = "    func testArchiveShareCopyIsSpecificToEveryCategory() throws {"
    replacement = r'''    func testEndedAddPreservesCurrentSelectionAndNotificationFocus() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self, NotificationSchedulingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let current = try makeShow("未来现场", year: 2027, artist: "未来艺人", city: "上海", venue: "MAO")
        let selection = CurrentShowSelection(selectedShowID: current.id)
        let notificationState = NotificationSchedulingState(focusedShowID: current.id)
        context.insert(current)
        context.insert(selection)
        context.insert(notificationState)
        try context.save()

        let ended = try makeShow("过去现场", year: 2024, artist: "过去艺人", city: "北京", venue: "工体")
        let result = try AddShowPersistenceCoordinator.persist(
            ended,
            lifecycle: .ended,
            selections: [selection],
            notificationStates: [notificationState],
            in: context,
            now: date(2026, 8, 29, 12)
        )

        XCTAssertEqual(result.outcome, .footprint)
        XCTAssertNil(result.notificationState)
        XCTAssertEqual(selection.selectedShowID, current.id)
        XCTAssertEqual(notificationState.focusedShowID, current.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Show>()).count, 2)
    }

    func testFutureAddDoesNotStealExistingCurrentShow() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self, NotificationSchedulingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let nearer = try makeShow("近场", year: 2027, artist: "A", city: "上海", venue: "MAO")
        let farther = try makeShow("远场", year: 2028, artist: "B", city: "北京", venue: "工体")
        let selection = CurrentShowSelection(selectedShowID: nearer.id)
        let notificationState = NotificationSchedulingState(focusedShowID: nearer.id)
        context.insert(nearer)
        context.insert(selection)
        context.insert(notificationState)
        try context.save()

        let result = try AddShowPersistenceCoordinator.persist(
            farther,
            lifecycle: .future,
            selections: [selection],
            notificationStates: [notificationState],
            in: context,
            now: date(2026, 8, 29, 12)
        )

        XCTAssertEqual(result.outcome, .future)
        XCTAssertNil(result.notificationState)
        XCTAssertEqual(selection.selectedShowID, nearer.id)
        XCTAssertEqual(notificationState.focusedShowID, nearer.id)
    }

    func testFutureAddBecomesCurrentWhenNoCurrentExists() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self, NotificationSchedulingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let future = try makeShow("第一场未来现场", year: 2027, artist: "A", city: "上海", venue: "MAO")

        let result = try AddShowPersistenceCoordinator.persist(
            future,
            lifecycle: .future,
            selections: [],
            notificationStates: [],
            in: context,
            now: date(2026, 8, 29, 12)
        )

        XCTAssertEqual(result.outcome, .future)
        XCTAssertEqual(result.notificationState?.focusedShowID, future.id)
        let selections = try context.fetch(FetchDescriptor<CurrentShowSelection>())
        XCTAssertEqual(selections.first?.selectedShowID, future.id)
    }

    func testConfirmedLiveAddForcesCurrentShow() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self, NotificationSchedulingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let existing = try makeShow("明天的现场", year: 2027, artist: "A", city: "上海", venue: "MAO")
        let live = try Show(
            name: "正在看的现场",
            date: date(2026, 8, 29),
            startTime: date(2026, 8, 29, 20)
        )
        let selection = CurrentShowSelection(selectedShowID: existing.id)
        let notificationState = NotificationSchedulingState(focusedShowID: existing.id)
        context.insert(existing)
        context.insert(selection)
        context.insert(notificationState)
        try context.save()

        let result = try AddShowPersistenceCoordinator.persist(
            live,
            lifecycle: .live,
            selections: [selection],
            notificationStates: [notificationState],
            in: context,
            now: date(2026, 8, 29, 21)
        )

        XCTAssertEqual(result.outcome, .current)
        XCTAssertEqual(result.notificationState?.focusedShowID, live.id)
        XCTAssertEqual(selection.selectedShowID, live.id)
        XCTAssertEqual(notificationState.focusedShowID, live.id)
    }

'''
    text = replace_between(text, start, end, replacement, "Footprint persistence tests")
    write(rel, text)

def patch_implementation():
    rel = "apps/ios/BeforeShow/OpeningMemoryWindow.swift"
    text = read(rel)
    text = text.replace("    static let fallbackDelay: TimeInterval = 10 * 60\n", "")
    old = '''        let boundary = windowEnd(showStart: start, confirmedEnd: end)
        guard now < boundary else { return nil }
        if now < start { return start }
        return min(now.addingTimeInterval(fallbackDelay), boundary)
'''
    new = '''        guard now < start else { return nil }
        return start
'''
    text = replace_once(text, old, new, "OpeningMemoryWindow implementation")
    write(rel, text)

    rel = "apps/ios/BeforeShow/AddShowFlowViews.swift"
    text = read(rel)
    start = "struct AddShowCoordinatorSheet: View {"
    end = "private struct AddShowEntryView: View {"
    replacement = r'''enum AddShowConfiguration {
    static let methodOrder: [AddShowSheet] = [.link, .screenshot, .manual]

    static var navigationTitle: String { BSLocalization.text("添加现场") }
    static var saveButtonTitle: String { BSLocalization.text("添加现场") }

    static func initialManualDraft(now: Date = Date(), calendar: Calendar = .current) -> ShowDraft {
        let today = calendar.startOfDay(for: now)
        let startTime = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: today)
        return ShowDraft(date: today, startTime: startTime, source: .manual)
    }
}

enum AddShowLifecycleResolution: Equatable {
    case future
    case needsEndConfirmation
    case ended
}

enum AddShowFinalLifecycle: Equatable {
    case future
    case live
    case ended
}

enum AddShowSaveOutcome: String, Equatable {
    case future
    case current
    case footprint
}

enum AddShowLifecyclePolicy {
    static func resolution(
        for show: Show,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AddShowLifecycleResolution {
        if show.endedAt != nil {
            return .ended
        }

        let state = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        switch state.kind {
        case .before:
            return .future
        case .today:
            guard let start = state.effectiveStartTime, now >= start else {
                return .future
            }
            return .needsEndConfirmation
        case .dayEnded, .postShow:
            return .needsEndConfirmation
        case .ended:
            return .ended
        case .canceled, .postponed:
            return .future
        }
    }
}

enum AddShowPersistenceError: Error, Equatable {
    case duplicateShow(existingShowID: UUID)
}

struct AddShowPersistenceResult {
    let outcome: AddShowSaveOutcome
    let notificationState: NotificationSchedulingState?
}

@MainActor
enum AddShowPersistenceCoordinator {
    static func persist(
        _ show: Show,
        lifecycle: AddShowFinalLifecycle,
        selections: [CurrentShowSelection],
        notificationStates: [NotificationSchedulingState],
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws -> AddShowPersistenceResult {
        let persistedShows = try modelContext.fetch(FetchDescriptor<Show>())
        if let duplicate = ShowDuplicateMatcher.firstDuplicate(of: show, in: persistedShows) {
            throw AddShowPersistenceError.duplicateShow(existingShowID: duplicate.id)
        }

        let existingCurrent = CurrentShowSession().selectCurrentShow(
            from: persistedShows,
            manualSelection: selections.first,
            now: now
        )

        modelContext.insert(show)

        switch lifecycle {
        case .ended:
            try modelContext.save()
            return AddShowPersistenceResult(outcome: .footprint, notificationState: nil)

        case .future where existingCurrent != nil:
            try modelContext.save()
            return AddShowPersistenceResult(outcome: .future, notificationState: nil)

        case .future, .live:
            let selection = selections.first ?? CurrentShowSelection()
            if selections.isEmpty {
                modelContext.insert(selection)
            }
            selection.select(showID: show.id)

            let notificationState = notificationStates.first
                ?? NotificationSchedulingState(focusedShowID: show.id)
            if notificationStates.isEmpty {
                modelContext.insert(notificationState)
            } else {
                notificationState.focus(showID: show.id)
            }

            try modelContext.save()
            return AddShowPersistenceResult(
                outcome: lifecycle == .live ? .current : .future,
                notificationState: notificationState
            )
        }
    }
}

struct AddShowCoordinatorSheet: View {
    var initialSheet: AddShowSheet? = nil
    var onShowAdded: (UUID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSheet: AddShowSheet?

    init(
        initialSheet: AddShowSheet? = nil,
        onShowAdded: @escaping (UUID) -> Void = { _ in }
    ) {
        self.initialSheet = initialSheet
        self.onShowAdded = onShowAdded
        _selectedSheet = State(initialValue: initialSheet)
    }

    var body: some View {
        NavigationStack {
            AddShowEntryView(methods: AddShowConfiguration.methodOrder) { sheet in
                selectedSheet = sheet
            }
            .navigationTitle(AddShowConfiguration.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: "取消") { dismiss() }
            }
            .navigationDestination(item: $selectedSheet) { sheet in
                AddShowFlowView(
                    sheet: sheet,
                    onSaved: onShowAdded,
                    onFinished: { dismiss() }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

'''
    text = replace_between(text, start, end, replacement, "AddShow coordinator/domain block")

    old = '''    let sheet: AddShowSheet
    let intent: AddShowIntent
    let linkParser: ShowLinkDraftParser
    private let onSaved: ((UUID) -> Void)?

    @State private var draft: ShowDraft
'''
    new = '''    let sheet: AddShowSheet
    let linkParser: ShowLinkDraftParser
    private let onSaved: ((UUID) -> Void)?
    private let onFinished: (() -> Void)?

    @State private var draft: ShowDraft
'''
    text = replace_once(text, old, new, "AddShow flow properties")

    old = '''    @State private var fallbackDateConfirmed = false
    init(
        sheet: AddShowSheet,
        intent: AddShowIntent = .upcoming,
        linkParser: ShowLinkDraftParser = AddShowFlowView.defaultLinkParser(),
        prefilledDraft: ShowDraft? = nil,
        onSaved: ((UUID) -> Void)? = nil
    ) {
        self.sheet = sheet
        self.intent = intent
        self.linkParser = linkParser
        self.onSaved = onSaved
        if let prefilledDraft {
            _draft = State(initialValue: prefilledDraft)
            _hasImportedDraft = State(initialValue: true)
        } else {
            let initialDraft = sheet == .manual
                ? intent.initialManualDraft()
                : ShowDraft(source: sheet.draftSource)
            _draft = State(initialValue: initialDraft)
        }
    }
'''
    new = '''    @State private var fallbackDateConfirmed = false
    @State private var pendingLifecycleConfirmation: PendingAddShowLifecycleConfirmation?
    @State private var detailTarget: AddShowDetailDestination?

    init(
        sheet: AddShowSheet,
        linkParser: ShowLinkDraftParser = AddShowFlowView.defaultLinkParser(),
        prefilledDraft: ShowDraft? = nil,
        onSaved: ((UUID) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        self.sheet = sheet
        self.linkParser = linkParser
        self.onSaved = onSaved
        self.onFinished = onFinished
        if let prefilledDraft {
            _draft = State(initialValue: prefilledDraft)
            _hasImportedDraft = State(initialValue: true)
        } else {
            let initialDraft = sheet == .manual
                ? AddShowConfiguration.initialManualDraft()
                : ShowDraft(source: sheet.draftSource)
            _draft = State(initialValue: initialDraft)
        }
    }
'''
    text = replace_once(text, old, new, "AddShow flow init")

    old = '''            if let savedShowConfirmation {
                AddShowSavedConfirmationView(
                    confirmation: savedShowConfirmation,
                    intent: intent
                )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
'''
    new = '''            if let savedShowConfirmation {
                AddShowSavedConfirmationView(
                    confirmation: savedShowConfirmation,
                    onOpen: { presentDetail(for: savedShowConfirmation) },
                    onDone: finishFlow
                )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
'''
    text = replace_once(text, old, new, "AddShow success body")
    text = text.replace('intent.saveButtonTitle', 'AddShowConfiguration.saveButtonTitle')

    marker = '''        .sheet(item: $paywallSheet) { sheet in
'''
    insertion = r'''        .navigationDestination(item: $detailTarget) { target in
            Group {
                if let show = shows.first(where: { $0.id == target.showID }) {
                    switch target.kind {
                    case .show:
                        ShowDetailView(show: show)
                    case .footprint:
                        FootprintDetailView(
                            show: show,
                            archive: FootprintArchiveBuilder.make(shows: shows)
                        )
                    }
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(item: $pendingLifecycleConfirmation) { pending in
            AddShowLifecycleConfirmationSheet(
                showName: pending.show.name,
                showStart: CurrentShowTimeState.minimumConfirmableEnd(
                    for: pending.show,
                    calendar: pending.show.timingCalendar()
                ),
                calendar: pending.show.endTimingCalendar(),
                onLive: {
                    pendingLifecycleConfirmation = nil
                    Task { @MainActor in
                        await persistPreparedShow(pending.show, lifecycle: .live)
                    }
                },
                onEnded: { endTime in
                    pending.show.markEnded(at: endTime)
                    pendingLifecycleConfirmation = nil
                    Task { @MainActor in
                        await persistPreparedShow(pending.show, lifecycle: .ended)
                    }
                }
            )
        }
'''
    text = replace_once(text, marker, insertion + marker, "AddShow lifecycle sheet")

    start = "    @MainActor\n    private func save() async {"
    end = "    @MainActor\n    private func activateNotifications("
    replacement = r'''    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard !isImportingDraft else { return }
        guard !needsDateConfirmation else { return }
        isSaving = true
        dismissKeyboard()

        do {
            let show = try draft.makeShow()

            if let duplicate = ShowDuplicateMatcher.firstDuplicate(of: show, in: shows) {
                PostHogSDK.shared.capture("duplicate_show_blocked", properties: [
                    "method": sheet.rawValue,
                    "existing_show_id": duplicate.id.uuidString
                ])
                savedShowConfirmation = SavedShowConfirmation(
                    showID: duplicate.id,
                    name: duplicate.name,
                    coverImageURL: duplicate.coverImageURL,
                    kind: .duplicate(detailOutcome(for: duplicate))
                )
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                isSaving = false
                return
            }

            let entitlement = ProEntitlementStorage.decode(entitlementRawValue)
            let gate = ProFeatureGate()
            let addedThisMonth = gate.showsAddedThisMonth(from: shows)
            guard gate.canAddShow(showsAddedThisMonth: addedThisMonth, entitlement: entitlement) else {
                PostHogSDK.shared.capture("pro_limit_reached")
                paywallSheet = .limit
                presentToast(.neutral, message: BSLocalization.text("保存上限"))
                isSaving = false
                return
            }

            switch AddShowLifecyclePolicy.resolution(for: show) {
            case .future:
                await persistPreparedShow(show, lifecycle: .future)
            case .ended:
                await persistPreparedShow(show, lifecycle: .ended)
            case .needsEndConfirmation:
                pendingLifecycleConfirmation = PendingAddShowLifecycleConfirmation(show: show)
                isSaving = false
            }
        } catch ShowValidationError.invalidEndTime {
            message = BSLocalization.text("结束时间需要晚于开始时间。")
            presentToast(.failure, message: BSLocalization.text("时间范围无效"))
            isSaving = false
        } catch ShowValidationError.missingStartTime {
            message = BSLocalization.text("请确认开场时间。")
            presentToast(.failure, message: BSLocalization.text("还缺开场时间"))
            isSaving = false
        } catch ShowValidationError.emptyName {
            message = BSLocalization.text("请填写现场名称。")
            presentToast(.failure, message: BSLocalization.text("保存失败"))
            isSaving = false
        } catch {
            modelContext.rollback()
            message = BSLocalization.text("请填写必填信息。")
            presentToast(.failure, message: BSLocalization.text("保存失败"))
            isSaving = false
        }
    }

    @MainActor
    private func persistPreparedShow(
        _ show: Show,
        lifecycle: AddShowFinalLifecycle
    ) async {
        isSaving = true
        do {
            let result = try AddShowPersistenceCoordinator.persist(
                show,
                lifecycle: lifecycle,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext
            )

            if let notificationState = result.notificationState {
                await activateNotifications(for: show, state: notificationState)
            }

            PostHogSDK.shared.capture("show_added", properties: [
                "method": sheet.rawValue,
                "lifecycle": result.outcome.rawValue
            ])
            AppReviewPrompt.consider(.addedShow)
            didSave = true
            coverLifecycle.finalize(keeping: draft.coverImageURL)

            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                savedShowConfirmation = SavedShowConfirmation(
                    showID: show.id,
                    name: show.name,
                    coverImageURL: show.coverImageURL,
                    kind: .saved(result.outcome)
                )
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSaving = false
            onSaved?(show.id)
        } catch AddShowPersistenceError.duplicateShow(let existingShowID) {
            modelContext.rollback()
            if let duplicate = shows.first(where: { $0.id == existingShowID }) {
                savedShowConfirmation = SavedShowConfirmation(
                    showID: duplicate.id,
                    name: duplicate.name,
                    coverImageURL: duplicate.coverImageURL,
                    kind: .duplicate(detailOutcome(for: duplicate))
                )
            } else {
                message = BSLocalization.text("这场已经在 BeforeShow 里了")
                presentToast(.neutral, message: BSLocalization.text("这场已经在 BeforeShow 里了"))
            }
            isSaving = false
        } catch {
            modelContext.rollback()
            message = BSLocalization.text("请填写必填信息。")
            presentToast(.failure, message: BSLocalization.text("保存失败"))
            isSaving = false
        }
    }

    private func detailOutcome(for show: Show) -> AddShowSaveOutcome {
        let state = CurrentShowTimeState(show: show, now: Date())
        if state.kind == .postShow || state.kind == .ended {
            return .footprint
        }
        if CurrentShowSession().isCurrent(
            show,
            among: shows,
            manualSelection: selections.first
        ) {
            return .current
        }
        return .future
    }

    private func presentDetail(for confirmation: SavedShowConfirmation) {
        detailTarget = AddShowDetailDestination(
            showID: confirmation.showID,
            kind: confirmation.outcome == .footprint ? .footprint : .show
        )
    }

    private func finishFlow() {
        if let onFinished {
            onFinished()
        } else {
            dismiss()
        }
    }

'''
    text = replace_between(text, start, end, replacement, "AddShow save block")

    start = "private struct SavedShowConfirmation: Equatable {"
    end = "private extension ShowDraft {"
    replacement = r'''private enum AddShowConfirmationKind: Equatable {
    case saved(AddShowSaveOutcome)
    case duplicate(AddShowSaveOutcome)

    var outcome: AddShowSaveOutcome {
        switch self {
        case .saved(let outcome), .duplicate(let outcome):
            return outcome
        }
    }

    var isDuplicate: Bool {
        if case .duplicate = self { return true }
        return false
    }
}

private struct SavedShowConfirmation: Equatable {
    let showID: UUID
    let name: String
    let coverImageURL: String?
    let kind: AddShowConfirmationKind

    var outcome: AddShowSaveOutcome { kind.outcome }
}

private enum AddShowDetailKind: Hashable {
    case show
    case footprint
}

private struct AddShowDetailDestination: Identifiable, Hashable {
    let showID: UUID
    let kind: AddShowDetailKind

    var id: String { "\(showID.uuidString)-\(kind)" }
}

private struct PendingAddShowLifecycleConfirmation: Identifiable {
    let id = UUID()
    let show: Show
}

private struct AddShowLifecycleConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let showName: String
    let showStart: Date
    let calendar: Calendar
    let onLive: () -> Void
    let onEnded: (Date) -> Void

    @State private var isConfirmingEndTime = false
    @State private var endTime: Date

    init(
        showName: String,
        showStart: Date,
        calendar: Calendar,
        now: Date = Date(),
        onLive: @escaping () -> Void,
        onEnded: @escaping (Date) -> Void
    ) {
        self.showName = showName
        self.showStart = showStart
        self.calendar = calendar
        self.onLive = onLive
        self.onEnded = onEnded
        _endTime = State(initialValue: max(showStart, now))
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            if isConfirmingEndTime {
                BSStageSheetHeader(
                    icon: "clock",
                    title: BSLocalization.text("实际几点结束？"),
                    subtitle: showName,
                    tint: BSColor.Stage.accent
                )

                BSSurfacePanel {
                    VStack(spacing: BSSpacing.sm) {
                        DatePicker(
                            BSLocalization.text("散场日期"),
                            selection: $endTime,
                            in: showStart...Date(),
                            displayedComponents: .date
                        )
                        DatePicker(
                            BSLocalization.text("散场时间"),
                            selection: $endTime,
                            in: showStart...Date(),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    .tint(BSColor.Stage.accent)
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
                }

                Button(BSLocalization.text("确认结束时间")) {
                    let confirmed = endTime
                    dismiss()
                    onEnded(confirmed)
                }
                .buttonStyle(BSPrimaryButtonStyle())
            } else {
                BSStageSheetHeader(
                    icon: "music.note",
                    title: BSLocalization.text("这场已经结束了吗？"),
                    subtitle: BSLocalization.text("我们看到这场已经开场，确认一下现在的状态。"),
                    tint: BSColor.Stage.accent
                )

                VStack(spacing: BSSpacing.sm) {
                    Button(BSLocalization.text("还在现场")) {
                        dismiss()
                        onLive()
                    }
                    .buttonStyle(BSPrimaryButtonStyle())

                    Button(BSLocalization.text("已经结束")) {
                        isConfirmingEndTime = true
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
            }
        }
    }
}

private struct AddShowSavedConfirmationView: View {
    let confirmation: SavedShowConfirmation
    let onOpen: () -> Void
    let onDone: () -> Void

    private var statusText: String? {
        guard !confirmation.kind.isDuplicate else { return nil }
        switch confirmation.outcome {
        case .future:
            return BSLocalization.text("已加入我的现场")
        case .current:
            return BSLocalization.text("已设为当前现场")
        case .footprint:
            return BSLocalization.text("已收进足迹")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: BSSpacing.xl)

            BSSurfacePanel {
                VStack(spacing: BSSpacing.lg) {
                    ZStack {
                        Circle()
                            .fill(BSColor.Stage.accent.opacity(0.16))
                            .frame(width: 58, height: 58)
                        Circle()
                            .stroke(BSColor.Stage.accent.opacity(0.46), lineWidth: 1)
                            .frame(width: 58, height: 58)
                        Image(systemName: confirmation.kind.isDuplicate ? "rectangle.on.rectangle" : "checkmark")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(BSColor.Stage.accent)
                    }

                    ShowCoverImageView(
                        urlString: confirmation.coverImageURL,
                        aspectRatio: 3.0 / 4.0,
                        contentMode: .fill,
                        cornerRadius: BSRadius.md
                    )
                    .frame(width: 96, height: 128)
                    .clipped()

                    VStack(spacing: BSSpacing.xs) {
                        Text(
                            BSLocalization.text(
                                confirmation.kind.isDuplicate
                                    ? "这场已经在 BeforeShow 里了"
                                    : "已添加现场"
                            )
                        )
                        .font(BSFont.heroTitle)
                        .foregroundColor(BSColor.Stage.foreground)
                        .multilineTextAlignment(.center)

                        Text(confirmation.name)
                            .font(BSFont.body)
                            .foregroundColor(BSColor.Stage.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        if let statusText {
                            Text(statusText)
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.Stage.dim)
                        }
                    }

                    VStack(spacing: 10) {
                        Button(action: onOpen) {
                            Text(
                                BSLocalization.text(
                                    confirmation.kind.isDuplicate
                                        ? "查看这场现场"
                                        : "查看现场"
                                )
                            )
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(BSColor.Stage.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)

                        Button(action: onDone) {
                            Text(BSLocalization.text("完成"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(BSColor.Stage.foreground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BSSpacing.sm)
            }
            .frame(maxWidth: 330)

            Spacer(minLength: BSSpacing.xl)
        }
        .padding(.horizontal, 20)
    }
}

'''
    text = replace_between(text, start, end, replacement, "AddShow success block")

    stale = [
        "AddShowIntent",
        "historicalBackfillRequiresCompletedShow",
        "upcomingRequiresActiveShow",
        "intent.saveButtonTitle",
        "intent: intent",
    ]
    leftovers = [token for token in stale if token in text]
    if leftovers:
        raise RuntimeError(f"AddShowFlowViews stale tokens: {leftovers}")
    write(rel, text)

    rel = "apps/ios/BeforeShow/FootprintsArchive.swift"
    text = read(rel)
    text = text.replace('actionTitle: BSLocalization.text("补录足迹")', 'actionTitle: BSLocalization.text("添加现场")')
    text = text.replace('actionTitle: BSLocalization.text("补录第一场足迹")', 'actionTitle: BSLocalization.text("添加现场")')
    text = text.replace("    @State private var pendingBackfillDetailID: UUID?\n", "")
    text = text.replace("            resolvePendingBackfillDetail()\n", "")
    old = '''            .sheet(isPresented: $isAddingShow, onDismiss: {
                resolvePendingBackfillDetail()
            }) {
                AddShowCoordinatorSheet(intent: .historicalBackfill) { showID in
                    pendingBackfillDetailID = showID
                }
                .presentationDetents([.large])
                .presentationCornerRadius(26)
                .presentationDragIndicator(.visible)
            }
'''
    new = '''            .sheet(isPresented: $isAddingShow) {
                AddShowCoordinatorSheet()
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
            }
'''
    text = replace_once(text, old, new, "Footprints add sheet")
    start_marker = "    /// Backfill detail navigation is state-driven rather than delay-driven:"
    end_marker = "    private func content(_ prepared: PreparedFootprint) -> some View {"
    if start_marker in text:
        text = replace_between(text, start_marker, end_marker, "", "Footprints backfill resolver")
    write(rel, text)

    rel = "apps/ios/BeforeShow/FootprintArchiveViews.swift"
    text = read(rel)
    old = '''            HStack(spacing: BSSpacing.sm) {
                dashboardIcon("magnifyingglass", label: BSLocalization.text("搜索足迹"), action: onSearch)
                dashboardIcon("square.and.arrow.up", label: BSLocalization.text("分享足迹"), action: onShare)
            }
'''
    new = '''            HStack(spacing: BSSpacing.sm) {
                dashboardIcon("plus", label: BSLocalization.text("添加现场"), action: onAdd)
                dashboardIcon("magnifyingglass", label: BSLocalization.text("搜索足迹"), action: onSearch)
                dashboardIcon("square.and.arrow.up", label: BSLocalization.text("分享足迹"), action: onShare)
            }
'''
    text = replace_once(text, old, new, "Footprint dashboard plus")
    write(rel, text)

    additions = {
        "apps/ios/BeforeShow/Resources/en.lproj/Localizable.strings": {
            "这场已经结束了吗？": "Has this show ended?",
            "我们看到这场已经开场，确认一下现在的状态。": "This show has already started. Confirm its current status.",
            "还在现场": "Still at the show",
            "已经结束": "It has ended",
            "实际几点结束？": "What time did it end?",
            "确认结束时间": "Confirm End Time",
            "已添加现场": "Show Added",
            "已加入我的现场": "Added to My Shows",
            "已设为当前现场": "Set as Current Show",
            "已收进足迹": "Added to Footprints",
            "查看现场": "View Show",
            "查看这场现场": "View This Show",
            "完成": "Done",
            "这场已经在 BeforeShow 里了": "This show is already in BeforeShow",
        },
        "apps/ios/BeforeShow/Resources/zh-Hant.lproj/Localizable.strings": {
            "这场已经结束了吗？": "這場已經結束了嗎？",
            "我们看到这场已经开场，确认一下现在的状态。": "我們看到這場已經開場，確認一下現在的狀態。",
            "还在现场": "還在現場",
            "已经结束": "已經結束",
            "实际几点结束？": "實際幾點結束？",
            "确认结束时间": "確認結束時間",
            "已添加现场": "已添加現場",
            "已加入我的现场": "已加入我的現場",
            "已设为当前现场": "已設為目前現場",
            "已收进足迹": "已收進足跡",
            "查看现场": "查看現場",
            "查看这场现场": "查看這場現場",
            "完成": "完成",
            "这场已经在 BeforeShow 里了": "這場已經在 BeforeShow 裡了",
        },
    }
    for rel, mapping in additions.items():
        text = read(rel)
        missing_lines = []
        for key, value in mapping.items():
            escaped_key = key.replace("\\", "\\\\").replace('"', '\\"')
            if f'"{escaped_key}" =' in text:
                continue
            escaped_value = value.replace("\\", "\\\\").replace('"', '\\"')
            missing_lines.append(f'"{escaped_key}" = "{escaped_value}";')
        if missing_lines:
            text = text.rstrip() + "\n\n/* Unified add show */\n" + "\n".join(missing_lines) + "\n"
        write(rel, text)

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"tests", "implementation"}:
        raise SystemExit("usage: implement_unified_add_show.py tests|implementation")
    if sys.argv[1] == "tests":
        patch_tests()
    else:
        patch_implementation()

if __name__ == "__main__":
    main()
