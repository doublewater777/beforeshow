import SwiftUI

/// 通过 App 内浏览器搜索演出、分享并拷贝链接。
struct AddShowLinkGuideView: View {
    /// 用户点了「打开 XX」时回调，用于只在真正去拿过链接后才读剪贴板。
    var onOpenPlatform: (() -> Void)?

    @State private var showsPlatforms = false
    @State private var browserPage: BSInAppBrowserPage?
    @Environment(\.dismiss) private var dismiss

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

                if showsPlatforms {
                    ScrollView {
                        pickerContent
                    }
                } else {
                    AddShowLinkGuideStepsView(completionTitle: "打开购票平台") {
                        showsPlatforms = true
                    }
                }
            }
            .navigationTitle(BSLocalization.text("如何获取链接？"))
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

    // MARK: - 平台选择

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(BSLocalization.format("打开 %@", platform.displayName))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BSColor.textPrimary)
                            Text(URL(string: platform.overviewURL)?.host() ?? platform.overviewURL)
                                .font(.system(size: 11))
                                .foregroundColor(BSColor.textTertiary)
                                .lineLimit(1)
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
                    .accessibilityLabel(BSLocalization.format("选择平台：%@", platform.displayName))
                }
            }
        }
        .padding(BSSpacing.lg)
    }

}
