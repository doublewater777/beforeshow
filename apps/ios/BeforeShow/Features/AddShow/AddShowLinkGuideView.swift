import SwiftUI

/// 「如何获取链接？」原生引导页：先选购票平台，再给对应步骤 + 一键打开平台总览页。
/// 替代之前的网页版 link-guide，平台数据来自 `ShowLinkPlatformCatalog.guidePlatforms`。
struct AddShowLinkGuideView: View {
    /// 用户点了「打开 XX」时回调，用于只在真正去拿过链接后才读剪贴板。
    var onOpenPlatform: (() -> Void)?

    @State private var selectedPlatform: ShowLinkGuidePlatform?
    @State private var browserPage: BSInAppBrowserPage?
    @Environment(\.dismiss) private var dismiss

    /// 排序跟随 app 语言（「跟随系统」时看系统首选语言）：中文环境国内平台在前。
    private var prefersChinese: Bool {
        switch AppLanguageManager.persisted {
        case .zhHans, .zhHant:
            return true
        case .en:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
        }
    }

    private var platforms: [ShowLinkGuidePlatform] {
        ShowLinkPlatformCatalog.guidePlatformsSorted(chineseFirst: prefersChinese)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BSColor.background.ignoresSafeArea()

                ScrollView {
                    if let platform = selectedPlatform {
                        detailContent(platform)
                            .transition(.opacity)
                    } else {
                        pickerContent
                            .transition(.opacity)
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
        .presentationDetents([.medium, .large])
        .animation(.easeInOut(duration: 0.2), value: selectedPlatform)
        .sheet(item: $browserPage) { page in
            BSInAppBrowser(page: page)
        }
    }

    // MARK: - 平台选择

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            Text(BSLocalization.text("选择你买票的平台，按步骤获取演出链接。"))
                .font(.system(size: 13))
                .foregroundColor(BSColor.textTertiary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(platforms) { platform in
                    Button {
                        selectedPlatform = platform
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(platform.displayName)
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

    // MARK: - 平台步骤

    private func detailContent(_ platform: ShowLinkGuidePlatform) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            VStack(alignment: .leading, spacing: 14) {
                stepRow(
                    number: 1,
                    text: BSLocalization.format("打开%@总览页，搜索你要添加的演出。", platform.displayName)
                )
                stepRow(number: 2, text: BSLocalization.text("点击搜索结果，进入对应的演出详情页。"))
                stepRow(
                    number: 3,
                    text: BSLocalization.text("复制此时页面地址栏里的链接，回到 BeforeShow 粘贴并开始解析。")
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.border, lineWidth: 1)
            )

            Button {
                guard let url = platform.url else { return }
                onOpenPlatform?()
                browserPage = BSInAppBrowserPage(url: url)
            } label: {
                Text(BSLocalization.format("打开 %@", platform.displayName))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditShowSaveButtonStyle())
            .disabled(platform.url == nil)
            .accessibilityLabel(BSLocalization.format("打开%@总览页", platform.displayName))

            VStack(alignment: .leading, spacing: 6) {
                Text(BSLocalization.text("解析失败时"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.Accent.warm)
                Text(BSLocalization.text("请确认你已经从平台总览页搜索并进入了正确的演出详情页，再复制当前地址栏。不要复制平台首页、搜索结果、订单、选座或付款页；如果打开的是短链，先让浏览器展开后再复制。"))
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.textTertiary)
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSColor.Accent.warm.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.Accent.warm.opacity(0.25), lineWidth: 1)
            )

            Button {
                selectedPlatform = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(BSLocalization.text("选择其他平台"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(BSColor.Accent.violet)
                .frame(maxWidth: .infinity)
                .frame(minHeight: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(BSSpacing.lg)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(BSColor.Accent.violet)
                .frame(width: 24, height: 24)
                .background(BSColor.Accent.violet.opacity(0.14))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(BSColor.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
