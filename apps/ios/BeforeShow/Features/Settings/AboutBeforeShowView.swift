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
        BSStageScaffold(title: "", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
            BSSurfacePanel {
                VStack(spacing: BSSpacing.md) {
                    Text("开场前")
                        .font(.system(size: 44, weight: .light))
                        .tracking(BSFont.titleTracking)
                        .bsGradientText()

                    Text("BeforeShow")
                        .font(BSFont.caption)
                        .tracking(4)
                        .foregroundColor(BSColor.textTertiary)

                   Text("开场之前，先进入状态")
                       .font(BSFont.body)
                       .foregroundColor(BSColor.textSecondary)

                    Text(AppVersionInformation.current.fullCopy)
                        .font(.subheadline)
                        .foregroundColor(BSColor.Stage.muted)
                }
                .frame(maxWidth: .infinity)
            }

            SettingsGroup(title: BSLocalization.text("法律信息")) {
                Button {
                    legalPage = BSInAppBrowserPage(url: localizedSiteURL(Self.privacyURL))
                } label: {
                    SettingsRowContent(
                        iconName: "hand.raised.fill",
                        title: BSLocalization.text("隐私政策"),
                        subtitle: nil,
                        value: nil,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())

                SettingsDivider()

                Button {
                    legalPage = BSInAppBrowserPage(url: localizedSiteURL(Self.termsURL))
                } label: {
                    SettingsRowContent(
                        iconName: "doc.text.fill",
                        title: BSLocalization.text("用户协议"),
                        subtitle: nil,
                        value: nil,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())

                SettingsDivider()
                Button {
                    legalPage = BSInAppBrowserPage(url: WeatherKitLegalAttribution.legalPageURL)
                } label: {
                    SettingsRowContent(
                        iconName: "cloud.sun.fill",
                        title: BSLocalization.text("weatherReminderLegalTitle"),
                        subtitle: nil,
                        value: nil,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())

                SettingsDivider()

                Button {
                    legalPage = BSInAppBrowserPage(url: Self.icpQueryURL)
                } label: {
                    SettingsRowContent(
                        iconName: "checkmark.seal.fill",
                        title: BSLocalization.text("ICP备案号"),
                        subtitle: Self.icpFilingNumber,
                        value: nil,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())
            }
        }
        .navigationTitle(BSLocalization.text("关于开场前"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $legalPage) { page in
            BSInAppBrowser(page: page)
        }
    }
}
