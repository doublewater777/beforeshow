import SwiftData
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Settings View

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

private struct SettingsPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? BSSettingsStyle.pressedOpacity : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: BSMotion.micro), value: configuration.isPressed)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(BSColor.Stage.border)
            .padding(.leading, BSSettingsStyle.rowDividerInset)
    }
}

private struct SettingsGroup<Content: View>: View {
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

private struct SettingsRowContent: View {
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
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
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
                await reconcileFocusAfterAuthorizationChange()
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
                // 之前被拒 / 未决时排期可能是空的，授权后立刻按当前现场补齐。
                await reconcileFocusAfterAuthorizationChange()
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

    /// 用户在系统设置里打开开关后回到 app 也走这里：把排期补齐到当前现场。
    @MainActor
    private func reconcileFocusAfterAuthorizationChange() async {
        guard authorizationState == .authorized || authorizationState == .provisional else { return }
        let currentShow = CurrentShowSession().selectCurrentShow(
            from: shows,
            manualSelection: selections.first
        )
        await LocalNotificationCenter.shared.reconcileFocus(
            to: currentShow,
            in: ModelContext(modelContext.container)
        )
    }
}

#if DEBUG
private enum DebugProEntitlementOption: String, CaseIterable {
    case free
    case active
    case expired

    var state: ProEntitlementState {
        switch self {
        case .free:
            return .free
        case .active:
            return .active(productID: "debug.local.pro", expirationDate: nil)
        case .expired:
            return .expired(productID: "debug.local.pro", expirationDate: Date(timeIntervalSince1970: 0))
        }
    }

    init(state: ProEntitlementState) {
        switch state {
        case .free:
            self = .free
        case .active:
            self = .active
        case .expired:
            self = .expired
        }
    }
}

private struct ProEntitlementDebugPicker: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""

    private var selectedOption: DebugProEntitlementOption {
        get {
            DebugProEntitlementOption(state: ProEntitlementStorage.decode(entitlementRawValue))
        }
        nonmutating set {
            entitlementRawValue = ProEntitlementStorage.encode(newValue.state)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(BSLocalization.text("Pro 状态测试"))
                .font(BSFont.V3.body.weight(.semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("切换后立即生效，仅调试构建可见。"))
                .font(BSFont.V3.body)
                .foregroundColor(BSColor.Stage.muted)

            Picker(BSLocalization.text("Pro 状态"), selection: Binding(get: { selectedOption }, set: { selectedOption = $0 })) {
                ForEach(DebugProEntitlementOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(BSSpacing.md)
    }
}

extension DebugProEntitlementOption {
    var displayName: String {
        switch self {
        case .free: return BSLocalization.text("免费版")
        case .active: return BSLocalization.text("Pro 已启用")
        case .expired: return BSLocalization.text("Pro 已过期")
        }
    }
}

private struct DebugPrintPendingNotificationsRow: View {
    @State private var isPrinting = false

    var body: some View {
        Button {
            isPrinting = true
            Task { @MainActor in
                await LocalNotificationCenter.shared.printPendingRequests()
                isPrinting = false
            }
        } label: {
            HStack(spacing: BSSpacing.md) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(width: 34, height: 34)
                    .background(BSColor.Stage.muted.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text("打印待发通知")
                        .font(BSFont.V3.body.weight(.semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                    Text("输出当前现场已排程的本地通知到控制台")
                        .font(BSFont.V3.body)
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer()

                if isPrinting {
                    ProgressView()
                }
            }
            .padding(BSSpacing.md)
        }
        .buttonStyle(SettingsPressButtonStyle())
    }
}
#endif

private struct PrivacyLocalDataView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(ProductAnalyticsPreferences.appStorageKey) private var productAnalyticsEnabled = true
    @State private var inventory: LocalDataInventory?
    @State private var clearFeedback: ClearDataFeedback?
    @State private var isClearing = false
    @State private var showsClearConfirmation = false

    var body: some View {
        BSStageScaffold(title: "", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
            SettingsGroup(title: BSLocalization.text("产品改进")) {
                Toggle(isOn: productAnalyticsBinding) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(BSLocalization.text("帮助改进产品"))
                            .font(BSFont.V3.body.weight(.semibold))
                            .foregroundColor(BSColor.Stage.foreground)
                        Text(BSLocalization.text("匿名分析与操作回放，用于发现卡点和修复问题。可随时关闭。"))
                            .font(BSFont.V3.body)
                            .foregroundColor(BSColor.Stage.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(BSColor.Stage.accent)
                .padding(.horizontal, BSSpacing.md)
                .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
                .accessibilityHint(BSLocalization.text("关闭后停止发送匿名分析与操作回放"))
            }

            SettingsGroup(title: BSLocalization.text("本地数据")) {
                if let inventory {
                    if inventory.isEmpty {
                        settingsStatusRow(BSLocalization.text("暂无本地数据"))
                    } else {
                        inventoryRow(BSLocalization.text("现场"), value: BSLocalization.format("%lld 场", inventory.showCount))
                        SettingsDivider()
                        inventoryRow(BSLocalization.text("记忆碎片"), value: BSLocalization.format("%lld 条", inventory.memoryFragmentCount))
                        SettingsDivider()
                        inventoryRow(BSLocalization.text("票根与时刻表"), value: BSLocalization.format("%lld 个", inventory.assetCount))
                        SettingsDivider()
                        inventoryRow(BSLocalization.text("动态封面"), value: BSLocalization.format("%lld 个", inventory.dynamicCoverCount))
                        SettingsDivider()
                        inventoryRow(BSLocalization.text("App 内占用"), value: formattedBytes(inventory.appBytes))
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BSSpacing.md)
                        .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
                }
            }

            SettingsGroup(title: "清除本地数据") {
                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    HStack(spacing: BSSpacing.sm) {
                        if isClearing {
                            ProgressView()
                        }
                        Text("清除 BeforeShow 本地数据")
                    }
                }
                .buttonStyle(BSDangerButtonStyle())
                .disabled(isClearing || inventory?.isEmpty != false)
                .opacity(isClearing || inventory?.isEmpty != false ? 0.35 : 1)
                .padding(.horizontal, BSSpacing.md)
                .padding(.vertical, BSSettingsStyle.rowVerticalPadding)

                if let clearFeedback {
                    SettingsDivider()
                    Label(
                        clearFeedback.text,
                        systemImage: clearFeedback.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                    )
                    .font(BSFont.V3.body)
                    .foregroundColor(clearFeedback.isError ? BSColor.Stage.danger : BSColor.Stage.success)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BSSpacing.md)
                    .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .alert(
            DangerConfirmation.clearLocalData.title,
            isPresented: $showsClearConfirmation
        ) {
            Button(DangerConfirmation.clearLocalData.confirmTitle, role: .destructive) {
                clearLocalData()
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(DangerConfirmation.clearLocalData.message)
        }
        .navigationTitle(BSLocalization.text("隐私与本地数据"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshInventory()
        }
    }

    private var productAnalyticsBinding: Binding<Bool> {
        Binding(
            get: { productAnalyticsEnabled },
            set: { newValue in
                productAnalyticsEnabled = newValue
                ProductAnalyticsPreferences.apply(newValue)
            }
        )
    }

    private func inventoryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(BSFont.V3.body)
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Text(value)
                .font(BSFont.V3.body.weight(.medium))
                .foregroundColor(BSColor.Stage.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: BSSettingsStyle.rowMinimumHeight, alignment: .leading)
    }

    private func settingsStatusRow(_ text: String) -> some View {
        Text(text)
            .font(BSFont.V3.body)
            .foregroundColor(BSColor.Stage.muted)
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: BSSettingsStyle.rowMinimumHeight, alignment: .leading)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @MainActor
    private func refreshInventory() async {
        inventory = await LocalDataInventoryService.compute(modelContext: modelContext)
    }

    private func clearLocalData() {
        let before = inventory
        isClearing = true
        clearFeedback = nil
        Task { @MainActor in
            do {
                let context = modelContext
                await ShowAssetMediaStore.shared.acquireCommitGate()
                ShowAssetCleanupRetry.markFullCleanupPrepared()
                do {
                    try context.delete(model: Show.self)
                    try context.delete(model: CurrentShowSelection.self)
                    try context.delete(model: NotificationSchedulingState.self)
                    try context.delete(model: ShowNotificationScheduleRecord.self)
                    try context.delete(model: MemoryMediaItem.self)
                    try context.delete(model: MemoryFragment.self)
                    try context.delete(model: ShowAsset.self)
                    try context.delete(model: DynamicCover.self)
                    try context.save()
                    // 系统通知中心里的 pending 请求不受 SwiftData 删除影响，
                    // 必须显式清掉，否则清空数据后通知仍按时弹出、深链指向已删除的现场。
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                } catch {
                    context.rollback()
                    throw error
                }
                DynamicCoverFaceStore.clearAll()
                ShowAssetCleanupRetry.markFullCleanupPending()
                ShowAssetCleanupRetry.clearFullCleanupPrepared()

                var cleanupFailures: [String] = []
                try await MemoryFragmentMediaStore.shared.deleteAll()
                do {
                    try await ShowAssetMediaStore.shared.deleteAll()
                } catch {
                    cleanupFailures.append(BSLocalization.text("票根和时刻表副本"))
                }
                do {
                    try await DynamicCoverMediaStore.shared.deleteAll()
                } catch {
                    cleanupFailures.append(BSLocalization.text("动态封面视频副本"))
                }
                if cleanupFailures.isEmpty {
                    ShowAssetCleanupRetry.clearFullCleanupPending()
                }

                await ShowAssetMediaStore.shared.releaseCommitGate()

                if cleanupFailures.isEmpty {
                    let freedBytes = before?.mediaBytes ?? 0
                    clearFeedback = .success(freedBytes > 0
                        ? BSLocalization.format("已清除本地数据，释放 %@。", formattedBytes(freedBytes))
                        : BSLocalization.text("已清除本地数据。"))
                } else {
                    clearFeedback = .failure(BSLocalization.format("部分内容未清除（%@），将于下次启动时重试。", cleanupFailures.joined(separator: "、")))
                }
            } catch {
                ShowAssetCleanupRetry.clearFullCleanupPrepared()
                clearFeedback = .failure(BSLocalization.text("清除本地数据失败，请重试。"))
                await ShowAssetMediaStore.shared.releaseCommitGate()
            }
            isClearing = false
            await refreshInventory()
        }
    }
}

enum ClearDataFeedback: Equatable {
    case success(String)
    case failure(String)

    var text: String {
        switch self {
        case .success(let text): return text
        case .failure(let text): return text
        }
    }

    var isError: Bool {
        if case .failure = self { return true }
        return false
    }
}

private struct FeedbackView: View {
    @State private var message = ""
    @State private var includesDiagnostics = false
    @State private var validationMessage: String?
    @State private var sendState: FeedbackSendState = .idle
    @FocusState private var isMessageFocused: Bool

    private let payloadBuilder = FeedbackPayloadBuilder()
    private let shareTextBuilder = FeedbackShareTextBuilder()

    var body: some View {
        BSStageScaffold(
            title: "",
            subtitle: nil,
            bottomPadding: BSSpacing.xl
        ) {
            BSSettingsSurface(padding: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: BSSpacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text(BSLocalization.text("被采纳的反馈会获得奖励"))
                            .font(BSFont.caption.weight(.semibold))
                    }
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("例如：在哪一步遇到了什么，期待结果是什么")
                                .font(BSFont.V3.body)
                                .foregroundColor(BSColor.Stage.dim)
                                .padding(.horizontal, 19)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $message)
                            .font(BSFont.V3.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .bsInputField()
                            .focused($isMessageFocused)
                            .accessibilityLabel("反馈内容，必填")
                            .accessibilityHint("请说明遇到的问题或建议")
                            .onChange(of: message) {
                                if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    validationMessage = nil
                                }
                            }
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(BSFont.V3.body)
                            .foregroundColor(BSColor.Stage.danger)
                            .accessibilityAddTraits(.isStaticText)
                    }

                    Toggle(BSLocalization.text("附上 App 版本与系统版本"), isOn: $includesDiagnostics)
                        .tint(BSColor.Stage.accent)
                        .foregroundColor(BSColor.Stage.muted)
                        .font(BSFont.V3.body)

                    Text("不会自动包含现场内容、截图、照片或视频。")
                        .font(BSFont.V3.body)
                        .foregroundColor(BSColor.Stage.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isMessageFocused = false
                }
            }

            Button {
                prepareFeedback()
            } label: {
                Label(
                    sendState == .sent ? "已唤起邮件 app" : "通过邮件发送反馈",
                    systemImage: sendState == .sent ? "checkmark.circle.fill" : "envelope.fill"
                )
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(sendState == .sending || sendState == .sent)
            .accessibilityHint("打开系统邮件 app，并预填反馈内容")

            if case .failed(let reason) = sendState {
                Label(reason, systemImage: "exclamationmark.circle.fill")
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.danger)
                    .accessibilityAddTraits(.isStaticText)
                    .padding(.top, BSSpacing.xs)
            }
        }
       .toolbar {
           ToolbarItemGroup(placement: .keyboard) {
               Spacer()

                Button("完成") {
                    isMessageFocused = false
                }
            }
        }
        .navigationTitle(BSLocalization.text("意见反馈"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prepareFeedback() {
        do {
            let payload = try payloadBuilder.build(from: FeedbackDraft(
                message: message,
                includesDiagnostics: includesDiagnostics
            ))
            validationMessage = nil
            Task { @MainActor in
                await presentMailto(shareTextBuilder.build(from: payload))
            }
        } catch {
            validationMessage = BSLocalization.text("请先填写反馈内容")
        }
    }

    @MainActor
    private func presentMailto(_ text: String) async {
        sendState = .sending
        guard let url = FeedbackDestination.mailtoURL(prefilledBody: text) else {
            sendState = .failed(BSLocalization.text("无法生成邮件链接"))
            return
        }
        let accepted = await FeedbackMailOpener.open(url: url)
        // 两种 accepted=false 场景：设备没装邮件 app / 装但未配账户。`open(mailto:)`
        // 对两者都返回 false，文案上给出唯一可执行的引导（去系统设置查看账户/添加 app）。
        sendState = accepted ? .sent : .failed(BSLocalization.text("无法唤起邮件 app，请检查系统邮件账户或 App Store 安装"))
    }
}

enum FeedbackSendState: Equatable {
    case idle
    case sending
    case sent
    case failed(String)
}

private struct LanguageSettingsView: View {
    @ObservedObject private var languageController = AppLanguageController.shared

    var body: some View {
        BSStageScaffold(title: "", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
            BSSettingsSurface {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            languageController.select(language)
                        } label: {
                            HStack(spacing: BSSpacing.compact) {
                                Text(language.displayName)
                                    .font(BSFont.V3.body.weight(.semibold))
                                    .foregroundColor(BSColor.Stage.foreground)
                                Spacer(minLength: 0)
                                if languageController.language == language {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(BSColor.Stage.accent)
                                }
                            }
                            .padding(.horizontal, BSSpacing.md)
                            .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
                            .frame(maxWidth: .infinity, minHeight: BSSettingsStyle.rowMinimumHeight, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SettingsPressButtonStyle())
                        .accessibilityLabel(language.displayName)
                        .accessibilityAddTraits(languageController.language == language ? .isSelected : [])

                        if language != AppLanguage.allCases.last {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
        .navigationTitle(BSLocalization.text("语言"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutBeforeShowView: View {
    private static let privacyURL = URL(string: "https://beforeshow.doublewaterapps.com/privacy")!
    private static let termsURL = URL(string: "https://beforeshow.doublewaterapps.com/terms")!
    private static let icpFilingNumber = "浙ICP备2026041359号-3A"
    private static let icpQueryURL = URL(string: "https://beian.miit.gov.cn/")!
    @State private var legalPage: BSInAppBrowserPage?
    @State private var weatherLegalURL: URL?

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

                if let weatherLegalURL {
                    SettingsDivider()
                    Button {
                        legalPage = BSInAppBrowserPage(url: weatherLegalURL)
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
                }

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
        .task {
            weatherLegalURL = await WeatherKitLegalAttribution.legalPageURL()
        }
        .sheet(item: $legalPage) { page in
            BSInAppBrowser(page: page)
        }
    }
}
