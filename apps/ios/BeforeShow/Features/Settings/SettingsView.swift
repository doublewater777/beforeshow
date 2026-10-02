import SwiftData
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Settings View (BeforeShow Stage Edition)
// 遵循 DESIGN.md V3 规范：一体化深炭卡片容器、暖金与舞台蓝克制色阶、Live Pass 票根质感。

struct SettingsView: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @AppStorage(FeedbackShakePreferences.appStorageKey) private var isShakeFeedbackEnabled = true
    @ObservedObject private var languageController = AppLanguageController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingProPaywall = false

    var body: some View {
        List {
            // 会员通行证卡片
            Section {
                Button {
                    isShowingProPaywall = true
                } label: {
                    SettingsMembershipPassCard(
                        summary: membershipSummary,
                        actionTitle: membershipActionTitle
                    )
                }
                .buttonStyle(SettingsPassPressStyle())
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            // 核心功能
            Section {
                NavigationLink {
                    WidgetSettingsView()
                } label: {
                    BSSettingsRow(
                        icon: "square.stack.3d.down.right.fill",
                        tint: BSColor.Stage.accent,
                        title: BSLocalization.text("小组件")
                    )
                }
                .listRowBackground(BSColor.Stage.surface)

                NotificationSettingsRow()
                    .listRowBackground(BSColor.Stage.surface)

                NavigationLink {
                    PrivacyLocalDataView()
                } label: {
                    BSSettingsRow(
                        icon: "lock.fill",
                        tint: BSColor.Stage.glowBlue,
                        title: SettingsEntry.privacyAndLocalData.displayTitle
                    )
                }
                .listRowBackground(BSColor.Stage.surface)
            } header: {
                Text(BSLocalization.text("核心功能"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BSColor.Stage.muted)
            }

            // 交互与支持
            Section {
                NavigationLink {
                    FeedbackView()
                } label: {
                    BSSettingsRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        tint: BSColor.Stage.prepare,
                        title: SettingsEntry.feedback.displayTitle
                    )
                }
                .listRowBackground(BSColor.Stage.surface)

                Toggle(isOn: $isShakeFeedbackEnabled) {
                    BSSettingsRow(
                        icon: "iphone.radiowaves.left.and.right",
                        tint: BSColor.Stage.prepare,
                        title: BSLocalization.text("摇一摇反馈")
                    )
                }
                .tint(BSColor.Stage.accent)
                .listRowBackground(BSColor.Stage.surface)

                Button {
                    AppReviewPrompt.consider(.settings)
                } label: {
                    HStack {
                        BSSettingsRow(
                            icon: "star.fill",
                            tint: BSColor.Stage.accent,
                            title: SettingsEntry.rateApp.displayTitle
                        )
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BSColor.Stage.dim)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(BSColor.Stage.surface)
            } header: {
                Text(BSLocalization.text("支持与互动"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BSColor.Stage.muted)
            }

            // 系统与关于
            Section {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    BSSettingsRow(
                        icon: "globe",
                        tint: BSColor.Stage.glowBlue,
                        title: BSLocalization.text("语言"),
                        value: languageController.language.displayName
                    )
                }
                .listRowBackground(BSColor.Stage.surface)

                NavigationLink {
                    AboutBeforeShowView()
                } label: {
                    BSSettingsRow(
                        icon: "info.circle.fill",
                        tint: BSColor.Stage.heroWarmGold,
                        title: SettingsEntry.about.displayTitle,
                        value: AppVersionInformation.current.compactCopy
                    )
                }
                .listRowBackground(BSColor.Stage.surface)
            } header: {
                Text(BSLocalization.text("系统与关于"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BSColor.Stage.muted)
            }

            #if DEBUG
            Section {
                ProEntitlementDebugPicker()
                    .listRowBackground(BSColor.Stage.surface)

                DebugPrintPendingNotificationsRow()
                    .listRowBackground(BSColor.Stage.surface)
            } header: {
                Text(BSLocalization.text("调试"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BSColor.Stage.muted)
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(stageBackground)
        .navigationTitle(BSLocalization.text("设置"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            BSChromeToolbarCloseButton { dismiss() }
        }
        .sheet(isPresented: $isShowingProPaywall) {
            ProPaywallSheetView()
        }
    }

    // MARK: - 舞台深邃背景与微光

    private var stageBackground: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()

            RadialGradient(
                colors: [
                    BSColor.Stage.accent.opacity(0.08),
                    .clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 280
            )
            .frame(height: 280)
            .ignoresSafeArea()
        }
    }

    private var membershipSummary: SettingsMembershipSummary {
        SettingsMembershipSummary(entitlement: ProEntitlementStorage.decode(entitlementRawValue))
    }

    private var membershipActionTitle: String {
        switch ProEntitlementStorage.decode(entitlementRawValue) {
        case .active:
            return BSLocalization.text("查看权益")
        case .free, .expired:
            return BSLocalization.text("升级 Pro")
        }
    }
}

// MARK: - Stage Squircle Row

struct BSSettingsRow: View {
    let icon: String
    var tint: Color = BSColor.Stage.accent
    let title: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 30, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(tint.opacity(0.24), lineWidth: 0.5)
                    )

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(BSFont.V3.body)
                .foregroundStyle(BSColor.Stage.foreground)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(BSFont.V3.small)
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// 保持兼容旧调用的辅助桥接
struct SettingsNativeRow: View {
    let icon: String
    var iconBackground: Color = BSColor.Stage.accent
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueTint: Color = BSColor.Stage.muted

    var body: some View {
        BSSettingsRow(icon: icon, tint: iconBackground, title: title, value: value)
    }
}

// MARK: - VIP Live Pass Ticket Card (现场通行证卡片)

private struct SettingsMembershipPassCard: View {
    let summary: SettingsMembershipSummary
    let actionTitle: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(BSLocalization.text("LIVE VIP PASS"))
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(BSColor.Stage.accent.opacity(0.85))

                    Text(summary.title)
                        .font(BSFont.V3.title2)
                        .foregroundStyle(BSColor.Stage.foreground)

                    Text(summary.subtitle)
                        .font(BSFont.V3.small)
                        .foregroundStyle(BSColor.Stage.muted)
                }

                Spacer(minLength: 8)

                // 微晶皇冠徽章
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BSColor.Stage.accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BSColor.Stage.accent.opacity(0.32), lineWidth: 0.5)
                        )

                    Image(systemName: "crown.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(BSColor.Stage.heroWarmGold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            // 票根虚线切痕
            TicketPerforationDivider()
                .padding(.horizontal, 16)

            // 底部行动条
            HStack {
                Text(actionTitle)
                    .font(BSFont.V3.body.weight(.medium))
                    .foregroundStyle(BSColor.Stage.heroWarmGold)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.accent.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BSColor.Stage.surface)
                .overlay(
                    RadialGradient(
                        colors: [
                            BSColor.Stage.accent.opacity(0.14),
                            .clear
                        ],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 180
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    BSColor.Stage.accent.opacity(0.38),
                                    BSColor.Stage.border
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .allowsHitTesting(false)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(BSLocalization.text("打开 Pro 会员方案"))
    }
}

private struct TicketPerforationDivider: View {
    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
            .foregroundStyle(Color.white.opacity(0.10))
            .frame(height: 1)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - 按压反馈 (支持 Reduce Motion)

private struct SettingsPassPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(BSColor.Stage.glowBlue.opacity(0.14))
                        .frame(width: 30, height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(BSColor.Stage.glowBlue.opacity(0.24), lineWidth: 0.5)
                        )

                    Image(systemName: "bell.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.glowBlue)
                }

                Text(BSLocalization.text("开场提醒"))
                    .font(BSFont.V3.body)
                    .foregroundStyle(BSColor.Stage.foreground)

                Spacer(minLength: 8)

                if isPerformingAction {
                    ProgressView()
                        .tint(BSColor.Stage.foreground)
                } else {
                    HStack(spacing: 4) {
                        Text(presentation.status)
                            .font(BSFont.V3.small)
                            .foregroundStyle(statusTint)

                        if presentation.action == .openSystemSettings {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(BSColor.Stage.dim)
                        }
                    }
                }
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(isPerformingAction)
        .accessibilityLabel(BSLocalization.format("开场提醒，%@", presentation.status))
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
            return BSColor.Stage.foreground
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
