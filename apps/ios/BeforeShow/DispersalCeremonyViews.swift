import PostHog
import SwiftUI
import SwiftData
import UIKit

// MARK: - 熄灯动画

/// 4.2s 舞台熄灯动画。3 道光束（蓝/金/紫）淡入淡出 + 标题"散场"淡入。
/// 计时在 fullScreenCover 转场落定后才开始,避免转场吃掉渐入前段。
/// reduceMotion 时直接呈现中段停驻帧并立即回调。
/// onComplete 在动画结束(包含 reduceMotion 跳过)时回调;视图提前消失(任务取消)时不回调。
struct DispersalLightsOutOverlay: View {
    let showName: String
    let ordinal: Int
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    var body: some View {
        Group {
            if reduceMotion {
                stage(progress: 0.5)
                    .saturation(0.2)
                    .brightness(-0.15)
            } else if let startedAt {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(startedAt)
                    let progress = DispersalLightsOutMotion.progress(
                        elapsed: elapsed,
                        duration: DispersalCeremonyPolicy.lightsOutDuration
                    )
                    stage(progress: progress)
                }
            } else {
                stage(progress: 0)
            }
        }
        .task {
            if reduceMotion {
                onComplete()
                return
            }
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(DispersalCeremonyPolicy.lightsOutTransitionLeadIn * 1_000_000_000)
                )
                startedAt = Date()
                try await Task.sleep(
                    nanoseconds: UInt64(DispersalCeremonyPolicy.lightsOutDuration * 1_000_000_000)
                )
                onComplete()
            } catch {
                // 任务被取消(视图提前消失)时不回调 onComplete,后续交给父视图决定。
            }
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(BSLocalization.format("散场，这是你的第 %lld 场现场", ordinal))
    }

    private func stage(progress: Double) -> some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            stageGlow(progress: progress)
            VStack(spacing: BSSpacing.md) {
                Text("散场")
                    .font(.system(size: 42, weight: .light))
                    .tracking(5)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.format("这是你的第 %lld 场现场", ordinal))
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.6)
                    .foregroundColor(BSColor.Stage.accent)
            }
            .padding(.horizontal, BSSpacing.lg)
            .opacity(DispersalLightsOutMotion.titleOpacity(progress: progress))
        }
    }

    private func stageGlow(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack {
                beam(
                    color: BSColor.Stage.glowBlue,
                    x: proxy.size.width * 0.20,
                    width: 170 * proxy.size.width / 393,
                    height: proxy.size.height * 0.80,
                    startRotation: 16,
                    endRotation: 8,
                    peak: 0.90,
                    progress: progress
                )
                beam(
                    color: BSColor.Stage.accent,
                    x: proxy.size.width * 0.80,
                    width: 170 * proxy.size.width / 393,
                    height: proxy.size.height * 0.80,
                    startRotation: -16,
                    endRotation: -7,
                    peak: 0.85,
                    progress: progress
                )
                beam(
                    color: BSColor.Accent.violet,
                    x: proxy.size.width * 0.50,
                    width: 150 * proxy.size.width / 393,
                    height: proxy.size.height * 0.70,
                    startRotation: 0,
                    endRotation: 0,
                    peak: 0.70,
                    progress: progress
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    private func beam(
        color: Color,
        x: CGFloat,
        width: CGFloat,
        height: CGFloat,
        startRotation: Double,
        endRotation: Double,
        peak: Double,
        progress: Double
    ) -> some View {
        let rotation = startRotation + (endRotation - startRotation) * progress
        let scaleY = 0.6 + 0.45 * progress
        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.55), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.55
                )
            )
            .frame(width: width, height: height)
            .scaleEffect(x: 1, y: scaleY, anchor: .top)
            .rotationEffect(.degrees(rotation))
            .opacity(DispersalLightsOutMotion.beamOpacity(progress: progress, peak: peak))
            .position(x: x, y: height * 0.4)
            .blur(radius: 22)
    }
}

// MARK: - 仪式 sheet

/// 「散场仪式」两步 sheet:评级 + 文字 同页 → 分享卡。
///
/// 整条流程与 `endedAt` 写入完全解耦:任一步骤失败或跳过,已结束的现场
/// 都不受影响。
/// - combined 步底部按钮:`跳过` / `生成散场卡`,前者直接跳过仪式进现场回忆(不落库),
///   后者把 `(rating, note)` 一次性 commit 后进分享卡
/// - 头部 `×` 按钮与「跳过」等价,触发 `onSkipToMemory`(直接跳到现场回忆,跳过 share)
/// - share 步底部按钮:`保存图片` / `进入现场回忆`,后者触发 `onSkipToMemory`
struct DispersalCeremonySheet: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let calendar: Calendar
    let onCommit: (_ rating: Int?, _ note: String?) async throws -> Void
    let onSkipToMemory: () -> Void

    enum Step: Equatable {
        case combined
        case share
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .combined
    @State private var draftRating: Int?
    @State private var draftNote: String = ""
    @State private var saving = false
    @State private var commitError: String?

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
            case .share:
                DispersalShareStep(
                    show: show,
                    identity: identity,
                    rating: draftRating,
                    note: draftNote,
                    onBack: {
                        step = .combined
                    },
                    onEnterMemory: {
                        AppReviewPrompt.consider(.completedCeremony)
                        onSkipToMemory()
                    }
                )
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
        case .combined: return commitSucceeded ? .share : .combined
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
                primaryTitle: BSLocalization.text("生成散场卡"),
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
        emojiBump = false
        withAnimation(.easeOut(duration: 0.18)) {
            emojiBump = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            withAnimation(.easeOut(duration: 0.16)) {
                emojiBump = false
            }
        }
    }
}

// MARK: - 分享步

struct DispersalShareStep: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String
    let onBack: () -> Void
    let onEnterMemory: () -> Void

    @State private var toast: BSToastPayload?
    @State private var isSaving = false

    private static let renderSize = CGSize(width: 360, height: 450)
    private static let renderScale: CGFloat = 3

    var body: some View {
        VStack(spacing: 0) {
            header

            cardPreview
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            DispersalSheetBottomBar(
                secondaryTitle: BSLocalization.text("保存图片"),
                primaryTitle: BSLocalization.text("进入现场回忆"),
                onSecondary: { Task { await saveToPhotos() } },
                onPrimary: onEnterMemory
            )
        }
        .bsToastOverlay(toast, bottomPadding: 24)
    }

    private var header: some View {
        HStack {
            BSChromeIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "回到评级",
                action: onBack
            )
            Spacer()
            Text("散场卡")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Color.clear.frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var cardPreview: some View {
        DispersalCeremonyShareCard(
            show: show,
            identity: identity,
            rating: rating,
            note: note
        )
        .aspectRatio(Self.renderSize.width / Self.renderSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
    }

    @MainActor
    private func renderImage() -> UIImage? {
        let card = DispersalCeremonyShareCard(
            show: show,
            identity: identity,
            rating: rating,
            note: note
        )
        .frame(width: Self.renderSize.width, height: Self.renderSize.height)

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(
            width: Self.renderSize.width,
            height: Self.renderSize.height
        )
        renderer.scale = Self.renderScale
        return renderer.uiImage
    }

    @MainActor
    private func saveToPhotos() async {
        guard !isSaving else { return }
        guard let image = renderImage() else {
            presentToast(.failure, message: BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        isSaving = true
        presentToast(.neutral, message: BSLocalization.text("保存中…"))
        do {
            try await FootprintPhotoLibrary.save(image)
            presentToast(.success, message: BSLocalization.text("已保存到相册"))
        } catch {
            presentToast(.failure, message: BSLocalization.text("保存失败，请检查相册权限"))
        }
        isSaving = false
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload { toast = nil }
        }
    }
}

// MARK: - 底部操作条

/// 与 App 其他 sheet 一致的标准按钮组:次要(描边) + 主要(白底),等宽排列。
private struct DispersalSheetBottomBar: View {
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
