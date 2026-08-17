import Foundation
import SwiftUI
import UIKit

private enum FootprintShareComposerTokens {
    static let previewCornerRadius = BSRadius.sheet
    static let materialHeight: CGFloat = 104
    static let actionHeight: CGFloat = 50
    static let renderSize = CGSize(width: 360, height: 450)
    static let renderScale: CGFloat = 3
    static let outputWidth = 1080
    static let outputHeight = 1350

    static let navigationFill = Color.white.opacity(0.055)
    static let previewBorder = Color.white.opacity(0.12)
    static let previewShadow = Color.black.opacity(0.48)
    static let materialScrim = Color.black.opacity(0.76)
    static let unselectedIndicator = Color.white.opacity(0.8)
    static let ticketWarningFill = BSColor.Accent.warm.opacity(0.08)
    static let ticketWarningBorder = BSColor.Accent.warm.opacity(0.24)
}

struct FootprintShareComposerView: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let materials: [FootprintShareMaterial]
    let onClose: () -> Void

    @State private var selected: Set<UUID>
    @State private var images: [UUID: UIImage] = [:]
    @State private var toast: BSToastPayload?

    init(
        show: Show,
        identity: FootprintDetailIdentity,
        materials: [FootprintShareMaterial],
        onClose: @escaping () -> Void
    ) {
        self.show = show
        self.identity = identity
        self.materials = materials
        self.onClose = onClose
        _selected = State(initialValue: Set(
            FootprintShareSelectionPolicy.defaultSelection(
                from: materials.map(\.candidate)
            )
        ))
    }

    private var orderedMaterials: [FootprintShareMaterial] {
        let ids = FootprintShareSelectionPolicy.outputOrder(
            selected: selected,
            from: materials.map(\.candidate)
        )
        let byID = Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            VStack(spacing: 0) {
                navigationBar
                    .padding(.horizontal, BSSpacing.roomy)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: BSSpacing.roomy) {
                        cardPreview
                        selectionSection
                        if selectedContainsTicket {
                            ticketWarning
                        }
                        shareAction
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.bottom, BSSpacing.xl)
                }
            }
        }
        .bsToastOverlay(toast, bottomPadding: 36)
        .task(id: materials.map(\.id)) { await loadImages() }
        .preferredColorScheme(.dark)
    }

    private var navigationBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(BSFont.caption.weight(.semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(FootprintShareComposerTokens.navigationFill, in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("取消分享"))
            Spacer()
            VStack(spacing: 2) {
                Text(BSLocalization.text("分享编辑器"))
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("选择 1–3 个画面"))
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.dim)
            }
            Spacer()
            Color.clear.frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
        }
        .padding(.top, BSSpacing.xs)
    }

    private var cardPreview: some View {
        GeometryReader { proxy in
            FootprintMemoryShareCard(
                show: show,
                identity: identity,
                materials: orderedMaterials,
                images: images
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: FootprintShareComposerTokens.previewCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: FootprintShareComposerTokens.previewCornerRadius)
                .stroke(FootprintShareComposerTokens.previewBorder)
        )
        .shadow(
            color: FootprintShareComposerTokens.previewShadow,
            radius: BSSpacing.lg,
            y: BSRadius.md
        )
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.text("选择画面"))
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                Spacer()
                Text("\(selected.count) / \(FootprintShareSelectionPolicy.maximumSelectionCount)")
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.dim)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: BSSpacing.sm),
                    GridItem(.flexible(), spacing: BSSpacing.sm),
                    GridItem(.flexible())
                ],
                spacing: BSSpacing.sm
            ) {
                ForEach(Array(materials.enumerated()), id: \.element.id) { index, material in
                    materialButton(material, ordinal: index + 1)
                }
            }

            Text(selected.isEmpty ? BSLocalization.text("至少选择一个画面") : BSLocalization.text("成品会按记忆时间排列，票根与时刻表排在最后。"))
                .font(BSFont.V3.caption)
                .foregroundColor(selected.isEmpty ? BSColor.Stage.danger : BSColor.Stage.dim)
        }
    }

    private func materialButton(_ material: FootprintShareMaterial, ordinal: Int) -> some View {
        let isSelected = selected.contains(material.id)
        return Button { toggle(material) } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = images[material.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        BSColor.Stage.surface
                            .overlay(Image(systemName: "photo").foregroundColor(BSColor.Stage.dim))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: FootprintShareComposerTokens.materialHeight)
                .clipped()

                LinearGradient(
                    colors: [.clear, FootprintShareComposerTokens.materialScrim],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(material.title)
                    .font(BSFont.V3.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(BSSpacing.sm)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(BSFont.headline)
                    .foregroundColor(
                        isSelected ? BSColor.Stage.accent : FootprintShareComposerTokens.unselectedIndicator
                    )
                    .padding(BSSpacing.sm)
            }
            .frame(height: FootprintShareComposerTokens.materialHeight)
            .background(BSColor.Stage.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(isSelected ? BSColor.Stage.accent : BSColor.Stage.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            FootprintAccessibilityPolicy.shareMaterialLabel(
                title: material.title,
                ordinal: ordinal,
                recordedAt: material.candidate.recordedAt,
                isSelected: isSelected
            )
        )
    }

    private var selectedContainsTicket: Bool {
        materials.contains { $0.kind == .ticket && selected.contains($0.id) }
    }

    private var ticketWarning: some View {
        HStack(alignment: .top, spacing: BSSpacing.compact) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(BSFont.caption.weight(.semibold))
                .foregroundColor(BSColor.Accent.warm)
                .padding(.top, BSSpacing.xs)
            VStack(alignment: .leading, spacing: 4) {
                Text(BSLocalization.text("分享票根前请检查"))
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("确认画面中没有二维码、订单号及其他个人信息。"))
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(BSSpacing.compact)
        .background(
            FootprintShareComposerTokens.ticketWarningFill,
            in: RoundedRectangle(cornerRadius: BSRadius.md)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(FootprintShareComposerTokens.ticketWarningBorder)
        )
    }

    private var shareAction: some View {
        Button { renderAndShare() } label: {
            Label(BSLocalization.text("分享图片"), systemImage: "square.and.arrow.up")
                .font(BSFont.caption.weight(.semibold))
                .foregroundColor(selected.isEmpty ? BSColor.Stage.dim : BSColor.Stage.background)
                .frame(maxWidth: .infinity)
                .frame(height: FootprintShareComposerTokens.actionHeight)
                .background(
                    selected.isEmpty ? BSColor.Stage.surfaceRaised : BSColor.Stage.accent,
                    in: RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                )
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
        .accessibilityHint(selected.isEmpty ? BSLocalization.text("至少选择一个画面") : BSLocalization.text("生成 PNG 并打开系统分享"))
    }

    private func toggle(_ material: FootprintShareMaterial) {
        if selected.contains(material.id) {
            selected.remove(material.id)
            return
        }
        guard let next = FootprintShareSelectionPolicy.selectionByAdding(material.id, to: selected) else {
            presentToast(.failure, BSLocalization.text("最多选择 3 个画面"))
            return
        }
        selected = next
    }

    @MainActor
    private func loadImages() async {
        let pairs = materials.map { ($0.id, $0.imageURL.path) }
        images = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: pairs.compactMap { id, path in
                UIImage(contentsOfFile: path).map { (id, $0) }
            })
        }.value
    }

    @MainActor
    private func renderAndShare() {
        guard !selected.isEmpty else {
            presentToast(.failure, BSLocalization.text("至少选择一个画面"))
            return
        }

        let card = FootprintMemoryShareCard(
            show: show,
            identity: identity,
            materials: orderedMaterials,
            images: images
        )
        .frame(
            width: FootprintShareComposerTokens.renderSize.width,
            height: FootprintShareComposerTokens.renderSize.height
        )

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(
            width: FootprintShareComposerTokens.renderSize.width,
            height: FootprintShareComposerTokens.renderSize.height
        )
        renderer.scale = FootprintShareComposerTokens.renderScale
        guard let image = renderer.uiImage,
              image.cgImage?.width == FootprintShareComposerTokens.outputWidth,
              image.cgImage?.height == FootprintShareComposerTokens.outputHeight,
              let data = image.pngData() else {
            presentToast(.failure, BSLocalization.text("分享图片生成失败，请重试"))
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShow-\(show.id.uuidString)-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            guard SystemPNGSharePresenter.present(url: url) else {
                try? FileManager.default.removeItem(at: url)
                presentToast(.failure, BSLocalization.text("系统分享面板暂时无法打开"))
                return
            }
        } catch {
            presentToast(.failure, BSLocalization.text("分享图片生成失败，请重试"))
        }
    }

    private func presentToast(_ tone: BSToastTone, _ message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if toast == payload { toast = nil }
        }
    }
}
