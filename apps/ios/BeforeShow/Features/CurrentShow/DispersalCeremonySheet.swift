import PostHog
import SwiftUI

struct DispersalCeremonySheet: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let onCommit: (_ rating: Int?, _ note: String?) async throws -> Void

    enum Step: Equatable {
        case combined
        case share
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

    init(
        show: Show,
        identity: FootprintDetailIdentity,
        onCommit: @escaping (_ rating: Int?, _ note: String?) async throws -> Void
    ) {
        self.show = show
        self.identity = identity
        self.onCommit = onCommit
        _step = State(initialValue: show.hasCompletedDispersalCeremony ? .share : .combined)
        _draftRating = State(initialValue: show.rating)
        _draftNote = State(initialValue: show.closingNote ?? "")
    }

    var body: some View {
        Group {
            switch step {
            case .combined:
                DispersalCombinedStep(
                    rating: $draftRating,
                    note: $draftNote,
                    isSaving: saving,
                    commitError: commitError,
                    transitionNamespace: reduceMotion ? nil : cardNamespace,
                    onClose: closeWithoutSaving,
                    onGenerate: {
                        Task { await advanceCombined() }
                    }
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
        .interactiveDismissDisabled(saving || exportBusy)
        .sensoryFeedback(.impact(weight: .light), trigger: cardCompletionFeedback)
    }

    private func closeWithoutSaving() {
        PostHogSDK.shared.capture(
            "dispersal_ceremony_skipped",
            properties: ["trigger": "close"]
        )
        dismiss()
    }

    @MainActor
    private func advanceCombined() async {
        guard !saving else { return }
        saving = true
        commitError = nil

        let trimmedNote = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteToSave = trimmedNote.isEmpty ? nil : draftNote

        do {
            try await onCommit(draftRating, noteToSave)
            var properties: [String: Any] = [
                "has_rating": draftRating != nil,
                "has_note": noteToSave != nil
            ]
            if let draftRating {
                properties["rating_value"] = draftRating
            }
            PostHogSDK.shared.capture(
                "dispersal_ceremony_completed",
                properties: properties
            )
            transition(to: .share, producesCardFeedback: true)
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
    nonisolated static func nextStep(
        after current: Step,
        commitSucceeded: Bool = true
    ) -> Step {
        switch current {
        case .combined:
            return commitSucceeded ? .share : .combined
        case .share:
            return .share
        }
    }
}

// MARK: - Emotion + note

struct DispersalCombinedStep: View {
    @Binding var rating: Int?
    @Binding var note: String
    let isSaving: Bool
    var commitError: String? = nil
    let transitionNamespace: Namespace.ID?
    let onClose: () -> Void
    let onGenerate: () -> Void

    @State private var raw: Double = 3
    @State private var emojiBump = false
    @FocusState private var isNoteFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(BSLocalization.text("这一场怎么样？"))
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(BSColor.Stage.foreground)

                    ratingHero
                        .padding(.top, 18)

                    noteBlock
                        .padding(.top, 18)

                    if let commitError {
                        Text(commitError)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Stage.danger)
                            .padding(.top, BSSpacing.sm)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, BSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)

            Button(action: generate) {
                HStack(spacing: BSSpacing.sm) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BSColor.Stage.background)
                    }
                    Text(BSLocalization.text("看看散场卡"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isSaving)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isNoteFocused = false
        }
        .onAppear {
            raw = Double(rating ?? 3)
        }
        .onChange(of: rating) { _, _ in
            bumpEmoji()
        }
    }

    private var header: some View {
        HStack {
            BSChromeIconButton(
                systemName: "xmark",
                accessibilityLabel: "关闭散场仪式",
                action: onClose
            )
            Spacer()
            Text(BSLocalization.text("散场了"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Color.clear
                .frame(
                    width: BSLayout.minTouchTarget,
                    height: BSLayout.minTouchTarget
                )
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var ratingHero: some View {
        VStack(spacing: 0) {
            if let current {
                HStack(spacing: 10) {
                    Text(current.emoji)
                        .font(.system(size: 44))
                    Text(current.label)
                        .font(.system(size: 30, weight: .bold))
                        .tracking(0.3)
                        .foregroundColor(current.tint)
                        .minimumScaleFactor(0.78)
                        .lineLimit(1)
                }
                .scaleEffect(emojiBump ? 1.08 : 1)
                .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
                .frame(maxWidth: .infinity, minHeight: 58)
                .dispersalMatchedGeometry(
                    id: "dispersal.rating",
                    namespace: transitionNamespace
                )

                Text(current.sub)
                    .font(.system(size: 11.5))
                    .foregroundColor(BSColor.Stage.dim)
                    .padding(.top, 6)
            } else {
                Text("🎭")
                    .font(.system(size: 46))
                    .opacity(0.72)
                    .frame(height: 58)
                    .accessibilityHidden(true)

                Color.clear
                    .frame(height: 20)
            }

            snapSlider
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.065),
                            Color.white.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )
        )
    }

    private var snapSlider: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                let inset = DispersalSnapSliderLayout.trackInset(width: proxy.size.width)
                let track = max(proxy.size.width - inset * 2, 1)
                let progress = CGFloat((rating ?? 1) - 1) / 4

                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: track, height: 4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    (current?.tint ?? BSColor.Stage.accent).opacity(0.55),
                                    current?.tint ?? BSColor.Stage.accent
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: rating == nil ? 0 : track * progress,
                            height: 4
                        )
                }
                .padding(.leading, inset)
                .padding(.top, 17)
            }

            HStack(spacing: 0) {
                ForEach(DispersalRating.allCases) { node in
                    let selected = node.rawValue == rating
                    Button {
                        rating = node.rawValue
                        raw = Double(node.rawValue)
                    } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(
                                    selected
                                        ? node.tint
                                        : Color(red: 0.165, green: 0.188, blue: 0.251)
                                )
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selected
                                                ? node.tint
                                                : Color.white.opacity(0.14),
                                            lineWidth: 2
                                        )
                                )
                                .shadow(
                                    color: selected
                                        ? node.tint.opacity(0.28)
                                        : .clear,
                                    radius: selected ? 7 : 0
                                )
                                .padding(.top, 12)

                            Text(node.emoji)
                                .font(.system(size: selected ? 20 : 18))
                                .opacity(selected ? 1 : 0.55)
                                .grayscale(selected ? 0 : 0.75)

                            Text(node.label)
                                .font(.system(size: 10, weight: selected ? .bold : .medium))
                                .foregroundColor(
                                    selected
                                        ? BSColor.Stage.foreground
                                        : BSColor.Stage.dim
                                )
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .animation(
                        .spring(response: 0.32, dampingFraction: 0.7),
                        value: rating
                    )
                    .accessibilityLabel(node.accessibilityLabel)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Slider(
                value: Binding(
                    get: { raw },
                    set: { newValue in
                        let snapped = DispersalCeremonyPolicy.snap(newValue)
                        raw = Double(snapped)
                        rating = snapped
                    }
                ),
                in: 1...5,
                step: 1
            )
            .opacity(0.02)
            .tint(.clear)
            .padding(.top, 4)
            .sensoryFeedback(.selection, trigger: rating)
            .accessibilityHidden(true)
        }
        .frame(height: 86)
    }

    private var noteBlock: some View {
        BSSurfacePanel {
            TextField(
                BSLocalization.text("这一晚，最想留下什么？"),
                text: $note,
                axis: .vertical
            )
            .lineLimit(4...10)
            .font(BSFont.body)
            .foregroundColor(BSColor.Stage.foreground)
            .tint(BSColor.Stage.accent)
            .focused($isNoteFocused)
            .onChange(of: note) { _, newValue in
                if newValue.count > DispersalCeremonyPolicy.maximumNoteLength {
                    note = String(
                        newValue.prefix(DispersalCeremonyPolicy.maximumNoteLength)
                    )
                }
            }
            .dispersalMatchedGeometry(
                id: "dispersal.note",
                namespace: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : transitionNamespace
            )
            .accessibilityLabel("散场文字")
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
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                emojiBump = false
            }
        }
    }
}
