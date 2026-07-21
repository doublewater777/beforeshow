import MapKit
import SwiftData
import SwiftUI

enum TravelPlanFormValidation {
    static func canSubmitMapRoute(
        origin: TravelPlace?,
        destination: TravelPlace?,
        requiresExplicitTime: Bool,
        hasEnteredTargetTime: Bool
    ) -> Bool {
        origin != nil && destination != nil && (!requiresExplicitTime || hasEnteredTargetTime)
    }
}

struct RoundTripPlanView: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [RoundTripPlan]

    @State private var selectedMode: TravelMode = .driving
    @State private var originQuery = ""
    @State private var destinationQuery = ""
    @State private var selectedOrigin: TravelPlace?
    @State private var selectedDestination: TravelPlace?
    @State private var originSuggestions: [TravelPlace] = []
    @State private var destinationSuggestions: [TravelPlace] = []
    @State private var targetTime = Date()
    @State private var customSummary = ""
    @State private var customLeaveAt = Date()
    @State private var customArriveAt = Date()
    @State private var isGenerating = false
    @State private var isLocating = false
    @State private var hasEnteredTargetTime = false
    @State private var showsTransitDurationFallback = false
    @State private var manualTransitDurationText = ""
    @State private var errorMessage: String?
    @State private var didBootstrap = false
    @State private var originSearchTask: Task<Void, Never>?
    @State private var destinationSearchTask: Task<Void, Never>?
    @StateObject private var locator: OriginLocator

    private var session: DeparturePlanSession { DeparturePlanSession(show: show) }

    init(show: Show) {
        self.show = show
        let showID = show.id
        _plans = Query(
            filter: #Predicate<RoundTripPlan> { $0.showID == showID },
            sort: [SortDescriptor(\RoundTripPlan.updatedAt, order: .reverse)]
        )
        _locator = StateObject(wrappedValue: OriginLocator())
    }

    private var plan: RoundTripPlan? { plans.first }

    private var direction: RoundTripDirection {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BS_TRANSIT_FALLBACK_SCREENSHOT"] == "1" {
            return .return
        }
        if let forced = ProcessInfo.processInfo.environment["BS_ROUTE_FORM_DIRECTION"] {
            return forced == "return" ? .return : .outbound
        }
        #endif
        if show.changeStatus == .postponed, show.postponedDate == nil { return .outbound }
        return Date() >= session.effectiveStartDate ? RoundTripDirection.return : RoundTripDirection.outbound
    }

    private var sheetTitle: String {
        direction == .outbound ? "生成去程" : "备好返程"
    }

    private var canSubmit: Bool {
        if selectedMode == .custom {
            return selectedOrigin != nil
                && selectedDestination != nil
                && !customSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && customArriveAt > customLeaveAt
        }
        let requiresExplicitTime = show.changeStatus == .postponed && show.postponedDate == nil
        let canSubmitRoute = TravelPlanFormValidation.canSubmitMapRoute(
            origin: selectedOrigin,
            destination: selectedDestination,
            requiresExplicitTime: requiresExplicitTime,
            hasEnteredTargetTime: hasEnteredTargetTime
        )
        if selectedMode == .transit, showsTransitDurationFallback {
            return canSubmitRoute && manualTransitDurationMinutes != nil
        }
        return canSubmitRoute
    }

    private var manualTransitDurationMinutes: Int? {
        guard let minutes = Int(manualTransitDurationText), minutes > 0 else { return nil }
        return minutes
    }

    private var submissionGuidance: String? {
        if selectedOrigin == nil {
            return "请先从地点列表选择出发点"
        }
        if selectedDestination == nil {
            return direction == .return
                ? "请先从地点列表选择返程目的地"
                : "请先从地点列表确认场馆位置"
        }
        if selectedMode == .custom {
            if customSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "请填写这段自定义路程的安排说明"
            }
            if customArriveAt <= customLeaveAt {
                return "预计到达时间需要晚于出发时间"
            }
        }
        if show.changeStatus == .postponed, show.postponedDate == nil, !hasEnteredTargetTime {
            return "请填写新的日期和时间"
        }
        if selectedMode == .transit, showsTransitDurationFallback, manualTransitDurationMinutes == nil {
            return "请填写预计用时"
        }
        return nil
    }

    var body: some View {
        ScrollView {
            StageBottomSheet(title: sheetTitle, onClose: { dismiss() }) {
                if show.changeStatus == .canceled {
                    InlineStatus(text: "这场已取消，无需安排出行", tone: .error)
                } else {
                    formContent
                }
            }
        }
        .background(BSColor.Stage.surfaceRaised.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await bootstrapIfNeeded() }
        .onChange(of: originQuery) { _, newValue in
            scheduleOriginSearch(newValue)
        }
        .onChange(of: destinationQuery) { _, newValue in
            scheduleDestinationSearch(newValue)
        }
    }

    @ViewBuilder
    private var formContent: some View {
        IconModeSelector(
            options: TravelMode.allCases,
            selection: $selectedMode,
            symbol: { $0.iconName },
            label: { $0.displayName }
        )

        if direction == .outbound {
            placeField(
                label: "出发地",
                query: $originQuery,
                selected: selectedOrigin,
                suggestions: originSuggestions,
                placeholder: "我的位置",
                onSelect: { place in
                    selectedOrigin = place
                    originQuery = place.name
                    originSuggestions = []
                },
                onLocate: { Task { await locateOrigin() } }
            )
        } else {
            returnOriginField
        }

        if direction == .return {
            placeField(
                label: "返程目的地",
                query: $destinationQuery,
                selected: selectedDestination,
                suggestions: destinationSuggestions,
                placeholder: "回家 / 目的地",
                onSelect: { place in
                    selectedDestination = place
                    destinationQuery = place.name
                    destinationSuggestions = []
                },
                onLocate: nil
            )
        } else {
            destinationReadOnly
        }

        if selectedMode == .custom {
            customFields
        } else {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text(direction == .outbound ? "希望到达" : "离开时间")
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { targetTime },
                        set: { value in
                            targetTime = value
                            hasEnteredTargetTime = true
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .colorScheme(.dark)
                if direction == .outbound, !(show.changeStatus == .postponed && show.postponedDate == nil) {
                    HStack(spacing: BSSpacing.sm) {
                        arrivalChip("开场前 1 小时", minutesBefore: 60)
                        arrivalChip("30 分钟", minutesBefore: 30)
                        arrivalChip("15 分钟", minutesBefore: 15)
                    }
                }
                if direction == .return {
                    HStack(spacing: BSSpacing.sm) {
                        timeChip("现在就走", date: Date())
                        if let showEnd = session.estimatedShowEndAt, showEnd > Date() {
                            timeChip("散场后 15 分钟", date: showEnd.addingTimeInterval(15 * 60))
                        }
                    }
                }
            }

            if selectedMode == .transit, showsTransitDurationFallback {
                transitDurationFallbackField
            }
        }

        if let errorMessage {
            InlineStatus(text: errorMessage, tone: .error)
        } else if let submissionGuidance {
            InlineStatus(text: submissionGuidance, tone: .neutral)
        }

        Button {
            Task { await submit() }
        } label: {
            Text(isGenerating ? "生成中…" : (direction == .outbound ? "生成去程" : "生成返程"))
        }
        .buttonStyle(StageSubmitButtonStyle())
        .disabled(!canSubmit || isGenerating || show.changeStatus == .canceled)
    }

    private var returnOriginField: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack {
                Text("出发点（场馆）")
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                Spacer()
                if selectedOrigin != nil {
                    Button("更改") {
                        selectedOrigin = nil
                        originQuery = ""
                        originSuggestions = []
                    }
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.accent)
                }
            }
            if let selectedOrigin {
                confirmedPlaceRow(selectedOrigin)
            } else {
                placeField(
                    label: "搜索出发地点",
                    query: $originQuery,
                    selected: nil,
                    suggestions: originSuggestions,
                    placeholder: "场馆 / 离开地点",
                    onSelect: { place in
                        selectedOrigin = place
                        originQuery = place.name
                        originSuggestions = []
                    },
                    onLocate: nil
                )
            }
        }
    }

    private var destinationReadOnly: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("到达地")
                .font(BSFont.V3.caption)
                .foregroundStyle(BSColor.Stage.dim)
            if let selectedDestination {
                confirmedPlaceRow(selectedDestination)
            } else {
                placeField(
                    label: "确认场馆位置",
                    query: $destinationQuery,
                    selected: nil,
                    suggestions: destinationSuggestions,
                    placeholder: show.departureDestination.text.isEmpty ? "搜索场馆" : show.departureDestination.text,
                    onSelect: { place in
                        selectedDestination = place
                        destinationQuery = place.name
                        destinationSuggestions = []
                    },
                    onLocate: nil
                )
            }
            if let guidance = show.departureDestination.guidance {
                InlineStatus(text: guidance, tone: .neutral)
            }
        }
    }

    /// 已确认地点的只读展示，容器与输入框选中态一致（surface + accent 描边）。
    private func confirmedPlaceRow(_ place: TravelPlace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place.name)
                .font(BSFont.V3.body)
                .foregroundStyle(BSColor.Stage.foreground)
            Text(place.address)
                .font(BSFont.V3.small)
                .foregroundStyle(BSColor.Stage.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                .stroke(BSColor.Stage.accent.opacity(0.5), lineWidth: 1)
        }
    }

    private var customFields: some View {
        VStack(alignment: .leading, spacing: BSSpacing.roomy) {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text("出发时间")
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { customLeaveAt },
                        set: { value in
                            customLeaveAt = value
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                    .labelsHidden()
                    .colorScheme(.dark)
            }
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text("预计到达")
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { customArriveAt },
                        set: { value in
                            customArriveAt = value
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                    .labelsHidden()
                    .colorScheme(.dark)
            }
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text("安排说明")
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                TextField("例如：接驳车 / 包车", text: $customSummary)
                    .textFieldStyle(.plain)
                    .padding(BSSpacing.compact)
                    .background(BSColor.Stage.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
                    .foregroundStyle(BSColor.Stage.foreground)
            }
        }
    }

    private var transitDurationFallbackField: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("预计用时")
                .font(BSFont.V3.caption)
                .foregroundStyle(BSColor.Stage.dim)
            HStack(spacing: BSSpacing.sm) {
                TextField("例如 45", text: $manualTransitDurationText)
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
                    .foregroundStyle(BSColor.Stage.foreground)
                Text("分钟")
                    .font(BSFont.V3.small)
                    .foregroundStyle(BSColor.Stage.muted)
            }
            .padding(BSSpacing.compact)
            .background(BSColor.Stage.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))

            InlineStatus(
                text: "暂时没拿到公共交通预计用时，可以手动填写后继续生成",
                tone: .neutral
            )
        }
    }

    private func placeField(
        label: String,
        query: Binding<String>,
        selected: TravelPlace?,
        suggestions: [TravelPlace],
        placeholder: String,
        onSelect: @escaping (TravelPlace) -> Void,
        onLocate: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack {
                Text(label)
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                Spacer()
                if let onLocate {
                    Button(isLocating ? "定位中…" : "我的位置", action: onLocate)
                        .font(BSFont.V3.caption)
                        .foregroundStyle(BSColor.Stage.accent)
                        .disabled(isLocating)
                }
            }
            TextField(placeholder, text: query)
                .textFieldStyle(.plain)
                .padding(BSSpacing.compact)
                .background(BSColor.Stage.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
                .foregroundStyle(BSColor.Stage.foreground)
                .overlay {
                    RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                        .stroke(
                            selected != nil ? BSColor.Stage.accent.opacity(0.5) : BSColor.Stage.border,
                            lineWidth: 1
                        )
                }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.prefix(6).enumerated()), id: \.offset) { _, place in
                        Button {
                            onSelect(place)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(BSFont.V3.small.weight(.medium))
                                    .foregroundStyle(BSColor.Stage.foreground)
                                Text(place.address)
                                    .font(BSFont.V3.caption)
                                    .foregroundStyle(BSColor.Stage.muted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BSSpacing.compact)
                .background(BSColor.Stage.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
            }
        }
    }

    private func arrivalChip(_ title: String, minutesBefore: Int) -> some View {
        timeChip(title, date: session.effectiveStartDate.addingTimeInterval(TimeInterval(-minutesBefore * 60)))
    }

    private func timeChip(_ title: String, date: Date) -> some View {
        let isSelected = targetTime == date
        return Button {
            targetTime = date
            hasEnteredTargetTime = true
        } label: {
            Text(title)
                .font(BSFont.V3.caption)
                .foregroundStyle(isSelected ? BSColor.Stage.accent : BSColor.Stage.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isSelected ? BSColor.Stage.accent.opacity(0.14) : BSColor.Stage.surfaceRaised)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? BSColor.Stage.accent.opacity(0.38) : .clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        if direction == .outbound {
            targetTime = session.defaultTargetArrivalAt
            customLeaveAt = targetTime.addingTimeInterval(-3_600)
            customArriveAt = targetTime
            await resolveOutboundDestination()
            await locateOrigin()
        } else {
            targetTime = session.defaultReturnLeaveAt()
            customLeaveAt = targetTime
            customArriveAt = targetTime.addingTimeInterval(3_600)
            if let outbound = plan?.outboundPlan {
                selectedMode = outbound.mode
                selectedOrigin = outbound.destination
                originQuery = outbound.destination.name
                selectedDestination = outbound.origin
                destinationQuery = outbound.origin.name
            } else {
                selectedDestination = nil
                await resolveReturnOriginFromVenue()
            }
        }

        if let existing = plan?.plan(for: direction) {
            selectedMode = existing.mode
            selectedOrigin = existing.origin
            originQuery = existing.origin.name
            selectedDestination = existing.destination
            destinationQuery = existing.destination.name
            if direction == .outbound {
                targetTime = existing.arriveAt
            } else {
                targetTime = existing.leaveAt
                hasEnteredTargetTime = true
            }
            if existing.mode == .custom {
                customLeaveAt = existing.leaveAt
                customArriveAt = existing.arriveAt
                customSummary = existing.summary
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.environment["BS_TRANSIT_FALLBACK_SCREENSHOT"] == "1" {
            selectedMode = .transit
            showsTransitDurationFallback = true
            manualTransitDurationText = "45"
        }
        #endif
    }

    @MainActor
    private func resolveOutboundDestination() async {
        let dest = show.departureDestination
        switch dest.quality {
        case .precise:
            if let place = await TravelPlaceSearch.geocodeAddress(
                dest.text,
                name: dest.venueName ?? dest.text
            ) {
                selectedDestination = place
                destinationQuery = place.name
            } else {
                destinationQuery = dest.text
            }
        case .approximate, .weak, .missing:
            destinationQuery = dest.text
        }
    }

    @MainActor
    private func resolveReturnOriginFromVenue() async {
        let dest = show.departureDestination
        if let place = await TravelPlaceSearch.resolve(text: dest.text, regionHint: show.city) {
            selectedOrigin = place
            originQuery = place.name
        }
    }

    @MainActor
    private func locateOrigin() async {
        isLocating = true
        defer { isLocating = false }
        do {
            let resolved = try await locator.requestCurrentOrigin()
            selectedOrigin = resolved.place
            originQuery = resolved.place.name
            errorMessage = nil
        } catch {
            selectedOrigin = nil
            originQuery = ""
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "暂时拿不到当前位置，请搜索地点。"
        }
    }

    private func scheduleOriginSearch(_ query: String) {
        originSearchTask?.cancel()
        if let selectedOrigin, selectedOrigin.name == query { return }
        if selectedOrigin != nil, selectedOrigin?.name != query {
            selectedOrigin = nil
        }
        originSearchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            let results = await TravelPlaceSearch.suggestions(matching: query, regionHint: show.city)
            await MainActor.run { originSuggestions = results }
        }
    }

    private func scheduleDestinationSearch(_ query: String) {
        destinationSearchTask?.cancel()
        if let selectedDestination, selectedDestination.name == query { return }
        if selectedDestination != nil, selectedDestination?.name != query {
            selectedDestination = nil
        }
        destinationSearchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            let results = await TravelPlaceSearch.suggestions(matching: query, regionHint: show.city)
            await MainActor.run { destinationSuggestions = results }
        }
    }

    @MainActor
    private func submit() async {
        guard show.changeStatus != .canceled else { return }
        guard let origin = selectedOrigin, let destination = selectedDestination else { return }

        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let travelPlan: TravelPlan
            if selectedMode == .custom {
                travelPlan = TravelPlan.custom(
                    direction: direction,
                    origin: origin,
                    destination: destination,
                    leaveAt: customLeaveAt,
                    arriveAt: customArriveAt,
                    summary: customSummary,
                    showFingerprint: session.showFingerprint
                )
            } else if selectedMode == .transit,
                      showsTransitDurationFallback,
                      let manualTransitDurationMinutes {
                travelPlan = session.generateTransitEstimate(
                    direction: direction,
                    origin: origin,
                    destination: destination,
                    targetTime: targetTime,
                    durationMinutes: manualTransitDurationMinutes
                )
            } else {
                travelPlan = try await session.generate(
                    direction: direction,
                    mode: selectedMode,
                    origin: origin,
                    destination: destination,
                    targetTime: targetTime
                )
            }
            let store = session.ensurePlan(existing: plan, in: modelContext)
            try session.save(travelPlan, to: store, in: modelContext)
            dismiss()
        } catch {
            if selectedMode == .transit {
                showsTransitDurationFallback = true
                errorMessage = nil
            } else {
                errorMessage = "暂时没查到路线，请换个方式或稍后重试"
            }
        }
    }
}
