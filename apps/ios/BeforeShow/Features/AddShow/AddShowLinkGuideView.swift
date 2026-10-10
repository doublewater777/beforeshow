import SwiftUI

/// 购票平台快捷入口及「如何获取链接？」图文引导。
/// 首次进入默认展示 5 步滑动图文教程；之后直接展示平台列表，用户可随时主动点击查看教程。
struct AddShowLinkGuideView: View {
    /// 用户点了「打开 XX」时回调，用于只在真正去拿过链接后才读剪贴板。
    var onOpenPlatform: (() -> Void)?

    @AppStorage("addShow.hasSeenLinkGuide") private var hasSeenLinkGuide = false
    @State private var showingTutorial: Bool
    @State private var browserPage: BSInAppBrowserPage?
    @Environment(\.dismiss) private var dismiss

    init(onOpenPlatform: (() -> Void)? = nil) {
        self.onOpenPlatform = onOpenPlatform
        _showingTutorial = State(
            initialValue: !UserDefaults.standard.bool(forKey: "addShow.hasSeenLinkGuide")
        )
    }

    private var prefersChinese: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("zh") ?? false
    }

    private var platforms: [ShowLinkGuidePlatform] {
        ShowLinkPlatformCatalog.guidePlatformsSorted(chineseFirst: prefersChinese)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BSColor.background.ignoresSafeArea()

                if showingTutorial {
                    tutorialContent
                        .transition(.opacity)
                } else {
                    pickerContent
                        .transition(.opacity)
                }
            }
            .navigationTitle(showingTutorial ? BSLocalization.text("如何获取链接？") : BSLocalization.text("购票平台"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BSColor.textTertiary)
                    }
                    .accessibilityLabel(BSLocalization.text("关闭"))
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .sheet(item: $browserPage, onDismiss: {
            dismiss()
        }) { page in
            BSInAppBrowser(page: page)
        }
    }

    // MARK: - 教程视图

    private var tutorialContent: some View {
        AddShowLinkGuideStepsView(
            completionTitle: hasSeenLinkGuide ? BSLocalization.text("返回平台列表") : BSLocalization.text("前往购票平台")
        ) {
            hasSeenLinkGuide = true
            withAnimation(.easeInOut(duration: 0.2)) {
                showingTutorial = false
            }
        }
    }

    // MARK: - 平台选择

    private var pickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                // 主动查看教程入口
                tutorialBanner

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(platforms) { platform in
                        Button {
                            guard let url = platform.url else { return }
                            onOpenPlatform?()
                            browserPage = BSInAppBrowserPage(url: url)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(platform.displayName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(BSColor.textPrimary)
                                    Text(URL(string: platform.overviewURL)?.host() ?? platform.overviewURL)
                                        .font(.system(size: 11))
                                        .foregroundColor(BSColor.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(BSColor.textTertiary.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(Color.white.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: BSRadius.md)
                                    .stroke(BSColor.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(platform.displayName)
                    }
                }
            }
            .padding(BSSpacing.lg)
        }
    }

    private var tutorialBanner: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingTutorial = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(BSColor.Accent.violet)

                VStack(alignment: .leading, spacing: 2) {
                    Text(BSLocalization.text("如何获取链接？"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                    Text(BSLocalization.text("查看秀动示例教程（搜索、分享与拷贝）"))
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.textTertiary)
                }

                Spacer(minLength: 4)

                HStack(spacing: 3) {
                    Text(BSLocalization.text("查看教程"))
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(BSColor.Accent.violet)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(BSColor.Accent.violet.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.Accent.violet.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.text("查看如何获取链接教程"))
    }
}
