import SwiftData
import SwiftUI
import UIKit

// MARK: - Settings View

struct SettingsView: View {
    /// 不再自带 NavigationStack:设置已迁入首页溢出菜单,
    /// 始终由外层(首页 / 我的现场)的导航栈 push,避免嵌套导航容器。
    var body: some View {
        BSStageScaffold(title: "设置", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
            NavigationLink {
                ProMembershipView()
            } label: {
                SettingsProMembershipCard {
                    SettingsRowContent(
                        iconName: "crown.fill",
                        title: "Pro 会员",
                        subtitle: "重复生成与无限保存现场",
                        value: nil,
                        tint: BSColor.Accent.warm,
                        titleUsesGradient: true
                    )
                }
            }
            .buttonStyle(.plain)

            SettingsGroup(title: "隐私与支持") {
                NotificationSettingsRow()

                Divider().overlay(BSColor.border)

                NavigationLink {
                    PrivacyLocalDataView()
                } label: {
                    SettingsRowContent(iconName: "lock.fill", title: SettingsEntry.privacyAndLocalData.rawValue, subtitle: nil, value: nil, tint: BSColor.Accent.info)
                }
                .buttonStyle(.plain)

                Divider().overlay(BSColor.border)

                NavigationLink {
                    FeedbackView()
                } label: {
                    SettingsRowContent(iconName: "bubble.left.and.bubble.right.fill", title: SettingsEntry.feedback.rawValue, subtitle: nil, value: nil, tint: BSColor.Accent.violet)
                }
                .buttonStyle(.plain)
            }

            SettingsGroup(title: "关于") {
                NavigationLink {
                    AboutBeforeShowView()
                } label: {
                    SettingsRowContent(iconName: "info.circle.fill", title: SettingsEntry.about.rawValue, subtitle: nil, value: "v2.1", tint: BSColor.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text("开场之前，先进入状态")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .frame(maxWidth: .infinity)

            #if DEBUG
            SettingsGroup(title: "调试") {
                ProEntitlementDebugPicker()

                Divider().overlay(BSColor.border)

                DebugPrintPendingNotificationsRow()
            }
            #endif
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
                .font(BSFont.body.weight(.semibold))
                .foregroundColor(BSColor.textPrimary)
            Text("切换后立即生效，仅调试构建可见。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)

            Picker("Pro 状态", selection: Binding(get: { selectedOption }, set: { selectedOption = $0 })) {
                ForEach(DebugProEntitlementOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, 14)
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
                    .foregroundColor(BSColor.Accent.prepare)
                    .frame(width: 34, height: 34)
                    .background(BSColor.Accent.prepare.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text("打印待发通知")
                        .font(BSFont.body.weight(.semibold))
                        .foregroundColor(BSColor.textPrimary)
                    Text("输出当前现场已排程的本地通知到控制台")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                }

                Spacer()

                if isPrinting {
                    ProgressView()
                }
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
#endif

private struct SettingsProMembershipCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        BSColor.Accent.violet.opacity(0.12),
                        BSColor.Accent.warm.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.lg)
                    .stroke(BSColor.borderProminent, lineWidth: 1)
            )
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        BSGlassPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                BSSectionHeader(title: title)
                    .padding(.horizontal, BSSpacing.md)
                    .padding(.top, 14)
                    .padding(.bottom, BSSpacing.xs)
                content
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
    var titleUsesGradient = false

    var body: some View {
        HStack(spacing: BSSpacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(title)
                    .font(BSFont.body.weight(.semibold))
                    .foregroundStyle(titleUsesGradient ? AnyShapeStyle(BSColor.brandGradient) : AnyShapeStyle(BSColor.textPrimary))
                if let subtitle {
                    Text(subtitle)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                }
            }

            Spacer()

            if let value {
                Text(value)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
        }
        .padding(.horizontal, BSSpacing.md)
        .padding(.vertical, 14)
    }
}

/// Notification permission status + jump to system settings when not enabled.
private struct NotificationSettingsRow: View {
    @State private var authorizationState: NotificationAuthorizationState = .notDetermined

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            SettingsRowContent(
                iconName: "bell.fill",
                title: "通知",
                subtitle: subtitle,
                value: nil,
                tint: BSColor.Accent.prepare
            )
        }
        .buttonStyle(.plain)
        .task {
            authorizationState = await LocalNotificationCenter.shared.authorizationState()
        }
    }

    private var subtitle: String {
        switch authorizationState {
        case .authorized, .provisional:
            return "已开启"
        case .denied:
            return "去系统设置开启通知"
        case .notDetermined:
            return "添加现场后会请求开启"
        }
    }
}

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
        BSStageScaffold(title: "Pro 会员", subtitle: "无限保存现场，重复生成准备内容", bottomPadding: BSLayout.tabBarContentInset) {
            BSGlassPanel {
                Text(statusText)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BSGlassPanel {
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
        BSGlassPanel {
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

            BSGlassPanel {
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
                .buttonStyle(BSSecondaryButtonStyle())
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
                }
            }
        }
        .sheet(isPresented: $showsClearConfirmation) {
            BSDangerConfirmationSheet(
                title: "清除本地数据",
                message: "这会删除 BeforeShow 管理的本地记录和副本，且无法恢复；系统相册原图不会删除。",
                destructiveTitle: "清除",
                onConfirm: {
                    showsClearConfirmation = false
                    clearLocalData()
                },
                onCancel: {
                    showsClearConfirmation = false
                }
            )
        }
    }

    private func clearLocalData() {
        isClearing = true
        Task { @MainActor in
            do {
                let context = modelContext
                await ShowAssetMediaStore.shared.acquireCommitGate()
                do {
                    try context.delete(model: Show.self)
                    try context.delete(model: CurrentShowSelection.self)
                    try context.delete(model: NotificationSchedulingState.self)
                    try context.delete(model: ShowNotificationScheduleRecord.self)
                    try context.delete(model: MemoryMediaItem.self)
                    try context.delete(model: MemoryFragment.self)
                    try context.delete(model: ShowAsset.self)
                    try context.save()
                    try await MemoryFragmentMediaStore.shared.deleteAll()
                    try await ShowAssetMediaStore.shared.deleteAll()
                    await ShowAssetMediaStore.shared.releaseCommitGate()
                } catch {
                    context.rollback()
                    await ShowAssetMediaStore.shared.releaseCommitGate()
                    throw error
                }
                clearResult = try await clearer.clearAppOwnedLocalData()
            } catch {
                clearResult = nil
            }
            isClearing = false
        }
    }
}

private struct FeedbackView: View {
    @State private var category: FeedbackCategory = .product
    @State private var message = ""
    @State private var includesDiagnostics = false
    @State private var submissionStateText: String?

    private let payloadBuilder = FeedbackPayloadBuilder()
    private let submitter = LocalFeedbackSubmitter()

    var body: some View {
        BSStageScaffold(title: "意见反馈", subtitle: "告诉我哪里不顺手，或哪里值得保留", bottomPadding: BSLayout.tabBarContentInset) {
            BSGlassPanel {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    Picker("类型", selection: $category) {
                        ForEach(FeedbackCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextEditor(text: $message)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .bsInputField()

                    Toggle("附上 App 版本与系统版本", isOn: $includesDiagnostics)
                        .tint(BSColor.Accent.violet)
                        .foregroundColor(BSColor.textSecondary)
                        .font(BSFont.caption)

                    Text("不会自动包含现场内容、截图、照片、视频、语音或生成结果。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("发送反馈") {
                submitFeedback()
            }
            .buttonStyle(BSPrimaryButtonStyle())

            if let submissionStateText {
                Text(submissionStateText)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
            }
        }
    }

    private func submitFeedback() {
        Task { @MainActor in
            do {
                let payload = try payloadBuilder.build(from: FeedbackDraft(
                    category: category,
                    message: message,
                    includesDiagnostics: includesDiagnostics
                ))
                try await submitter.submit(payload)
                submissionStateText = "已保存待发送的最小反馈内容"
                message = ""
            } catch {
                submissionStateText = "请先填写反馈内容"
            }
        }
    }
}

private struct AboutBeforeShowView: View {
    var body: some View {
        BSStageScaffold(title: "关于开场前", subtitle: nil, bottomPadding: BSLayout.tabBarContentInset) {
            BSGlassPanel {
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

                    Text("版本 2.1")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
