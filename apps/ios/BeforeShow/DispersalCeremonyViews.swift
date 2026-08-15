import SwiftUI
import SwiftData
import UIKit

// MARK: - 熄灯动画

/// 2.8s 舞台熄灯动画。3 道光束（蓝/金/紫）淡入淡出 + 标题"散场"淡入,
/// 节奏对齐 V2 原型。reduceMotion 时直接跳到末尾帧。
/// onComplete 在动画结束(包含 reduceMotion 跳过)时回调,父视图负责切到仪式 sheet。
struct DispersalLightsOutOverlay: View {
    let showName: String
    let ordinal: Int
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()

            stageGlow

            VStack(spacing: BSSpacing.md) {
                Text("散场")
                    .font(.system(size: 42, weight: .light))
                    .tracking(5)
                    .foregroundColor(BSColor.Stage.foreground)
                Text("这是你的第 \(ordinal) 场现场")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.6)
                    .foregroundColor(BSColor.Stage.accent)
            }
            .padding(.horizontal, BSSpacing.lg)
            .opacity(reduceMotion ? 1 : animatedTitleOpacity)
        }
        .saturation(reduceMotion ? 0.2 : 1.0)
        .brightness(reduceMotion ? -0.15 : 0)
        .task {
            if reduceMotion {
                onComplete()
            } else {
                try? await Task.sleep(
                    nanoseconds: UInt64(DispersalCeremonyPolicy.lightsOutDuration * 1_000_000_000)
                )
                onComplete()
            }
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("散场，这是你的第 \(ordinal) 场现场")
    }

    /// 标题在 [0, 25%] 渐入, [80%, 100%] 渐出,中段保持。3 段 0..1 keyTimes。
    private var animatedTitleOpacity: Double {
        let progress = timelineProgress
        if progress < 0.25 {
            return progress / 0.25
        } else if progress < 0.80 {
            return 1
        } else {
            return max(0, 1 - (progress - 0.80) / 0.20)
        }
    }

    private var timelineProgress: Double {
        // 通过 `body` 重新计算耗时,避免在 reduceMotion 时拉起额外 state。
        Date().timeIntervalSince1970.truncatingRemainder(
            dividingBy: DispersalCeremonyPolicy.lightsOutDuration
        ) / DispersalCeremonyPolicy.lightsOutDuration
    }

    private var stageGlow: some View {
        GeometryReader { proxy in
            ZStack {
                beam(color: BSColor.Stage.glowBlue,
                     x: proxy.size.width * 0.20,
                     width: 170 * proxy.size.width / 393,
                     height: proxy.size.height * 0.80,
                     rotation: 14)
                beam(color: BSColor.Stage.accent,
                     x: proxy.size.width * 0.80,
                     width: 170 * proxy.size.width / 393,
                     height: proxy.size.height * 0.80,
                     rotation: -12)
                beam(color: BSColor.Accent.violet,
                     x: proxy.size.width * 0.50,
                     width: 150 * proxy.size.width / 393,
                     height: proxy.size.height * 0.70,
                     rotation: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    private func beam(color: Color, x: CGFloat, width: CGFloat, height: CGFloat, rotation: Double) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.55), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.55
                )
            )
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .position(x: x, y: height * 0.4)
            .blur(radius: 22)
    }
}

// MARK: - 仪式 sheet

/// 「散场仪式」两步 sheet:评级 + 文字 同页 → 分享卡。
///
/// 整条流程与 `endedAt` 写入完全解耦:任一步骤失败或跳过,已结束的现场
/// 都不受影响。
/// - combined 步底部按钮:`跳过` / `生成散场卡`,后者把 `(rating, note)` 一次性 commit
/// - 头部 `×` 按钮触发 `onSkipToMemory`(直接跳到现场回忆,跳过 share)
/// - share 步底部按钮:`保存图片` / `进入现场回忆`,后者触发 `onSkipToMemory`
struct DispersalCeremonySheet: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let calendar: Calendar
    let onCommit: (_ rating: Int?, _ note: String?) async -> Void
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

    init(
        show: Show,
        identity: FootprintDetailIdentity,
        calendar: Calendar,
        onCommit: @escaping (_ rating: Int?, _ note: String?) async -> Void,
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
                    onClose: { onSkipToMemory() },
                    onSkip: { Task { await advanceCombined(skip: true) } },
                    onGenerate: { Task { await advanceCombined(skip: false) } }
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
                    onEnterMemory: { onSkipToMemory() }
                )
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func advanceCombined(skip: Bool) async {
        guard !saving else { return }
        saving = true
        let noteToSave: String?
        if skip {
            noteToSave = nil
        } else {
            noteToSave = draftNote.isEmpty ? nil : draftNote
        }
        await onCommit(draftRating, noteToSave)
        step = .share
        saving = false
    }

    /// 纯规则:把当前 step 推到下一步(测试用 seam)。
    nonisolated static func nextStep(after current: Step) -> Step {
        switch current {
        case .combined: return .share
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, BSSpacing.lg)
            }

            DispersalSheetBottomBar(
                secondaryTitle: "跳过",
                primaryTitle: "生成散场卡",
                onSecondary: onSkip,
                onPrimary: onGenerate
            )
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
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
                    .foregroundColor(BSColor.Stage.foreground)
            }
            .accessibilityLabel("跳过散场仪式，回到足迹")
            Spacer()
            Text("散场了")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Color.clear.frame(width: 42, height: 42)
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
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: 4)
                .padding(.horizontal, 16)
                .padding(.top, 17)

            GeometryReader { proxy in
                let inset: CGFloat = 16
                let track = max(proxy.size.width - inset * 2, 1)
                let progress = CGFloat((rating ?? 1) - 1) / 4
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
                        "写下现在最想记住的事……",
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
                    .accessibilityLabel("填入：\(preset.text)")
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

    @State private var lastError: String?

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

            if let lastError {
                Text(lastError)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.danger)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            DispersalSheetBottomBar(
                secondaryTitle: "保存图片",
                primaryTitle: "进入现场回忆",
                onSecondary: { Task { await saveToPhotos() } },
                onPrimary: onEnterMemory
            )
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
                    .foregroundColor(BSColor.Stage.foreground)
            }
            .accessibilityLabel("回到评级")
            Spacer()
            Text("散场卡")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Color.clear.frame(width: 42, height: 42)
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
        guard let image = renderImage() else {
            lastError = "分享图片生成失败，请重试"
            return
        }
        do {
            try await FootprintPhotoLibrary.save(image)
            lastError = nil
        } catch {
            lastError = "保存失败，请检查相册权限"
        }
    }
}

// MARK: - 底部操作条

/// V2 原型的浮动玻璃底栏:窄次要按钮 + 撑满的主按钮。
private struct DispersalSheetBottomBar: View {
    let secondaryTitle: String
    let primaryTitle: String
    let onSecondary: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(secondaryTitle, action: onSecondary)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(BSColor.Stage.muted)
                .frame(width: 108, height: 46)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))

            Button(primaryTitle, action: onPrimary)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Color(red: 0.035, green: 0.043, blue: 0.067))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(red: 0.051, green: 0.067, blue: 0.106).opacity(0.72))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
