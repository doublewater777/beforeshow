import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingProPaywall = false

    /// 设置以 sheet 形式呈现，自带 NavigationStack 容纳内层子页面。
    var body: some View {
        BSStageScaffold(
            title: "",
            subtitle: nil,
            bottomPadding: BSSpacing.xl
        ) {
            Button {
                isShowingProPaywall = true
            } label: {
                SettingsMembershipCard(summary: membershipSummary)
            }
            .buttonStyle(SettingsPressButtonStyle())

            SettingsGroup(title: BSLocalization.text("通知与数据")) {
                NotificationSettingsRow()

                SettingsDivider()

                NavigationLink {
                    PrivacyLocalDataView()
                } label: {
                    SettingsRowContent(
                        iconName: "lock.fill",
                        title: SettingsEntry.privacyAndLocalData.displayTitle,
                        subtitle: nil,
                        value: nil,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())
            }

            SettingsGroup(title: BSLocalization.text("支持")) {
                NavigationLink {
                    FeedbackView()
                } label: {
                    SettingsRowContent(
                        iconName: "bubble.left.and.bubble.right.fill",
                        title: SettingsEntry.feedback.displayTitle,
                        subtitle: nil,
                        value: nil,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())

                SettingsDivider()

                Button {
                    AppReviewPrompt.consider(.settings)
                } label: {
                    SettingsRowContent(
                        iconName: "star.fill",
                        title: SettingsEntry.rateApp.displayTitle,
                        subtitle: nil,
                        value: nil,
                        tint: BSColor.Stage.muted,
                        trailingIconName: "arrow.up.right.square"
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())
                .accessibilityHint(BSLocalization.text("打开 App Store 写下评价"))
            }

            SettingsGroup(title: BSLocalization.text("语言")) {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    SettingsRowContent(
                        iconName: "globe",
                        title: BSLocalization.text("App 语言"),
                        subtitle: nil,
                        value: AppLanguageController.shared.language.displayName,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())
            }

            SettingsGroup(title: BSLocalization.text("关于")) {
                NavigationLink {
                    AboutBeforeShowView()
                } label: {
                    SettingsRowContent(
                        iconName: "info.circle.fill",
                        title: SettingsEntry.about.displayTitle,
                        subtitle: nil,
                        value: AppVersionInformation.current.compactCopy,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())
            }

            #if DEBUG
            SettingsGroup(title: BSLocalization.text("调试")) {
                ProEntitlementDebugPicker()

                SettingsDivider()

                DebugPrintPendingNotificationsRow()
            }
            #endif
        }
        .navigationTitle("设置")
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
}

private struct SettingsMembershipCard: View {
    let summary: SettingsMembershipSummary

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            HStack(alignment: .top, spacing: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text("当前方案")
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
                Text("查看会员方案与购买")
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
        .accessibilityHint("打开 Pro 会员方案")
    }
}

struct SettingsPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? BSSettingsStyle.pressedOpacity : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: BSMotion.micro), value: configuration.isPressed)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(BSColor.Stage.border)
            .padding(.leading, BSSettingsStyle.rowDividerInset)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(title)
                .font(BSFont.tag)
                .foregroundColor(BSColor.Stage.dim)
                .padding(.horizontal, BSSpacing.xs)

            BSSettingsSurface {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
            }
        }
    }
}

struct SettingsRowContent: View {
    let iconName: String
    let title: String
    let subtitle: String?
    let value: String?
    let tint: Color
    var valueTint: Color = BSColor.Stage.muted
    var trailingIconName = "chevron.right"

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BSSpacing.compact) {
                    HStack(spacing: BSSpacing.compact) {
                        icon
                        Text(title)
                            .font(BSFont.V3.body.weight(.semibold))
                            .foregroundColor(BSColor.Stage.foreground)

                        Spacer(minLength: BSSpacing.sm)
                        trailingIcon
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(BSFont.V3.body)
                            .foregroundColor(BSColor.Stage.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let value {
                        Text(value)
                            .font(BSFont.V3.body.weight(.medium))
                            .foregroundColor(valueTint)
                    }
                }
            } else {
                HStack(spacing: BSSpacing.compact) {
                    icon

                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(title)
                            .font(BSFont.V3.body.weight(.semibold))
                            .foregroundColor(BSColor.Stage.foreground)
                        if let subtitle {
                            Text(subtitle)
                                .font(BSFont.V3.body)
                                .foregroundColor(BSColor.Stage.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .layoutPriority(1)

                    Spacer(minLength: BSSpacing.sm)

                    if let value {
                        Text(value)
                            .font(BSFont.V3.small.weight(.semibold))
                            .foregroundColor(valueTint)
                            .lineLimit(1)
                    }

                    trailingIcon
                }
            }
        }
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: BSSettingsStyle.rowMinimumHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var icon: some View {
        Image(systemName: iconName)
            .font(.system(size: BSSettingsStyle.iconSize, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: BSSettingsStyle.iconContainerSize, height: BSSettingsStyle.iconContainerSize)
            .background(tint.opacity(BSSettingsStyle.iconSurfaceOpacity))
            .clipShape(RoundedRectangle(cornerRadius: BSSettingsStyle.iconCornerRadius))
            .accessibilityHidden(true)
    }

    private var trailingIcon: some View {
        Image(systemName: trailingIconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(BSColor.Stage.dim)
            .accessibilityHidden(true)
    }
}

private struct NotificationSettingsRow: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var authorizationState: NotificationAuthorizationState = .notDetermined
    @State private var isPerformingAction = false

    var body: some View {
        Button(action: performAction) {
            SettingsRowContent(
                iconName: "bell.fill",
                title: BSLocalization.text("开场提醒"),
                subtitle: nil,
                value: isPerformingAction ? nil : presentation.status,
                tint: statusTint,
                valueTint: statusTint,
                trailingIconName: presentation.action == .openSystemSettings
                    ? "arrow.up.right.square"
                    : "chevron.right"
            )
            .overlay(alignment: .trailing) {
                if isPerformingAction {
                    ProgressView()
                        .tint(BSColor.Stage.foreground)
                        .padding(.trailing, BSSpacing.md)
                }
            }
        }
        .buttonStyle(SettingsPressButtonStyle())
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
                // 之前未授权时系统 pending 可能不完整，授权后立刻对齐完整 portfolio。
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

    /// 用户在系统设置里打开开关后回到 app 也走这里：把完整通知组合补齐。
    @MainActor
    private func reconcilePortfolioAfterAuthorizationChange() async {
        guard authorizationState == .authorized || authorizationState == .provisional else { return }
        await LocalNotificationCenter.shared.reconcilePortfolio(
            reason: .foreground,
            in: ModelContext(modelContext.container)
        )
    }
}
