import SwiftUI

struct CurrentShowEmptyStateView: View {
    let hasShows: Bool
    let onAddShow: () -> Void
    let onOpenSettings: () -> Void
    let onOpenShowLibrary: () -> Void

    private var message: String {
        BSLocalization.text(
            hasShows
                ? "从你的现场中选择一个，设为当前"
                : "把要去的音乐现场放进来，\n慢慢靠近那一场。"
        )
    }

    var body: some View {
        BSRootEmptyState(
            iconSystemName: "sparkles",
            title: BSLocalization.text(hasShows ? "选择当前现场" : "先添加一场现场"),
            message: message,
            actionTitle: BSLocalization.text(hasShows ? "选择现场" : "添加现场"),
            action: hasShows ? onOpenShowLibrary : onAddShow
        ) {
            if !hasShows {
                CurrentShowStagePreview()
            }
        }
        .overlay(alignment: .top) {
            HStack {
                Text(BSLocalization.text("当前"))
                    .font(BSFont.pageTitle)
                    .tracking(-0.5)
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                HStack(spacing: 8) {
                    if hasShows {
                        emptyHeaderButton(
                            icon: "list.bullet.rectangle",
                            label: BSLocalization.text("全部现场"),
                            action: onOpenShowLibrary
                        )
                    }
                    emptyHeaderButton(icon: "gearshape", label: BSLocalization.text("设置"), action: onOpenSettings)
                    emptyHeaderButton(icon: "plus", label: BSLocalization.text("添加现场"), action: onAddShow)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, BSLayout.pageHeaderTopPadding)
        }
    }

    private func emptyHeaderButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 还没有现场时，先让人看到一场现场从开场前到散场后都能做什么。
private struct CurrentShowStagePreview: View {
    var body: some View {
        BSFeaturePreviewCard(rows: [
            .init(icon: "hourglass", title: BSLocalization.text("开演前"), detail: BSLocalization.text("倒数 · 听几首 · 路线")),
            .init(icon: "music.mic", title: BSLocalization.text("现场"), detail: BSLocalization.text("时刻表 · 记忆碎片 · 歌单")),
            .init(icon: "opticaldisc", title: BSLocalization.text("散场后"), detail: BSLocalization.text("数字唱片 · 足迹"))
        ])
        .padding(.top, BSSpacing.sm)
    }
}
