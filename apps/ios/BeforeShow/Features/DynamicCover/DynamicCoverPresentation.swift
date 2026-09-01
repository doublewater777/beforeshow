import Foundation
import SwiftUI
import UIKit

// MARK: - Face state

enum DynamicCoverFaceStore {
    private static let keyPrefix = "dynamic-cover-face-v1-"

    static func isDynamicFace(for showID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: keyPrefix + showID.uuidString)
    }

    static func setDynamicFace(_ isDynamic: Bool, for showID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(isDynamic, forKey: keyPrefix + showID.uuidString)
    }

    static func clear(showID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyPrefix + showID.uuidString)
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

enum DynamicCoverAccessibilityPolicy {
    static func shouldExposeAddVideoAction(
        hasDynamicCover: Bool,
        hasChooseVideoAction: Bool
    ) -> Bool {
        !hasDynamicCover && hasChooseVideoAction
    }

    static func shouldExposeFaceActions(canFlip: Bool) -> Bool {
        canFlip
    }

    static func hint(canFlip: Bool, opensDetail: Bool) -> String {
        switch (opensDetail, canFlip) {
        case (true, true):
            return BSLocalization.text("轻点查看现场详情，长按翻转动态封面")
        case (true, false):
            return BSLocalization.text("轻点查看现场详情")
        case (false, true):
            return BSLocalization.text("长按翻转动态封面，轻点返回静态封面")
        case (false, false):
            return BSLocalization.text("暂无动态封面")
        }
    }
}

private struct DynamicCoverAddVideoAccessibilityModifier: ViewModifier {
    let isAvailable: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAvailable {
            content.accessibilityAction(named: BSLocalization.text("添加动态封面视频"), action)
        } else {
            content
        }
    }
}

private struct DynamicCoverFaceAccessibilityModifier: ViewModifier {
    let isAvailable: Bool
    let showStaticFace: () -> Void
    let showDynamicFace: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAvailable {
            content
                .accessibilityAction(named: BSLocalization.text("显示静态封面")) { showStaticFace() }
                .accessibilityAction(named: BSLocalization.text("显示动态封面")) { showDynamicFace() }
        } else {
            content
        }
    }
}

// MARK: - Cover faces

/// A show-bound cover with a static primary face and an optional video face.
/// The dynamic face is deliberately only played while it is frontmost and active.
struct DynamicCoverFlipView<StaticFace: View>: View {
    let showID: UUID
    let dynamicCover: DynamicCover?
    let width: CGFloat
    let height: CGFloat
    let isPlaybackActive: Bool
    let reduceMotion: Bool
    let onChooseVideo: (() -> Void)?
    let opensDetail: Bool
    private let staticFace: () -> StaticFace

    @State private var isDynamicFace: Bool
    @State private var mediaURL: URL?

    init(
        showID: UUID,
        dynamicCover: DynamicCover?,
        width: CGFloat,
        height: CGFloat,
        isPlaybackActive: Bool,
        reduceMotion: Bool,
        onChooseVideo: (() -> Void)? = nil,
        opensDetail: Bool = false,
        accessibilityName: String? = nil,
        @ViewBuilder staticFace: @escaping () -> StaticFace
    ) {
        self.showID = showID
        self.dynamicCover = dynamicCover
        self.width = width
        self.height = height
        self.isPlaybackActive = isPlaybackActive
        self.reduceMotion = reduceMotion
        self.onChooseVideo = onChooseVideo
        self.opensDetail = opensDetail
        self.accessibilityName = accessibilityName
        self.staticFace = staticFace
        _isDynamicFace = State(initialValue: dynamicCover != nil && DynamicCoverFaceStore.isDynamicFace(for: showID))
    }

    private let accessibilityName: String?

    /// 已上传视频时翻向播放面；未上传时翻向带「选择视频」入口的空状态背面。
    private var canFlip: Bool { mediaURL != nil || (dynamicCover == nil && onChooseVideo != nil) }
    private var faceDescription: String { isDynamicFace ? BSLocalization.text("动态封面") : BSLocalization.text("静态封面") }

    private func chooseVideoFromAccessibility() {
        guard dynamicCover == nil else { return }
        onChooseVideo?()
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                staticFace()
                    .opacity(isDynamicFace ? 0 : 1)
                dynamicFace
                    .opacity(isDynamicFace ? 1 : 0)
            } else {
                staticFace()
                    .rotation3DEffect(
                        .degrees(isDynamicFace ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.72
                    )
                    .opacity(isDynamicFace ? 0 : 1)
                dynamicFace
                    .rotation3DEffect(
                        .degrees(isDynamicFace ? 0 : -180),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.72
                    )
                    .opacity(isDynamicFace ? 1 : 0)
            }

        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard canFlip else { return }
                flip(to: !isDynamicFace, haptic: true)
            }
        )
        .task(id: dynamicCoverRevision) {
            guard let dynamicCover else {
                mediaURL = nil
                isDynamicFace = false
                return
            }
            mediaURL = try? await DynamicCoverMediaStore.shared.absoluteURL(
                for: dynamicCover.relativePath,
                showID: showID
            )
            if mediaURL == nil {
                isDynamicFace = false
            }
        }
        .onChange(of: dynamicCover?.id) { _, newID in
            guard newID != nil else {
                isDynamicFace = false
                DynamicCoverFaceStore.clear(showID: showID)
                return
            }
            // A newly imported/replaced video is the user's explicit request to
            // see the dynamic side. Update local state immediately; the persisted
            // preference is written by the import transaction as well.
            isDynamicFace = true
            DynamicCoverFaceStore.setDynamicFace(true, for: showID)
        }
        .onChange(of: dynamicCover?.relativePath) { oldPath, newPath in
            guard oldPath != nil, newPath != nil, oldPath != newPath else { return }
            flip(to: true, haptic: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [accessibilityName.map { BSLocalization.format("现场封面，%@", $0) } ?? BSLocalization.text("现场封面"), BSLocalization.format("当前为%@", faceDescription)]
                .joined(separator: "，")
        )
        .accessibilityAddTraits(opensDetail ? .isButton : [])
        .accessibilityHint(DynamicCoverAccessibilityPolicy.hint(canFlip: canFlip, opensDetail: opensDetail))
        .modifier(
            DynamicCoverFaceAccessibilityModifier(
                isAvailable: DynamicCoverAccessibilityPolicy.shouldExposeFaceActions(canFlip: canFlip),
                showStaticFace: { flip(to: false, haptic: false) },
                showDynamicFace: { flip(to: true, haptic: false) }
            )
        )
        .modifier(
            DynamicCoverAddVideoAccessibilityModifier(
                isAvailable: DynamicCoverAccessibilityPolicy.shouldExposeAddVideoAction(
                    hasDynamicCover: dynamicCover != nil,
                    hasChooseVideoAction: onChooseVideo != nil
                ),
                action: chooseVideoFromAccessibility
            )
        )
    }

    private var dynamicCoverRevision: String? {
        guard let dynamicCover else { return nil }
        return "\(dynamicCover.id.uuidString)|\(dynamicCover.relativePath)|\(dynamicCover.updatedAt.timeIntervalSince1970)"
    }

    private func flip(to dynamicFace: Bool, haptic: Bool) {
        guard dynamicFace != isDynamicFace else { return }
        if haptic {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        // Spring instead of easeInOut so the user can grab the cover mid-flip
        // and reverse it without a velocity discontinuity — Apple §3 Interruptibility,
        // §4 Springs. reduceMotion keeps the same animation family but damps to
        // 1.0 to drop the bounce rather than swapping in a different curve.
        withAnimation(.spring(
            response: 0.4,
            dampingFraction: reduceMotion ? 1.0 : 0.85
        )) {
            isDynamicFace = dynamicFace
        }
        DynamicCoverFaceStore.setDynamicFace(dynamicFace, for: showID)
    }

    @ViewBuilder
    private var dynamicFace: some View {
        if let mediaURL {
            DynamicCoverPlaybackView(
                url: mediaURL,
                isPlaying: isDynamicFace && isPlaybackActive
            )
        } else if dynamicCover == nil, let onChooseVideo {
            emptyDynamicFace(onChooseVideo: onChooseVideo)
        } else {
            ZStack {
                BSColor.Stage.surfaceRaised
                Image(systemName: "play.rectangle")
                    .font(BSFont.heroTitle.weight(.light))
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
    }

    /// 未上传视频时延续静态封面的色彩与氛围，只保留一个选择视频入口。
    private func emptyDynamicFace(onChooseVideo: @escaping () -> Void) -> some View {
        ZStack {
            staticFace()
                .scaleEffect(1.08)
                .blur(radius: 18)
                .saturation(0.82)
                .brightness(-0.30)
                .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    BSColor.Stage.background.opacity(0.48),
                    BSColor.Stage.background.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: BSSpacing.sm) {
                Button(action: onChooseVideo) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text("添加动态封面视频"))
                .padding(.bottom, BSSpacing.xs)
                Text("添加动态封面")
                    .font(BSFont.caption.weight(.medium))
                    .foregroundColor(.white)
            }
        }
    }
}

/// Local video surface for management and historical previews.
struct DynamicCoverVideoPreviewView: View {
    let showID: UUID
    let cover: DynamicCover
    let isPlaying: Bool

    @State private var mediaURL: URL?

    var body: some View {
        Group {
            if let mediaURL {
                DynamicCoverPlaybackView(url: mediaURL, isPlaying: isPlaying)
            } else {
                ZStack {
                    BSColor.Stage.surfaceRaised
                    ProgressView().tint(BSColor.Stage.muted)
                }
            }
        }
        .task(id: cover.relativePath) {
            mediaURL = try? await DynamicCoverMediaStore.shared.absoluteURL(
                for: cover.relativePath,
                showID: showID
            )
        }
        .clipped()
    }
}
