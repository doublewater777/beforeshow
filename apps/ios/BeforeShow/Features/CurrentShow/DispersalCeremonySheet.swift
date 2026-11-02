import SwiftUI

struct DispersalCeremonySheet: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let onCommit: (_ rating: Int?, _ note: String?, _ generatesCard: Bool?) async throws -> Void

    enum Step: Equatable {
        case combined
        case share
    }

    /// 提交成功后的去向。足迹详情编辑只保存并关闭，不进入散场卡。
    enum Destination: Equatable {
        case combined
        case share
        case dismiss
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    @State private var draftRating: Int?
    @State private var draftNote: String
    @State private var saving = false
    @State private var exportBusy = false
    @State private var commitError: String?
    @State private var cardCompletionFeedback = 0
    @Namespace private var cardNamespace
    private let customHeaderTitle: String?
    private let presentsShareAfterCommit: Bool

    init(
        show: Show,
        identity: FootprintDetailIdentity,
        initialStep: Step? = nil,
        headerTitle: String? = nil,
        presentsShareAfterCommit: Bool = true,
        onCommit: @escaping (_ rating: Int?, _ note: String?, _ generatesCard: Bool?) async throws -> Void
    ) {
        self.show = show
        self.identity = identity
        self.customHeaderTitle = headerTitle
        self.presentsShareAfterCommit = presentsShareAfterCommit
        self.onCommit = onCommit
        _step = State(initialValue: initialStep ?? Self.defaultStep(for: show))
        _draftRating = State(initialValue: show.rating)
        _draftNote = State(initialValue: show.closingNote ?? "")
    }

    /// Legacy completed records have no card-choice field, so retain their old share landing.
    static func defaultStep(for show: Show) -> Step {
        show.hasCompletedDispersalCeremony && show.hasGeneratedDispersalCard != false
            ? .share : .combined
    }

    var body: some View {
        NavigationStack {
            stepContent
                .navigationBarTitleDisplayMode(.inline)
                .background(BSColor.Stage.background.ignoresSafeArea())
        }
        .tint(BSColor.Stage.foreground)
        .interactiveDismissDisabled(saving || exportBusy)
        .sensoryFeedback(.impact(weight: .light), trigger: cardCompletionFeedback)
    }

    private var stepContent: some View {
        Group {
            switch step {
            case .combined:
                DispersalCombinedStep(
                    show: show,
                    identity: identity,
                    rating: $draftRating,
                    note: $draftNote,
                    headerTitle: customHeaderTitle,
                    commitTitle: presentsShareAfterCommit
                        ? BSLocalization.text("生成散场卡")
                        : BSLocalization.text("保存"),
                    isSaving: saving,
                    commitError: commitError,
                    transitionNamespace: reduceMotion ? nil : cardNamespace,
                    onClose: closeWithoutSaving,
                    onGenerate: {
                        Task { await advanceCombined(generatesCard: true) }
                    },
                    onFinishWithoutCard: presentsShareAfterCommit ? {
                        Task { await advanceCombined(generatesCard: false) }
                    } : nil
                )
                .transition(.opacity)

            case .share:
                DispersalShareStep(
                    show: show,
                    identity: identity,
                    rating: draftRating,
                    note: draftNote,
                    transitionNamespace: reduceMotion ? nil : cardNamespace,
                    onBack: { transition(to: .combined) },
                    onDone: { dismiss() },
                    onBusyChange: { exportBusy = $0 }
                )
                .transition(.opacity)
            }
        }
    }

    private func closeWithoutSaving() {
        ProductAnalytics.capture(.dispersalCeremonySkipped(showID: show.id, trigger: "close"))
        dismiss()
    }

    @MainActor
    private func advanceCombined(generatesCard: Bool) async {
        guard !saving else { return }
        saving = true
        commitError = nil

        let trimmedNote = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteToSave = trimmedNote.isEmpty ? nil : draftNote

        do {
            try await onCommit(
                draftRating,
                noteToSave,
                presentsShareAfterCommit ? generatesCard : nil
            )
            ProductAnalytics.capture(.dispersalCeremonyCompleted(
                showID: show.id, rating: draftRating, hasNote: noteToSave != nil
            ))
            switch Self.nextDestination(
                after: .combined,
                commitSucceeded: true,
                presentsShareAfterCommit: presentsShareAfterCommit,
                generatesCard: generatesCard
            ) {
            case .share:
                transition(to: .share, producesCardFeedback: true)
            case .dismiss:
                dismiss()
            case .combined:
                break
            }
        } catch {
            commitError = BSLocalization.text("散场记录没有保存，请重试")
        }

        saving = false
    }

    private func transition(to target: Step, producesCardFeedback: Bool = false) {
        let duration = reduceMotion
            ? DispersalCeremonyPolicy.reduceMotionCardTransitionDuration
            : DispersalCeremonyPolicy.cardTransitionDuration

        withAnimation(.easeInOut(duration: duration)) {
            step = target
        }

        guard producesCardFeedback else { return }
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            if step == .share {
                cardCompletionFeedback += 1
            }
        }
    }

    /// Pure navigation rule used by the feature tests.
    nonisolated static func nextDestination(
        after current: Step,
        commitSucceeded: Bool = true,
        presentsShareAfterCommit: Bool = true,
        generatesCard: Bool = true
    ) -> Destination {
        switch current {
        case .combined:
            guard commitSucceeded else { return .combined }
            return presentsShareAfterCommit && generatesCard ? .share : .dismiss
        case .share:
            return .share
        }
    }
}

// MARK: - Emotion + note

struct DispersalCombinedStep: View {
    let show: Show
    let identity: FootprintDetailIdentity
    @Binding var rating: Int?
    @Binding var note: String
    var headerTitle: String? = nil
    var commitTitle: String = BSLocalization.text("保存并查看")
    let isSaving: Bool
    var commitError: String? = nil
    let transitionNamespace: Namespace.ID?
    let onClose: () -> Void
    let onGenerate: () -> Void
    var onFinishWithoutCard: (() -> Void)? = nil

    @State private var raw: Double = 3
    @State private var emojiBump = false
    @FocusState private var isNoteFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    showMiniCard

                    moodSelectorSection

                    noteSection

                    if let commitError {
                        Text(commitError)
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.Stage.danger)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, BSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)

            actionDock
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .navigationTitle(headerTitle ?? BSLocalization.text("散场短评"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.muted)
                }
                .accessibilityLabel(BSLocalization.text("关闭散场仪式"))
            }
        }
        .onAppear {
            raw = Double(rating ?? 3)
        }
        .onChange(of: rating) { _, _ in
            bumpEmoji()
        }
    }

    private var formattedDateAndCity: String {
        let dateStr = BSDateFormat.dottedDate(show.effectiveDate, calendar: show.timingCalendar())
        let cityStr = FootprintTextNormalizer.nonEmptyTrimmed(show.city)
        return [dateStr, cityStr].compactMap { $0 }.joined(separator: " · ")
    }

    private var dispersalTimeSummary: String? {
        guard let endedAt = show.endedAt else { return nil }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = show.timingCalendar().timeZone
        return BSLocalization.format("%@ 散场", timeFormatter.string(from: endedAt))
    }

    private var showDurationSummary: String? {
        let start = show.startTime
        let end = show.endedAt ?? Date()
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        guard minutes > 0 else { return nil }
        return BSLocalization.format("历时 %@", ShowDurationFormatter.single(totalMinutes: minutes))
    }

    private var showMiniCard: some View {
        HStack(spacing: 12) {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                enforcesAspectRatio: true,
                cornerRadius: 8,
                restoresPersistedImageOnFirstFrame: true
            )
            .frame(width: 54, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(show.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(2)

                if !formattedDateAndCity.isEmpty {
                    Text(formattedDateAndCity)
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    if let duration = showDurationSummary {
                        Text(duration)
                        Text("·")
                    }
                    if let ended = dispersalTimeSummary {
                        Text(ended)
                        Text("·")
                    }
                    Text(BSLocalization.format("第 %lld 场", identity.showOrdinal))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BSColor.Stage.accent)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BSColor.Stage.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )
        )
    }

    private var moodSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(BSLocalization.text("现场感受"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                if let current {
                    Text(BSLocalization.format("%@，%@", current.label, current.sub))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(current.tint)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 7) {
                ForEach(DispersalRating.allCases) { node in
                    let selected = node.rawValue == rating
                    Button {
                        rating = node.rawValue
                        raw = Double(node.rawValue)
                    } label: {
                        VStack(spacing: 4) {
                            Text(node.emoji)
                                .font(.system(size: selected ? 19 : 17))
                                .scaleEffect(selected ? 1.08 : 1.0)
                            Text(node.label)
                                .font(.system(size: 10, weight: selected ? .bold : .medium))
                                .foregroundStyle(selected ? BSColor.Stage.foreground : BSColor.Stage.dim)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(selected ? node.tint.opacity(0.18) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(selected ? node.tint : BSColor.Stage.border, lineWidth: selected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.32, dampingFraction: 0.7), value: rating)
                    .accessibilityLabel(node.accessibilityLabel)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BSLocalization.text("散场短评（可选）"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)

            BSSurfacePanel {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        BSLocalization.text("写点今晚的记忆或安可时刻..."),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(4...7)
                    .font(BSFont.body)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .tint(BSColor.Stage.accent)
                    .focused($isNoteFocused)
                    .onChange(of: note) { _, newValue in
                        if newValue.count > DispersalCeremonyPolicy.maximumNoteLength {
                            note = String(newValue.prefix(DispersalCeremonyPolicy.maximumNoteLength))
                        }
                    }
                    .dispersalMatchedGeometry(
                        id: "dispersal.note",
                        namespace: transitionNamespace
                    )
                    .accessibilityLabel(BSLocalization.text("散场文字"))

                    HStack {
                        Spacer()
                        Text("\(note.count)/\(DispersalCeremonyPolicy.maximumNoteLength)")
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.Stage.dim)
                    }
                }
            }
        }
    }

    private var actionDock: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if let onFinishWithoutCard {
                    Button {
                        isNoteFocused = false
                        onFinishWithoutCard()
                    } label: {
                        Text(BSLocalization.text("直接完成"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(BSColor.Stage.muted)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }

                Button(action: generate) {
                    HStack(spacing: 5) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(BSColor.Stage.background)
                        } else {
                            Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(commitTitle)
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.background)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(BSColor.Stage.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }

            if onFinishWithoutCard != nil {
                Text(BSLocalization.text("直接完成仅保存到足迹，稍后也可随时生成散场卡"))
                    .font(.system(size: 11))
                    .foregroundStyle(BSColor.Stage.dim)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var current: DispersalRating? {
        guard let rating else { return nil }
        return DispersalRating.from(rawValue: rating)
    }

    private func generate() {
        isNoteFocused = false
        onGenerate()
    }

    private func bumpEmoji() {
        guard !reduceMotion else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
            emojiBump = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                emojiBump = false
            }
        }
    }
}

