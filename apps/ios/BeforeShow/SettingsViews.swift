import SwiftData
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("defaultMusicPlatform") private var defaultMusicPlatformName = SettingsInformation.defaultMusicPlatformName

    var body: some View {
        NavigationStack {
            BSStageScaffold(title: "设置", subtitle: nil, bottomPadding: BSLayout.floatingTabBarClearance) {
                NavigationLink {
                    ProMembershipView()
                } label: {
                    SettingsProMembershipCard {
                        SettingsRowContent(
                            iconName: "crown.fill",
                            title: "Pro 会员",
                            subtitle: "重复生成与无限保存现场",
                            value: nil,
                            tint: BSColor.Accent.music,
                            titleUsesGradient: true
                        )
                    }
                }
                .buttonStyle(.plain)

                SettingsGroup(title: "基础") {
                    Divider().overlay(BSColor.border)

                    NavigationLink {
                        MusicPlatformSettingsView(selectedPlatformName: $defaultMusicPlatformName)
                    } label: {
                        SettingsRowContent(
                            iconName: "music.note",
                            title: SettingsEntry.defaultMusicPlatform.rawValue,
                            subtitle: nil,
                            value: defaultMusicPlatformName,
                            tint: BSColor.Accent.music
                        )
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroup(title: "隐私与支持") {
                    NavigationLink {
                        PrivacyLocalDataView()
                    } label: {
                        SettingsRowContent(iconName: "lock.fill", title: SettingsEntry.privacyAndLocalData.rawValue, subtitle: nil, value: nil, tint: BSColor.Accent.travel)
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(BSColor.border)

                    NavigationLink {
                        FeedbackView()
                    } label: {
                        SettingsRowContent(iconName: "bubble.left.and.bubble.right.fill", title: SettingsEntry.feedback.rawValue, subtitle: nil, value: nil, tint: BSColor.Accent.video)
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
                }
                #endif
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
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
#endif

private struct SettingsProMembershipCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        BSColor.Accent.video.opacity(0.12),
                        BSColor.Accent.music.opacity(0.08)
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
        BSStageScaffold(title: "Pro 会员", subtitle: "无限保存现场，重复生成准备内容") {
            BSGlassPanel {
                Text(statusText)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            return "Pro 已启用，可以继续添加现场和重复生成。"
        case .expired:
            return "Pro 已过期，已有本地内容仍可查看和编辑。"
        case .free:
            return "当前为免费版：可保存 1 场现场，并首次生成候选曲目。"
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

private struct MusicPlatformSettingsView: View {
    @Binding var selectedPlatformName: String

    var body: some View {
        BSStageScaffold(title: "默认音乐平台", subtitle: "候选曲目会把搜索交给你选择的平台") {
            ForEach(SettingsInformation.musicPlatformNames, id: \.self) { platformName in
                Button {
                    selectedPlatformName = platformName
                } label: {
                    HStack(spacing: BSSpacing.md) {
                        Image(systemName: "music.note")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BSColor.Accent.music)
                            .frame(width: 34, height: 34)
                            .background(BSColor.Accent.music.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text(platformName)
                            .font(BSFont.body.weight(.semibold))
                            .foregroundColor(BSColor.textPrimary)

                        Spacer()

                        if selectedPlatformName == platformName {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(BSColor.Accent.prepare)
                        }
                    }
                    .padding(BSSpacing.md)
                    .background(Color.white.opacity(selectedPlatformName == platformName ? 0.07 : 0.045))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.lg)
                            .stroke(selectedPlatformName == platformName ? BSColor.Accent.prepare.opacity(0.34) : BSColor.borderProminent, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
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
        BSStageScaffold(title: "隐私与本地数据", subtitle: "只保留 BeforeShow 需要的本机内容") {
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
                message: "这会删除所有现场、碎片、计划和本地设置，且无法恢复。",
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
                let service = LocalAppDataDeletionService(
                    audioStorage: .applicationSupport()
                )
                try service.clearLocalAppData(in: modelContext)
                try modelContext.save()
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
        BSStageScaffold(title: "意见反馈", subtitle: "告诉我哪里不顺手，或哪里值得保留") {
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
                        .tint(BSColor.Accent.video)
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
        BSStageScaffold(title: "关于开场前", subtitle: nil) {
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
