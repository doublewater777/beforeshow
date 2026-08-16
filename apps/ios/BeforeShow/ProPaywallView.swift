import SwiftUI

/// V2 Paywall：标准三档（月度 $1.49 / 年度 $4.99 / 终身 $8.99）+ 挽留双档
///（特惠年度 $2.99 / 特惠终身 $5.99）。布局以参考稿
/// beforeshow-settings-paywall-v2-winback.html 为准：居中 hero + 横向并排方案卡。
///
/// sheet 形态（设置 / 限额 / 长按图标 deep link）：`ProPaywallSheetView`，
/// 关闭且未购买时每次弹一次挽留卡片；`initiallyShowsWinback: true` 直接进入挽留态。
struct ProPaywallView: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var products = ProSubscriptionCatalog.defaultProducts
    @State private var isLoadingProducts = false
    @State private var purchasingProductID: String?
    @State private var message: String?
    @State private var selectedPlan: ProSubscriptionPlan = .yearly
    @State private var selectedWinbackPlan: ProSubscriptionPlan = .yearlyDiscount
    @State private var showsWinback: Bool
    @State private var didPurchase = false
    /// 点「暂时不要」置 true：挽留 sheet 关闭时连带关闭 paywall；下拉收起则保留 paywall。
    @State private var winbackDeclined = false
    @State private var legalPage: BSInAppBrowserPage?

    private let store: any ProSubscriptionStore
    private let showsCloseButton: Bool
    /// sheet 场景下的关闭回调；nil 表示无关闭入口（挽留逻辑不启用）。
    private let onRequestDismiss: (() -> Void)?

    init(
        store: any ProSubscriptionStore = ProPaywallView.defaultStore(),
        showsCloseButton: Bool = false,
        initiallyShowsWinback: Bool = false,
        onRequestDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.showsCloseButton = showsCloseButton
        self.onRequestDismiss = onRequestDismiss
        _showsWinback = State(initialValue: initiallyShowsWinback)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background

            ScrollView {
                VStack(spacing: BSSpacing.md) {
                    hero

                    if entitlement.isProActive {
                        activeCard
                    } else {
                        if case .expired = entitlement {
                            noteText("Pro 已过期，已有本地内容仍可查看和编辑。")
                        }
                        benefitCard
                        planCards
                        ctaButton
                        ctaNote
                    }

                    if let message {
                        noteText(message)
                    }

                    linksRow
                }
                .padding(.horizontal, 20)
                .padding(.top, showsCloseButton ? 8 : BSSpacing.lg)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)

            if showsCloseButton {
                BSChromeIconButton(
                    systemName: "xmark",
                    accessibilityLabel: "关闭",
                    action: handleClose
                )
                .padding(.trailing, 18)
                .padding(.top, BSSpacing.sm)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProducts()
        }
        .sheet(item: $legalPage) { page in
            BSInAppBrowser(page: page)
        }
        .sheet(isPresented: $showsWinback, onDismiss: {
            // 下拉收起挽留只是回到 paywall；点「暂时不要」或购买成功才连带关闭。
            if winbackDeclined || didPurchase {
                onRequestDismiss?()
            }
        }) {
            BSDrawerSheet(detent: .height(430), fitsContent: true) {
                winbackContent
            }
        }
    }

    // MARK: - 背景与 Hero（居中，参考稿 .pw-head）

    private var background: some View {
        ZStack {
            CurrentShowStageBackground()
            RadialGradient(
                colors: [BSColor.Stage.accent.opacity(0.13), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 280
            )
            RadialGradient(
                colors: [BSColor.Stage.glowBlue.opacity(0.09), .clear],
                center: UnitPoint(x: 0.02, y: 0.14),
                startRadius: 0,
                endRadius: 240
            )
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BSColor.Stage.accent.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 52
                        )
                    )
                    .frame(width: 104, height: 104)
                    .blur(radius: 4)
                Image(systemName: "sparkle")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
            }
            .frame(width: 67, height: 67)
            .padding(.bottom, 18)

            Text("BEFORESHOW PRO")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.7)
                .foregroundColor(BSColor.Stage.accent)
                .padding(.bottom, 9)

            Text("把下一场，\n也留下来")
                .font(.system(size: 29, weight: .bold))
                .kerning(-0.7)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundColor(BSColor.Stage.foreground)

            Text(ProPaywallCopy.summary)
                .font(.system(size: 13))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundColor(BSColor.Stage.muted)
                .frame(maxWidth: 310)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, showsCloseButton ? 44 : BSSpacing.md)
    }

    // MARK: - 权益卡

    private var benefitCard: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 24, height: 24)
                .background(BSColor.Stage.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("无限添加现场")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text("未来的每一场，都可以继续进入「当前」并最终留进「足迹」。")
                    .font(.system(size: 11.8))
                    .lineSpacing(2)
                    .foregroundColor(BSColor.Stage.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Stage.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(
            RoundedRectangle(cornerRadius: 19)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    // MARK: - 方案卡（横向并排，参考稿 .plans）

    private var planCards: some View {
        HStack(spacing: 10) {
            ForEach(ProSubscriptionCatalog.standardPlans, id: \.self) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: ProSubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(ProPaywallCopy.planName(plan))
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.bottom, 9)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(priceAmount(for: plan))
                        .font(.system(size: 21, weight: .semibold))
                        .kerning(-0.4)
                        .foregroundColor(BSColor.Stage.foreground)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(ProPaywallCopy.periodLabel(plan))
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                }

                Text(ProPaywallCopy.planNote(plan))
                    .font(.system(size: 10.5))
                    .foregroundColor(BSColor.Stage.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 15)
            .frame(minHeight: 109, alignment: .topLeading)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient(
                        colors: [
                            BSColor.Stage.accent.opacity(0.10),
                            BSColor.Stage.accent.opacity(0.035)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    : AnyShapeStyle(Color.white.opacity(0.035))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isSelected ? BSColor.Stage.accent.opacity(0.48) : BSColor.Stage.border,
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if plan == .yearly {
                    Text("推荐")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(BSColor.Stage.accent.opacity(0.13))
                        .clipShape(Capsule())
                        .padding(9)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA 与说明

    private var ctaButton: some View {
        Button {
            Task {
                await purchase(selectedPlan)
            }
        } label: {
            HStack {
                if let productID = product(for: selectedPlan)?.id, purchasingProductID == productID {
                    ProgressView()
                        .tint(.black)
                }
                Text(ctaTitle)
            }
        }
        .buttonStyle(BSPrimaryButtonStyle())
        .disabled(purchasingProductID != nil)
    }

    private var ctaTitle: String {
        let price = ctaPrice(for: selectedPlan)
        switch selectedPlan {
        case .monthly:
            return "订阅月度 Pro · \(price)"
        case .yearly:
            return "订阅年度 Pro · \(price)"
        case .lifetime:
            return "买断终身 Pro · \(price)"
        case .yearlyDiscount, .lifetimeDiscount:
            return "以特惠价解锁 Pro · \(price)"
        }
    }

    /// CTA 上的紧凑价格：金额 + 紧凑周期（/月、/年；买断档不带周期）。
    /// StoreKit 的 displayPrice 不含周期，这里由方案补上。
    private func ctaPrice(for plan: ProSubscriptionPlan) -> String {
        let amount = priceAmount(for: plan)
        switch plan {
        case .monthly:
            return "\(amount)/月"
        case .yearly, .yearlyDiscount:
            return "\(amount)/年"
        case .lifetime, .lifetimeDiscount:
            return amount
        }
    }

    private var ctaNote: some View {
        Text(selectedPlan.isLifetime
             ? "一次性购买，永久有效。不升级 Pro，已有现场也仍可查看和编辑。"
             : "订阅将通过 App Store 自动续订，直到取消。已有现场即使 Pro 到期，也仍可查看和编辑。")
            .font(.system(size: 10.5))
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .foregroundColor(BSColor.Stage.dim)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 7)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var activeCard: some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(BSColor.brandGradient)
            Text("Pro 已启用，可以继续添加现场。")
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.foreground)
        }
        .padding(BSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(
            RoundedRectangle(cornerRadius: 19)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .multilineTextAlignment(.center)
            .foregroundColor(BSColor.Stage.dim)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 底部链接（参考稿 .links）

    private var linksRow: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            linkButton("恢复购买") {
                Task {
                    await restore()
                }
            }
            linkButton("隐私政策") {
                legalPage = BSInAppBrowserPage(url: localizedSiteURL(ProPaywallCopy.privacyURL))
            }
            linkButton("使用条款") {
                legalPage = BSInAppBrowserPage(url: localizedSiteURL(ProPaywallCopy.termsURL))
            }
            Spacer(minLength: 0)
        }
        .disabled(purchasingProductID != nil)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11))
            .foregroundColor(BSColor.Stage.muted)
    }

    // MARK: - 挽留内容（标准抽屉 sheet：手柄 + 系统 glass）

    private var winbackContent: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            Text("限时优惠 · 最高 40% OFF")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(BSColor.Stage.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(BSColor.Stage.accent.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(BSColor.Stage.accent.opacity(0.28), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                Text("再想一下？")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text("以特惠价升级，错过恢复原价；免费版仍可完整保存 20 场现场。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                winbackDealCard(.yearlyDiscount)
                winbackDealCard(.lifetimeDiscount)
            }

            Button {
                Task {
                    await purchase(selectedWinbackPlan)
                }
            } label: {
                HStack {
                    if let productID = product(for: selectedWinbackPlan)?.id, purchasingProductID == productID {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(ctaTitleForWinback)
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(purchasingProductID != nil)

            Button("暂时不要") {
                winbackDeclined = true
                showsWinback = false
            }
            .font(BSFont.caption)
            .foregroundColor(BSColor.Stage.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BSSpacing.sm)
        }
    }

    /// 挽留选项卡：内容竖排（名称在上、价格在下），与标准方案卡同一语言。
    private func winbackDealCard(_ plan: ProSubscriptionPlan) -> some View {
        let isSelected = selectedWinbackPlan == plan
        return Button {
            selectedWinbackPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(ProPaywallCopy.planName(plan))
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.bottom, 7)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(priceAmount(for: plan))
                        .font(.system(size: 21, weight: .semibold))
                        .kerning(-0.4)
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(ProPaywallCopy.periodLabel(plan))
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                    Text(standardPriceAmount(for: plan))
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                        .strikethrough()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient(
                        colors: [
                            BSColor.Stage.accent.opacity(0.10),
                            BSColor.Stage.accent.opacity(0.035)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    : AnyShapeStyle(BSColor.Stage.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(
                        isSelected ? BSColor.Stage.accent.opacity(0.48) : BSColor.Stage.border,
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                Text(ProPaywallCopy.winbackSaveLabel(plan))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(BSColor.Stage.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(BSColor.Stage.accent.opacity(0.13))
                    .clipShape(Capsule())
                    .padding(9)
            }
        }
        .buttonStyle(.plain)
    }

    private var ctaTitleForWinback: String {
        "以特惠价解锁 Pro · \(ctaPrice(for: selectedWinbackPlan))"
    }

    // MARK: - 数据与行为

    private var entitlement: ProEntitlementState {
        ProEntitlementStorage.decode(entitlementRawValue)
    }

    private func product(for plan: ProSubscriptionPlan) -> ProSubscriptionProduct? {
        products.first { $0.plan == plan }
    }

    /// 价格字符串只保留金额部分（去掉「/月」「/年」后缀），周期由方案推导，
    /// 这样 StoreKit 的 displayPrice（不含周期）和 fallback 文案都能用。
    private func priceAmount(for plan: ProSubscriptionPlan) -> String {
        let priceText = product(for: plan)?.priceText ?? ""
        return priceText.components(separatedBy: "/").first ?? priceText
    }

    /// 挽留价对应的标准价划线金额：特惠年度 → 年度，特惠终身 → 终身。
    private func standardPriceAmount(for winbackPlan: ProSubscriptionPlan) -> String {
        let standardPlan: ProSubscriptionPlan = winbackPlan == .yearlyDiscount ? .yearly : .lifetime
        return priceAmount(for: standardPlan)
    }

    private func handleClose() {
        if entitlement.isProActive || didPurchase {
            onRequestDismiss?()
        } else {
            showsWinback = true
        }
    }

    @MainActor
    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await store.loadProducts()
            if !loadedProducts.isEmpty {
                // 按方案逐个覆盖：StoreKit 暂时没返回的档（如新建产品还在传播）
                // 回退到目录参考价，避免方案卡显示空价格。
                products = ProSubscriptionCatalog.defaultProducts.map { fallback in
                    loadedProducts.first { $0.plan == fallback.plan } ?? fallback
                }
            }
        } catch {
            message = "暂时没有加载到 App Store 价格，先显示参考价。"
        }
    }

    @MainActor
    private func purchase(_ plan: ProSubscriptionPlan) async {
        guard let product = product(for: plan) else { return }
        purchasingProductID = product.id
        defer { purchasingProductID = nil }

        do {
            let entitlement = try await store.purchase(productID: product.id)
            entitlementRawValue = ProEntitlementStorage.encode(entitlement)
            didPurchase = true
            message = "Pro 已启用。"
            withAnimation(.easeOut(duration: BSMotion.interface)) {
                showsWinback = false
            }
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
            didPurchase = true
            message = "已恢复 Pro。"
        } catch ProSubscriptionError.nothingToRestore {
            message = "没有找到可恢复的 Pro。"
        } catch {
            message = "恢复购买暂时没有完成。"
        }
    }

    static func defaultStore() -> any ProSubscriptionStore {
        #if canImport(StoreKit)
        return StoreKitProSubscriptionStore()
        #else
        return MockProSubscriptionStore()
        #endif
    }
}

// MARK: - Sheet 形态（设置 / 限额 / 长按图标入口）

struct ProPaywallSheetView: View {
    @Environment(\.dismiss) private var dismiss

    private let store: any ProSubscriptionStore
    private let initiallyShowsWinback: Bool

    init(
        initiallyShowsWinback: Bool = false,
        store: any ProSubscriptionStore = ProPaywallView.defaultStore()
    ) {
        self.initiallyShowsWinback = initiallyShowsWinback
        self.store = store
    }

    var body: some View {
        ProPaywallView(
            store: store,
            showsCloseButton: true,
            initiallyShowsWinback: initiallyShowsWinback,
            onRequestDismiss: { dismiss() }
        )
    }
}

// MARK: - 文案

enum ProPaywallCopy {
    static let summary = "免费版可以完整保存 20 场现场。Pro 让你的足迹继续累积，不限制新增场次。"

    static let privacyURL = URL(string: "https://beforeshow.doublewaterapps.com/privacy")!
    static let termsURL = URL(string: "https://beforeshow.doublewaterapps.com/terms")!

    static func planName(_ plan: ProSubscriptionPlan) -> String {
        switch plan {
        case .monthly: return "月度"
        case .yearly: return "年度"
        case .lifetime: return "终身"
        case .yearlyDiscount: return "特惠年度"
        case .lifetimeDiscount: return "特惠终身"
        }
    }

    static func periodLabel(_ plan: ProSubscriptionPlan) -> String {
        switch plan {
        case .monthly: return "/ 月"
        case .yearly, .yearlyDiscount: return "/ 年"
        case .lifetime, .lifetimeDiscount: return "一次性"
        }
    }

    static func planNote(_ plan: ProSubscriptionPlan) -> String {
        switch plan {
        case .monthly: return "按月续订，可随时取消"
        case .yearly: return "约 $0.42 / 月"
        case .lifetime: return "一次买断，永久有效"
        case .yearlyDiscount, .lifetimeDiscount: return ""
        }
    }

    static func winbackSaveLabel(_ plan: ProSubscriptionPlan) -> String {
        switch plan {
        case .yearlyDiscount: return "省 40%"
        case .lifetimeDiscount: return "省 33%"
        default: return ""
        }
    }
}
