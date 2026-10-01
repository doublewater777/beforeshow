import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @AppStorage(FeedbackShakePreferences.appStorageKey) private var isShakeFeedbackEnabled = true
    @ObservedObject private var languageController = AppLanguageController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingProPaywall = false

    var body: some View {
        List {
            Section {
                Button {
                    isShowingProPaywall = true
                } label: {
                    SettingsMembershipCard(
                        summary: membershipSummary,
                        actionTitle: membershipActionTitle
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(header: Text(BSLocalization.text("小组件"))) {
                NavigationLink {
                    WidgetSettingsView()
                } label: {
                    SettingsNativeRow(
                        icon: "square.text.square.fill",
                        iconBackground: BSColor.Stage.accent,
                        title: BSLocalization.text("桌面与锁屏小组件"),
                        subtitle: BSLocalization.text("主屏幕和锁屏倒计时"),
                        value: widgetStatusText
                    )
                }
                .listRowBackground(BSColor.Stage.surface)
            }

            Section(header: Text(BSLocalization.text("通知与数据"))) {
                NotificationSettingsRow()
                    .listRowBackground(BSColor.Stage.surface)

                NavigationLink {
                    PrivacyLocalDataView()
                } label: {
                    SettingsNativeRow(
                        icon: "lock.fill",
                        iconBackground: Color(red: 0.35, green: 0.55, blue: 0.85),
                        title: SettingsEntry.privacyAndLocalData.displayTitle
                    )
                }
                .listRowBackground(BSColor.Stage.surface)
            }

            Section(header: Text(BSLocalization.text("支持"))) {
                NavigationLink {
                    FeedbackView()
                } label: {
                    SettingsNativeRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        iconBackground: Color(red: 0.40, green: 0.75, blue: 0.65),
                        title: SettingsEntry.feedback.displayTitle
                    )
                }
                .listRowBackground(BSColor.Stage.surface)

                Toggle(isOn: $isShakeFeedbackEnabled) {
                    SettingsNativeRow(
                        icon: "iphone.gen3.radiowaves.left.and.right",
                        iconBackground: Color(red: 0.55, green: 0.45, blue: 0.75),
                        title: BSLocalization.text("摇一摇反馈"),
                        subtitle: BSLocalization.text("晃动 iPhone 快速呼出反馈表单")
                    )
                }
                .tint(BSColor.Stage.accent)
                .listRowBackground(BSColor.Stage.surface)

                Button {
                    AppReviewPrompt.consider(.settings)
                } label: {
                    HStack {
                        SettingsNativeRow(
                            icon: "star.fill",
                            iconBackground: Color(red: 0.95, green: 0.75, blue: 0.30),
                            title: SettingsEntry.rateApp.displayTitle
                        )
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(BSColor.Stage.surface)
                .accessibilityHint(BSLocalization.text("打开 App Store 写下评价"))
            }

            Section(header: Text(BSLocalization.text("语言"))) {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    SettingsNativeRow(
                        icon: "globe",
                        iconBackground: Color(red: 0.35, green: 0.65, blue: 0.95),
                        title: BSLocalization.text("App 语言"),
                        value: languageController.language.displayName
                    )
                }
                .listRowBackground(BSColor.Stage.surface)
            }

            Section(header: Text(BSLocalization.text("关于"))) {
                NavigationLink {
                    AboutBeforeShowView()
                } label: {
                    SettingsNativeRow(
                        icon: "info.circle.fill",
                        iconBackground: Color(red: 0.55, green: 0.55, blue: 0.65),
                        title: SettingsEntry.about.displayTitle,
                        value: AppVersionInformation.current.compactCopy
                    )
                }
                .listRowBackground(BSColor.Stage.surface)
            }

            #if DEBUG
            Section(header: Text(BSLocalization.text("调试"))) {
                ProEntitlementDebugPicker()
                    .listRowBackground(BSColor.Stage.surface)

                DebugPrintPendingNotificationsRow()
                    .listRowBackground(BSColor.Stage.surface)
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .navigationTitle(BSLocalization.text("设置"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            BSChromeToolbarCloseButton { dismiss() }
        }
        .sheet(isPresented: $isShowingProPaywall) {
            ProPaywallSheetView()
        }
    }

    private var membershipSummary: SettingsMembershipSummary {
        SettingsMembershipSummary(entitlement: ProEntitlementStorage.decode(entitlementRawValue))
    }

    private var membershipActionTitle: String {
        switch ProEntitlementStorage.decode(entitlementRawValue) {
        case .active:
            return BSLocalization.text("查看会员方案与权益")
        case .free, .expired:
            return BSLocalization.text("查看会员方案与购买")
        }
    }

    private var widgetStatusText: String {
        if let snapshot = WidgetSnapshotStore.read() {
            return snapshot.name
        }
        return BSLocalization.text("未添加")
    }
}

// MARK: - Native Row Component

struct SettingsNativeRow: View {
    let icon: String
    var iconBackground: Color = BSColor.Stage.accent
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueTint: Color = BSColor.Stage.muted

    var body: some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(iconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BSFont.V3.body)
                    .foregroundColor(BSColor.Stage.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(BSFont.V3.small)
                        .foregroundColor(BSColor.Stage.muted)
                }
            }

            if let value {
                Spacer()
                Text(value)
                    .font(BSFont.V3.body)
                    .foregroundColor(valueTint)
            }
        }
    }
}

// MARK: - Membership Card

private struct SettingsMembershipCard: View {
    let summary: SettingsMembershipSummary
    let actionTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            HStack(alignment: .top, spacing: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(BSLocalization.text("当前方案"))
                        .font(BSFont.tag)
                        .foregroundColor(BSColor.Stage.dim)

                    Text(summary.title)
                        .font(BSFont.V3.title2)
                        .foregroundColor(BSColor.Stage.foreground)

                    Text(summary.subtitle)
                        .font(BSFont.V3.body)
                        .foregroundColor(BSColor.Stage.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: BSSpacing.sm)

                Image(systemName: "crown.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(BSColor.Stage.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                    .accessibilityHidden(true)
            }

            Divider()
                .overlay(BSColor.Stage.border)

            HStack(spacing: BSSpacing.sm) {
                Text(actionTitle)
                    .font(BSFont.V3.body.weight(.medium))
                    .foregroundColor(BSColor.Stage.accent)

                Spacer(minLength: BSSpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(BSColor.Stage.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(BSSpacing.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Stage.surface)
        .background(alignment: .topTrailing) {
            RadialGradient(
                colors: [BSColor.Stage.accent.opacity(BSSettingsStyle.membershipGlowOpacity), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: BSSettingsStyle.membershipGlowRadius
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.Stage.accent.opacity(BSSettingsStyle.membershipBorderOpacity), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityHint(BSLocalization.text("打开 Pro 会员方案"))
    }
}

// MARK: - Notification Row

private struct NotificationSettingsRow: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var authorizationState: NotificationAuthorizationState = .notDetermined
    @State private var isPerformingAction = false

    var body: some View {
        Button(action: performAction) {
            HStack {
                SettingsNativeRow(
                    icon: "bell.fill",
                    iconBackground: Color(red: 0.95, green: 0.40, blue: 0.40),
                    title: BSLocalization.text("开场提醒"),
                    value: isPerformingAction ? nil : presentation.status,
                    valueTint: statusTint
                )

                if isPerformingAction {
                    Spacer()
                    ProgressView()
                        .tint(BSColor.Stage.foreground)
                } else if presentation.action == .openSystemSettings {
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.dim)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPerformingAction)
        .accessibilityLabel(BSLocalization.format("开场提醒，%@", presentation.status))
        .accessibilityHint(
            presentation.action == .requestPermission
                ? BSLocalization.text("轻点请求通知权限")
                : BSLocalization.text("轻点前往系统设置管理通知")
        )
        .task {
            await refreshAuthorizationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshAuthorizationState()
                await reconcilePortfolioAfterAuthorizationChange()
            }
        }
    }

    private var presentation: NotificationSettingsPresentation {
        NotificationSettingsPresentation(authorizationState: authorizationState)
    }

    private var statusTint: Color {
        switch authorizationState {
        case .authorized, .provisional:
            return BSColor.Stage.success
        case .denied:
            return BSColor.Stage.danger
        case .notDetermined:
            return BSColor.Stage.muted
        }
    }

    private func performAction() {
        guard !isPerformingAction else { return }
        isPerformingAction = true

        Task { @MainActor in
            switch presentation.action {
            case .requestPermission:
                _ = await LocalNotificationCenter.shared.requestAuthorization()
                await refreshAuthorizationState()
                await reconcilePortfolioAfterAuthorizationChange()
            case .openSystemSettings:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
            }
            isPerformingAction = false
        }
    }

    @MainActor
    private func refreshAuthorizationState() async {
        authorizationState = await LocalNotificationCenter.shared.authorizationState()
    }

    @MainActor
    private func reconcilePortfolioAfterAuthorizationChange() async {
        guard authorizationState == .authorized || authorizationState == .provisional else { return }
        await LocalNotificationCenter.shared.reconcilePortfolio(
            in: ModelContext(modelContext.container)
        )
    }
}
