import PostHog
import SwiftUI
import SwiftData
import UIKit

struct DispersalCeremonySheet: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let calendar: Calendar
    let onCommit: (_ rating: Int?, _ note: String?) async throws -> Void
    let onSkipToMemory: () -> Void

    enum Step: Equatable {
        case combined
        case setlist
        case share
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var step: Step = .combined
    @State private var draftRating: Int?
    @State private var draftNote: String = ""
    @State private var saving = false
    @State private var commitError: String?
    @State private var setlistCoordinator: FootprintListeningCoordinator?

    init(
        show: Show,
        identity: FootprintDetailIdentity,
        calendar: Calendar,
        onCommit: @escaping (_ rating: Int?, _ note: String?) async throws -> Void,
        onSkipToMemory: @escaping () -> Void = {}
    ) {
        self.show = show
        self.identity = identity
        self.calendar = calendar
        self.onCommit = onCommit
        self.onSkipToMemory = onSkipToMemory
        _draftRating = State(initialValue: show.rating)
        _draftNote = State(initialValue: show.closingNote ?? "")
    }

    var body: some View {
        Group {
            switch step {
            case .combined:
                DispersalCombinedStep(
                    showName: show.name,
                    rating: $draftRating,
                    note: $draftNote,
                    commitError: commitError,
                    onClose: {
                        PostHogSDK.shared.capture("dispersal_ceremony_skipped", properties: ["trigger": "close"])
                        onSkipToMemory()
                    },
                    onSkip: {
                        PostHogSDK.shared.capture("dispersal_ceremony_skipped", properties: ["trigger": "skip"])
                        onSkipToMemory()
                    },
                    onGenerate: { Task { await advanceCombined() } }
                )
            case .setlist:
                if let setlistCoordinator {
                    DispersalSetlistStepView(
                        coordinator: setlistCoordinator,
                        onBack: { step = .combined },
                        onSkip: { step = .share },
                        onFinish: { step = .share },
                        onClose: {
                            PostHogSDK.shared.capture("dispersal_ceremony_skipped", properties: ["trigger": "close_from_setlist"])
                            onSkipToMemory()
                        }
                    )
                } else {
                    Color.clear.task { step = .share }
                }
            case .share:
                DispersalShareStep(
                    show: show,
                    identity: identity,
                    rating: draftRating,
                    note: draftNote,
                    onBack: {
                        step = .setlist
                    },
                    onEnterMemory: {
                        AppReviewPrompt.consider(.completedCeremony)
                        onSkipToMemory()
                    }
                )
            }
        }
        .task {
            if setlistCoordinator == nil {
                let coordinator = FootprintListeningCoordinator(context: modelContext, show: show)
                coordinator.reload()
                setlistCoordinator = coordinator
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func advanceCombined() async {
        guard !saving else { return }
        saving = true
        commitError = nil
        let noteToSave = draftNote.isEmpty ? nil : draftNote
        do {
            try await onCommit(draftRating, noteToSave)
            var props: [String: Any] = [
                "has_rating": draftRating != nil,
                "has_note": noteToSave != nil
            ]
            if let rating = draftRating { props["rating_value"] = rating }
            PostHogSDK.shared.capture("dispersal_ceremony_completed", properties: props)
            step = Self.nextStep(after: .combined, commitSucceeded: true)
        } catch {
            commitError = BSLocalization.text("散场评价没有保存，请重试")
            step = Self.nextStep(after: .combined, commitSucceeded: false)
        }
        saving = false
    }

    /// 纯规则:commit 成功才离开评级页,失败停在 combined。
    nonisolated static func nextStep(after current: Step, commitSucceeded: Bool = true) -> Step {
        switch current {
        case .combined: return commitSucceeded ? .setlist : .combined
        case .setlist: return .share
        case .share: return .share
        }
    }
}

// MARK: - 评级+文字 同页

/// V2 同款:评级 + 文字 在同 sheet 内,中间不分步。
/// 头部 `×` 直接跳到现场回忆(跳过 share),不持久化新数据。

struct DispersalCombinedStep: View {
    let showName: String
    @Binding var rating: Int?
    @Binding var note: String
    var commitError: String? = nil
    let onClose: () -> Void
    let onSkip: () -> Void
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
                    ritualHead
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

            DispersalSheetBottomBar(
                secondaryTitle: BSLocalization.text("跳过"),
                primaryTitle: BSLocalization.text("下一步：回记歌单"),
                onSecondary: onSkip,
                onPrimary: onGenerate
            )
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

    // MARK: 子区块

    private var header: some View {
        HStack {
            BSChromeIconButton(
                systemName: "xmark",
                accessibilityLabel: "跳过散场仪式，回到足迹",
                action: onClose
            )
            Spacer()
            Text("散场了")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Color.clear.frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var ritualHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今晚留下什么")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.2)
                .foregroundColor(BSColor.Stage.accent)
            Text("这一场怎么样？")
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)
        }
    }

    private var ratingHero: some View {
        VStack(spacing: 0) {
            Text(current?.emoji ?? "🎭")
                .font(.system(size: 48))
                .scaleEffect(emojiBump ? 1.13 : 1)
                .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
                .frame(height: 56)
                .accessibilityHidden(true)

            Text(current?.label ?? " ")
                .font(.system(size: 32, weight: .bold))
                .tracking(0.4)
                .foregroundColor(current?.tint ?? BSColor.Stage.muted)
                .padding(.top, 10)
                .animation(.easeInOut(duration: 0.18), value: current)

            Text(current?.sub ?? " ")
                .font(.system(size: 11.5))
                .foregroundColor(BSColor.Stage.dim)
                .padding(.top, 5)
                .animation(.easeInOut(duration: 0.18), value: current)

            snapSlider
                .padding(.top, 22)
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
                        .frame(width: rating == nil ? 0 : track * progress, height: 4)
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
                                .fill(selected ? node.tint : Color(red: 0.165, green: 0.188, blue: 0.251))
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle().stroke(
                                        selected ? node.tint : Color.white.opacity(0.14),
                                        lineWidth: 2
                                    )
                                )
                                .shadow(
                                    color: selected ? node.tint.opacity(0.28) : .clear,
                                    radius: selected ? 7 : 0
                                )
                                .padding(.top, 12)
                            Text(node.emoji)
                                .font(.system(size: selected ? 20 : 18))
                                .opacity(selected ? 1 : 0.55)
                                .grayscale(selected ? 0 : 0.75)
                            Text(node.label)
                                .font(.system(size: 10, weight: selected ? .bold : .medium))
                                .foregroundColor(selected ? BSColor.Stage.foreground : BSColor.Stage.dim)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.32, dampingFraction: 0.7), value: rating)
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
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("留下些什么？")
                .font(.system(size: 12))
                .foregroundColor(BSColor.Stage.muted)

            BSSurfacePanel {
                VStack(alignment: .trailing, spacing: BSSpacing.sm) {
                    TextField(
                        BSLocalization.text("写下现在最想记住的事……"),
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
                            note = String(newValue.prefix(DispersalCeremonyPolicy.maximumNoteLength))
                        }
                    }
                    .accessibilityLabel("散场文字")

                    Text("\(note.count) / \(DispersalCeremonyPolicy.maximumNoteLength)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BSColor.Stage.dim)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 7) {
                ForEach(DispersalCeremonyPolicy.quickFillPresets, id: \.label) { preset in
                    Button {
                        note = preset.text
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(BSColor.Stage.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.08)))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.format("填入：%@", preset.text))
                }
            }
        }
    }

    private var current: DispersalRating? {
        guard let r = rating else { return nil }
        return DispersalRating.from(rawValue: r)
    }

    private func bumpEmoji() {
        guard !reduceMotion else { return }
        // Spring bounce: the overshoot lands the emoji rather than easing into a
        // hard stop, so a rating tap reads as one physical beat.
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

// MARK: - 分享步

struct DispersalSheetBottomBar: View {
    let secondaryTitle: String
    let primaryTitle: String
    let onSecondary: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(secondaryTitle, action: onSecondary)
                .buttonStyle(BSSecondaryButtonStyle())

            Button(primaryTitle, action: onPrimary)
                .buttonStyle(BSPrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
