import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct AboutBeforeShowView: View {
    private static let privacyURL = URL(string: "https://beforeshow.doublewaterapps.com/privacy")!
    private static let termsURL = URL(string: "https://beforeshow.doublewaterapps.com/terms")!
    private static let icpFilingNumber = "浙ICP备2026041359号-3A"
    private static let icpQueryURL = URL(string: "https://beian.miit.gov.cn/")!
    @State private var legalPage: BSInAppBrowserPage?

    var body: some View {
        List {
            Section {
                VStack(spacing: BSSpacing.md) {
                    Text(BSLocalization.text("开场前"))
                        .font(.system(size: 38, weight: .light))
                        .tracking(BSFont.titleTracking)
                        .bsGradientText()

                    Text("BeforeShow")
                        .font(BSFont.caption)
                        .tracking(4)
                        .foregroundColor(BSColor.Stage.dim)

                    Text(BSLocalization.text("开场之前，先进入状态"))
                        .font(BSFont.V3.body)
                        .foregroundColor(BSColor.Stage.muted)

                    Text(AppVersionInformation.current.fullCopy)
                        .font(BSFont.V3.small)
                        .foregroundColor(BSColor.Stage.dim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BSSpacing.md)
                .listRowBackground(BSColor.Stage.surface)
            }

            Section(header: Text(BSLocalization.text("法律信息"))) {
                Button {
                    legalPage = BSInAppBrowserPage(url: localizedSiteURL(Self.privacyURL))
                } label: {
                    HStack {
                        Text(BSLocalization.text("隐私政策"))
                            .foregroundColor(BSColor.Stage.foreground)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(BSColor.Stage.surface)

                Button {
                    legalPage = BSInAppBrowserPage(url: localizedSiteURL(Self.termsURL))
                } label: {
                    HStack {
                        Text(BSLocalization.text("用户协议"))
                            .foregroundColor(BSColor.Stage.foreground)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(BSColor.Stage.surface)

                Button {
                    legalPage = BSInAppBrowserPage(url: Self.icpQueryURL)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BSLocalization.text("ICP备案号"))
                                .foregroundColor(BSColor.Stage.foreground)
                            Text(Self.icpFilingNumber)
                                .font(BSFont.V3.small)
                                .foregroundColor(BSColor.Stage.muted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(BSColor.Stage.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .navigationTitle(BSLocalization.text("关于开场前"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $legalPage) { page in
            BSInAppBrowser(page: page)
        }
    }
}
