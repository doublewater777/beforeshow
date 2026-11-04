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

    @FocusState private var isNoteFocused: Bool
    @State private var editorialFontsReady = BSEditorialFontLoader.isSongtiAvailable

    private static let horizontalMargin: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    collageHero
                    titleBlock
                    moodSelectorSection
                    noteSection

                    if let commitError {
                        Text(commitError)
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.Stage.danger)
                    }
                }
                .padding(.horizontal, Self.horizontalMargin)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .id(editorialFontsReady)

            actionDock
                .padding(.horizontal, Self.horizontalMargin)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.compact)
        }
        .background(alignment: .top) { stageLight }
        .task {
            editorialFontsReady = await BSEditorialFontLoader.ensureSongtiAvailable()
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
    }

    private var calendar: Calendar { show.timingCalendar() }

    private var current: DispersalRating? {
        rating.flatMap(DispersalRating.from(rawValue:))
    }

    // MARK: Hero collage

    private var stageLight: some View {
        ZStack {
            RadialGradient(
                colors: [BSColor.Stage.accent.opacity(0.10), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 320
            )
            RadialGradient(
                colors: [BSColor.Stage.glowBlue.opacity(0.16), .clear],
                center: UnitPoint(x: 0, y: 0.25), startRadius: 0, endRadius: 280
            )
        }
        .frame(height: 520)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var collageHero: some View {
        ZStack(alignment: .topLeading) {
            DispersalPolaroid(coverURL: show.coverImageURL, imageWidth: 138)
                .rotationEffect(.degrees(-3))
                .shadow(color: BSColor.Stage.glowBlue.opacity(0.22), radius: 20, y: 18)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                .offset(y: 6)

            DispersalPostmark(
                city: FootprintTextNormalizer.nonEmptyTrimmed(show.city),
                date: BSDateFormat.dottedDate(show.effectiveDate, calendar: calendar),
                ink: BSColor.Stage.accent,
                knockout: BSColor.Stage.background
            )
            .rotationEffect(.degrees(-14))
            .opacity(0.85)
            .offset(x: 112, y: 152)
        }
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            DispersalDateColumn(
                stamp: DispersalCeremonyCardCopy.dateStamp(for: show.effectiveDate, calendar: calendar),
                caption: DispersalCeremonyCardCopy.dateCaption(for: show.effectiveDate, calendar: calendar),
                numeralSize: 76,
                color: BSColor.Stage.heroIvory,
                captionColor: BSColor.Stage.muted
            )
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BSLocalization.format("第 %lld 场", identity.showOrdinal))
                .font(BSFont.V3.caption)
                .tracking(BSFont.Editorial.kickerTracking)
                .foregroundStyle(BSColor.Stage.muted)

            Text(DispersalCeremonyCardCopy.serifTitle(show.name))
                .font(BSFont.Editorial.song(size: 28, weight: .black))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let facts = DispersalCeremonyCardCopy.factsLine(
                startTime: show.startTime,
                endedAt: show.endedAt,
                calendar: calendar
            ) {
                Text(facts)
                    .font(BSFont.Editorial.numerals(size: 15, italic: true))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Rating

    private func kicker(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(BSFont.V3.caption)
                .tracking(BSFont.Editorial.kickerTracking)
                .foregroundStyle(BSColor.Stage.muted)
            Rectangle()
                .fill(BSColor.Stage.border)
                .frame(height: 1)
        }
    }

    private var moodSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                kicker(BSLocalization.text("今晚"))
                if let current {
                    Text(current.sub)
                        .font(BSFont.Editorial.song(size: 13, weight: .bold))
                        .foregroundStyle(current.stageInk)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            HStack(spacing: 0) {
                ForEach(DispersalRating.allCases) { node in
                    ratingButton(node)
                }
            }
        }
    }

    private func ratingButton(_ node: DispersalRating) -> some View {
        let selected = node.rawValue == rating
        return Button {
            rating = node.rawValue
        } label: {
            Text(node.label)
                .font(BSFont.Editorial.song(size: 15, weight: selected ? .black : .regular))
                .foregroundStyle(selected ? node.stageInk : BSColor.Stage.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget + 4)
                .background {
                    if selected {
                        DispersalHandCircle()
                            .trim(from: 0, to: 1)
                            .stroke(node.stageInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .frame(width: 68, height: 40)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: rating)
        .accessibilityLabel(node.accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                kicker(BSLocalization.text("那天"))
                Text(verbatim: "\(note.count) / \(DispersalCeremonyPolicy.maximumNoteLength)")
                    .font(BSFont.Editorial.numerals(size: 13))
                    .foregroundStyle(BSColor.Stage.muted)
                    .monospacedDigit()
                    .fixedSize()
            }

            DispersalRuledNoteField(
                text: $note,
                placeholder: BSLocalization.text("写点今晚的记忆或安可时刻..."),
                ink: BSColor.Stage.foreground,
                ruleColor: BSColor.Stage.border,
                focus: $isNoteFocused
            )
            .onChange(of: note) { _, newValue in
                if newValue.count > DispersalCeremonyPolicy.maximumNoteLength {
                    note = String(newValue.prefix(DispersalCeremonyPolicy.maximumNoteLength))
                }
            }
            .dispersalMatchedGeometry(id: "dispersal.note", namespace: transitionNamespace)
            .accessibilityLabel(BSLocalization.text("散场文字"))
        }
    }

    // MARK: Actions

    private var actionDock: some View {
        VStack(spacing: 2) {
            Button(action: generate) {
                HStack(spacing: BSSpacing.sm) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BSColor.Stage.background)
                    }
                    Text(commitTitle)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BSColor.Stage.background)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(BSColor.Stage.accent))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            if let onFinishWithoutCard {
                Button {
                    isNoteFocused = false
                    onFinishWithoutCard()
                } label: {
                    Text(BSLocalization.text("只存进足迹"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(BSColor.Stage.muted)
                        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
    }

    private func generate() {
        isNoteFocused = false
        onGenerate()
    }
}
