import SwiftData
import SwiftUI
import UIKit

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @Environment(\.dismiss) private var dismiss

    /// 设置以 sheet 形式呈现，自带 NavigationStack 容纳内层子页面。
    var body: some View {
        BSStageScaffold(
            title: "",
            subtitle: "管理你的方案、开场提醒与本地数据",
            bottomPadding: BSSpacing.xl
        ) {
            NavigationLink {
                ProMembershipView()
            } label: {
                SettingsMembershipCard(summary: membershipSummary)
            }
            .buttonStyle(SettingsPressButtonStyle())

            SettingsGroup(title: "通知与数据") {
                NotificationSettingsRow()

                SettingsDivider()

                NavigationLink {
                    PrivacyLocalDataView()
                } label: {
                    SettingsRowContent(
                        iconName: "lock.fill",
                        title: SettingsEntry.privacyAndLocalData.rawValue,
                        subtitle: "查看保存范围或清除本地副本",
                        value: nil,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())
            }

            SettingsGroup(title: "支持") {
                NavigationLink {
                    FeedbackView()
                } label: {
                    SettingsRowContent(
                        iconName: "bubble.left.and.bubble.right.fill",
                        title: SettingsEntry.feedback.rawValue,
                        subtitle: "分享使用感受、问题或隐私建议",
                        value: nil,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())
            }

            SettingsGroup(title: "关于") {
                NavigationLink {
                    AboutBeforeShowView()
                } label: {
                    SettingsRowContent(
                        iconName: "info.circle.fill",
                        title: SettingsEntry.about.rawValue,
                        subtitle: "开场之前，先进入状态",
                        value: AppVersionInformation.current.compactCopy,
                        tint: BSColor.Stage.muted
                    )
                }
                .buttonStyle(SettingsPressButtonStyle())
            }

            #if DEBUG
            SettingsGroup(title: "调试") {
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
    @State private var authorizationState: NotificationAuthorizationState = .notDetermined
    @State private var isPerformingAction = false

    var body: some View {
        Button(action: performAction) {
            SettingsRowContent(
                iconName: "bell.fill",
                title: "开场提醒",
                subtitle: presentation.subtitle,
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
        .accessibilityLabel("开场提醒，\(presentation.status)")
        .accessibilityHint(
            presentation.action == .requestPermission
                ? "轻点请求通知权限"
                : "轻点前往系统设置管理通知"
        )
        .task {
            await refreshAuthorizationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshAuthorizationState()
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
            Text("Pro 状态测试")
                .font(BSFont.V3.body.weight(.semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text("切换后立即生效，仅调试构建可见。")
                .font(BSFont.V3.body)
                .foregroundColor(BSColor.Stage.muted)

            Picker("Pro 状态", selection: Binding(get: { selectedOption }, set: { selectedOption = $0 })) {
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
        case .free: return "免费版"
        case .active: return "Pro 已启用"
        case .expired: return "Pro 已过期"
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

struct ProMembershipView: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var products = ProSubscriptionCatalog.defaultProducts
    @State private var isLoadingProducts = false
    @State private var purchasingProductID: String?
    @State private var message: String?

    private let store: any ProSubscriptionStore

    init(store: any ProSubscriptionStore = ProMembershipView.defaultStore()) {
        self.store = store
    }

    var body: some View {
        BSStageScaffold(title: "Pro 会员", subtitle: "无限保存现场", bottomPadding: BSLayout.tabBarContentInset) {
            BSSurfacePanel {
                Text(statusText)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BSSurfacePanel {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    Text(ProMembershipCopy.summary)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    BSSectionHeader(title: "Pro 解锁")
                    ForEach(ProMembershipCopy.unlockedPoints, id: \.self) { point in
                        Label(point, systemImage: "checkmark")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    BSSectionHeader(title: "不需要 Pro 也能用")
                    ForEach(ProMembershipCopy.freePoints, id: \.self) { point in
                        Label(point, systemImage: "checkmark.shield")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(products, id: \.id) { product in
                proProductCard(product)
            }

            Button {
                Task {
                    await restore()
                }
            } label: {
                HStack {
                    if purchasingProductID == "restore" {
                        ProgressView()
                    }
                    Text("恢复购买")
                }
            }
            .buttonStyle(BSSecondaryButtonStyle())
            .disabled(purchasingProductID != nil)

            Text(isLoadingProducts ? "正在从 App Store 加载产品。" : "通过 App Store 订阅；V2.1 不提供免费试用。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)

            if let message {
                Text(message)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
            }
        }
        .task {
            await loadProducts()
        }
    }

    private func proProductCard(_ product: ProSubscriptionProduct) -> some View {
        BSSurfacePanel {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(product.plan == .monthly ? "月度 Pro" : "年度 Pro")
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.textPrimary)
                        Text(product.plan == .monthly ? "按月订阅，随时取消" : "更适合每年看很多现场")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }

                    Spacer()

                    Text(product.priceText)
                        .font(.system(size: 22, weight: .bold))
                        .bsGradientText()
                }

                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    ForEach(product.benefitCopy, id: \.self) { benefit in
                        Label(benefit, systemImage: "checkmark")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textSecondary)
                    }
                }

                if product.plan == .monthly {
                    subscriptionButton(for: product)
                        .buttonStyle(BSPrimaryButtonStyle())
                } else {
                    subscriptionButton(for: product)
                        .buttonStyle(BSSecondaryButtonStyle())
                }
            }
        }
    }

    private func subscriptionButton(for product: ProSubscriptionProduct) -> some View {
        Button {
            Task {
                await purchase(product)
            }
        } label: {
            HStack {
                if purchasingProductID == product.id {
                    ProgressView()
                        .tint(product.plan == .monthly ? .black : BSColor.textPrimary)
                }
                Text(product.plan == .monthly ? "订阅月度 Pro" : "订阅年度 Pro")
            }
        }
        .disabled(purchasingProductID != nil)
    }

    private var entitlement: ProEntitlementState {
        ProEntitlementStorage.decode(entitlementRawValue)
    }

    private var statusText: String {
        switch entitlement {
        case .active:
            return "Pro 已启用，可以继续添加现场。"
        case .expired:
            return "Pro 已过期，已有本地内容仍可查看和编辑。"
        case .free:
            return "当前为免费版：可保存 1 场现场。"
        }
    }

    @MainActor
    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await store.loadProducts()
            if !loadedProducts.isEmpty {
                products = loadedProducts
            }
        } catch {
            message = "暂时没有加载到 App Store 产品，先显示本地订阅信息。"
        }
    }

    @MainActor
    private func purchase(_ product: ProSubscriptionProduct) async {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }

        do {
            let entitlement = try await store.purchase(productID: product.id)
            entitlementRawValue = ProEntitlementStorage.encode(entitlement)
            message = "Pro 已启用。"
        } catch ProSubscriptionError.purchaseCancelled {
            message = "已取消购买。"
        } catch ProSubscriptionError.purchasePending {
            message = "购买正在处理中。"
        } catch {
            message = "购买暂时没有完成。"
        }
    }

    @MainActor
    private func restore() async {
        purchasingProductID = "restore"
        defer { purchasingProductID = nil }

        do {
            let entitlement = try await store.restorePurchases()
            entitlementRawValue = ProEntitlementStorage.encode(entitlement)
            message = "已恢复 Pro。"
        } catch ProSubscriptionError.nothingToRestore {
            message = "没有找到可恢复的 Pro 订阅。"
        } catch {
            message = "恢复购买暂时没有完成。"
        }
    }

    private static func defaultStore() -> any ProSubscriptionStore {
        #if canImport(StoreKit)
        return StoreKitProSubscriptionStore()
        #else
        return MockProSubscriptionStore()
        #endif
    }
}

struct ProMembershipSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProMembershipView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct PrivacyLocalDataView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var clearResult: LocalDataClearancePlan?
    @State private var clearStatusText: String?
    @State private var isClearing = false
    @State private var showsClearConfirmation = false
    private let clearer = LocalDataClearer()

    var body: some View {
        BSStageScaffold(title: "隐私与本地数据", subtitle: "管理 BeforeShow 的本地记录和副本", bottomPadding: BSLayout.tabBarContentInset) {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "隐私说明")
                ForEach(PrivacyLocalDataCopy.points, id: \.self) { point in
                    Label(point, systemImage: "checkmark.shield")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(BSSpacing.md)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.borderProminent, lineWidth: 1))

            BSSurfacePanel {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    Text("清除本地数据")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                    Text(PrivacyLocalDataCopy.clearDataExplanation)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    HStack {
                        if isClearing {
                            ProgressView()
                        }
                        Text("清除 BeforeShow 本地数据")
                    }
                }
                .buttonStyle(BSDangerButtonStyle())
                .disabled(isClearing)

                if let clearResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已清除")
                            .font(BSFont.caption.weight(.semibold))
                            .foregroundColor(BSColor.textPrimary)
                        ForEach(clearResult.deletesAppOwnedData, id: \.self) { item in
                            Text(item)
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textTertiary)
                        }
                        Text("保留")
                            .font(BSFont.caption.weight(.semibold))
                            .foregroundColor(BSColor.textPrimary)
                            .padding(.top, 4)
                        ForEach(clearResult.preservesSystemData, id: \.self) { item in
                            Text(item)
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textTertiary)
                        }
                    }
                }

                if let clearStatusText {
                    Text(clearStatusText)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textSecondary)
                }
                }
            }
        }
        .confirmationDialog(
            DangerConfirmation.clearLocalData.title,
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(DangerConfirmation.clearLocalData.confirmTitle, role: .destructive) {
                clearLocalData()
            }
        } message: {
            Text(DangerConfirmation.clearLocalData.message)
        }
    }

    private func clearLocalData() {
        isClearing = true
        clearStatusText = nil
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
                    cleanupFailures.append("票根和时刻表副本")
                }
                do {
                    try await DynamicCoverMediaStore.shared.deleteAll()
                } catch {
                    cleanupFailures.append("动态封面视频副本")
                }
                if cleanupFailures.isEmpty {
                    ShowAssetCleanupRetry.clearFullCleanupPending()
                }

                if cleanupFailures.isEmpty {
                    clearResult = try await clearer.clearAppOwnedLocalData()
                    clearStatusText = nil
                } else {
                    clearResult = nil
                    clearStatusText = "部分内容未清除（\(cleanupFailures.joined(separator: "、"))），将于下次启动时重试。"
                }
                await ShowAssetMediaStore.shared.releaseCommitGate()
            } catch {
                ShowAssetCleanupRetry.clearFullCleanupPrepared()
                clearResult = nil
                clearStatusText = "清除本地数据失败，请重试。"
                await ShowAssetMediaStore.shared.releaseCommitGate()
            }
            isClearing = false
        }
    }
}

private struct FeedbackView: View {
    @State private var category: FeedbackCategory = .product
    @State private var message = ""
    @State private var includesDiagnostics = false
    @State private var validationMessage: String?
    @State private var sendState: FeedbackSendState = .idle
    @FocusState private var isMessageFocused: Bool

    private let payloadBuilder = FeedbackPayloadBuilder()
    private let shareTextBuilder = FeedbackShareTextBuilder()

    var body: some View {
        BSStageScaffold(
            title: "意见反馈",
            subtitle: "整理成一段最小反馈，由 app 唤起系统邮件完成发送",
            bottomPadding: BSSpacing.xl
        ) {
            BSSettingsSurface(padding: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    Text("反馈类型")
                        .font(BSFont.V3.body.weight(.semibold))
                        .foregroundColor(BSColor.Stage.foreground)

                    Picker("类型", selection: $category) {
                        ForEach(FeedbackCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                        Text("反馈内容")
                            .font(BSFont.V3.body.weight(.semibold))
                            .foregroundColor(BSColor.Stage.foreground)

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
                    }

                    Toggle("附上 App 版本与系统版本", isOn: $includesDiagnostics)
                        .tint(BSColor.Stage.accent)
                        .foregroundColor(BSColor.Stage.muted)
                        .font(BSFont.V3.body)

                    Text("不会自动包含现场内容、截图、照片或视频。邮件 app 打开后，发送仍由你确认。")
                        .font(BSFont.V3.body)
                        .foregroundColor(BSColor.Stage.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
    }

    private func prepareFeedback() {
        do {
            let payload = try payloadBuilder.build(from: FeedbackDraft(
                category: category,
                message: message,
                includesDiagnostics: includesDiagnostics
            ))
            validationMessage = nil
            Task { @MainActor in
                await presentMailto(shareTextBuilder.build(from: payload))
            }
        } catch {
            validationMessage = "请先填写反馈内容"
        }
    }

    @MainActor
    private func presentMailto(_ text: String) async {
        sendState = .sending
        guard let url = FeedbackDestination.mailtoURL(prefilledBody: text) else {
            sendState = .failed("无法生成邮件链接")
            return
        }
        let accepted = await FeedbackMailOpener.open(url: url)
        // 两种 accepted=false 场景：设备没装邮件 app / 装但未配账户。`open(mailto:)`
        // 对两者都返回 false，文案上给出唯一可执行的引导（去系统设置查看账户/添加 app）。
        sendState = accepted ? .sent : .failed("无法唤起邮件 app，请检查系统邮件账户或 App Store 安装")
    }
}

enum FeedbackSendState: Equatable {
    case idle
    case sending
    case sent
    case failed(String)
}

private struct AboutBeforeShowView: View {
    var body: some View {
        BSStageScaffold(title: "关于开场前", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
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
        }
    }
}
