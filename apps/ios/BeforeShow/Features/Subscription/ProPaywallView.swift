import PostHog
import SwiftUI

struct ProPaywallView: View {
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var products = ProSubscriptionCatalog.defaultProducts
    @State private var isLoadingProducts = false
    @State private var productsLoadFailed = false
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
                            noteText(BSLocalization.text("Pro 已过期，已有本地内容仍可查看和编辑。"))
                        }
                        benefitCard
                        planCards
                        ctaButton
                        if productsLoadFailed {
                            Button {
                                Task {
                                    await loadProducts()
                                }
                            } label: {
                                Text(BSLocalization.text("重试"))
                                    .font(.system(size: 11))
                                    .foregroundColor(BSColor.Stage.accent)
                            }
                        }
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
                    accessibilityLabel: BSLocalization.text("关闭"),
                    action: handleClose
                )
                .padding(.trailing, 18)
                .padding(.top, BSSpacing.sm)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            PostHogSDK.shared.capture("pro_paywall_viewed")
            await loadProducts()
        }
        .sheet(item: $legalPage) { page in
            BSInAppBrowser(page: page)
        }
        .sheet(
            isPresented: Binding(
                get: { showsWinback && !entitlement.isProActive },
                set: { showsWinback = $0 }
            ),
            onDismiss: {
                // 下拉收起挽留只是回到 paywall；点「暂时不要」或购买成功才连带关闭。
                if winbackDeclined || didPurchase {
                    onRequestDismiss?()
                }
            }
        ) {
            BSDrawerSheet(detent: .height(430), fitsContent: true) {
                winbackContent
            }
        }
    }

    // MARK: - Presentation sections

    private var background: some View {
        ProPaywallBackground()
    }

    private var hero: some View {
        ProPaywallHero(showsCloseButton: showsCloseButton)
    }

    private var benefitCard: some View {
        ProPaywallBenefitCard()
    }

    private var planCards: some View {
        ProPaywallPlanSelectionView(
            plans: ProSubscriptionCatalog.standardPlans,
            selectedPlan: selectedPlan,
            product: product(for:),
            priceAmount: priceAmount(for:),
            onSelect: { selectedPlan = $0 }
        )
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
        .disabled(purchasingProductID != nil || product(for: selectedPlan)?.isAvailable != true)
    }

    private var ctaTitle: String {
        guard let product = product(for: selectedPlan), product.isAvailable else {
            return BSLocalization.text("价格暂不可用")
        }
        return ProPaywallCopy.ctaTitle(selectedPlan, product: product, price: ctaPrice(for: selectedPlan))
    }

    /// CTA 上的紧凑价格：金额 + 紧凑周期（/年；买断档不带周期）。
    /// store 的 displayPrice 不含周期，这里由方案补上。
    private func ctaPrice(for plan: ProSubscriptionPlan) -> String {
        let amount = priceAmount(for: plan)
        switch plan {
        case .yearly, .yearlyDiscount:
            return BSLocalization.format("%@/年", amount)
        case .lifetime, .lifetimeDiscount:
            return amount
        }
    }

    private var ctaNoteText: String {
        ProPaywallCopy.ctaNote(
            selectedPlan,
            product: product(for: selectedPlan),
            priceAmount: priceAmount(for: selectedPlan)
        )
    }

    private var ctaNote: some View {
        Text(ctaNoteText)
            .font(.system(size: 10.5))
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .foregroundColor(BSColor.Stage.dim)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 7)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var activeCard: some View {
        ProPaywallActiveCard()
    }

    private func noteText(_ text: String) -> some View {
        ProPaywallNote(text: text)
    }

    private var linksRow: some View {
        ProPaywallLinksRow(
            isDisabled: purchasingProductID != nil,
            onRestore: {
                Task {
                    await restore()
                }
            },
            onPrivacy: {
                legalPage = BSInAppBrowserPage(url: localizedSiteURL(ProPaywallCopy.privacyURL))
            },
            onTerms: {
                legalPage = BSInAppBrowserPage(url: localizedSiteURL(ProPaywallCopy.termsURL))
            }
        )
    }

    // MARK: - Winback presentation

    private var winbackContent: some View {
        ProPaywallWinbackView(
            selectedPlan: selectedWinbackPlan,
            purchasingProductID: purchasingProductID,
            product: product(for:),
            priceAmount: priceAmount(for:),
            standardPriceAmount: standardPriceAmount(for:),
            ctaPrice: ctaPrice(for:),
            onSelect: { selectedWinbackPlan = $0 },
            onPurchase: { plan in
                Task {
                    await purchase(plan)
                }
            },
            onDecline: {
                winbackDeclined = true
                showsWinback = false
            }
        )
    }

    // MARK: - 数据与行为

    private var entitlement: ProEntitlementState {
        ProEntitlementStorage.decode(entitlementRawValue)
    }

    private func product(for plan: ProSubscriptionPlan) -> ProSubscriptionProduct? {
        products.first { $0.plan == plan }
    }

    /// 价格字符串只保留金额部分（去掉「/年」后缀），周期由方案推导，
    /// 这样 store 的 displayPrice（不含周期）和 fallback 文案都能用。
    /// 未从 store 拿到的方案只显示「价格暂不可用」，不展示 catalog USD 参考价。
    private func priceAmount(for plan: ProSubscriptionPlan) -> String {
        guard let product = product(for: plan), product.isAvailable else {
            return BSLocalization.text("价格暂不可用")
        }
        let priceText = product.priceText
        return priceText.components(separatedBy: "/").first ?? priceText
    }

    /// 挽留价对应的标准价划线金额：特惠年度 → 年度，特惠终身 → 终身。
    private func standardPriceAmount(for winbackPlan: ProSubscriptionPlan) -> String {
        let standardPlan: ProSubscriptionPlan = winbackPlan == .yearlyDiscount ? .yearly : .lifetime
        guard product(for: standardPlan)?.isAvailable == true else { return "" }
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

        productsLoadFailed = false
        do {
            let loadedProducts = try await store.loadProducts()
            guard !loadedProducts.isEmpty else {
                productsLoadFailed = true
                message = BSLocalization.text("暂时无法加载 App Store 价格。")
                return
            }
            // 只保留 store 实际返回的方案；缺失方案仍用 catalog 占位，
            // 但 isAvailable == false，UI 显示「价格暂不可用」并禁用 CTA，
            // 不会用自定义 USD 参考价冒充真实 App Store 价格。
            products = ProSubscriptionCatalog.defaultProducts.map { fallback in
                loadedProducts.first { $0.plan == fallback.plan } ?? fallback
            }
        } catch {
            productsLoadFailed = true
            message = BSLocalization.text("暂时无法加载 App Store 价格。")
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
            PostHogSDK.shared.capture("pro_purchase_completed", properties: [
                "plan": plan.rawValue
            ])
            didPurchase = true
            message = BSLocalization.text("Pro 已启用。")
            withAnimation(.easeOut(duration: BSMotion.interface)) {
                showsWinback = false
            }
        } catch ProSubscriptionError.purchaseCancelled {
            message = nil
        } catch ProSubscriptionError.winbackNotAvailableWhileActive {
            // 模型层拒绝：当前已是 Pro，挽留方案会与已有订阅重叠，直接关闭挽留态。
            showsWinback = false
            message = BSLocalization.text("当前已是 Pro，挽留方案不适用。")
        } catch {
            PostHogSDK.shared.capture("pro_purchase_failed", properties: [
                "plan": plan.rawValue
            ])
            message = BSLocalization.text("购买暂时没有完成。")
        }
    }

    @MainActor
    private func restore() async {
        purchasingProductID = "restore"
        defer { purchasingProductID = nil }

        do {
            let entitlement = try await store.restorePurchases()
            entitlementRawValue = ProEntitlementStorage.encode(entitlement)
            PostHogSDK.shared.capture("pro_restored")
            didPurchase = true
            message = BSLocalization.text("已恢复 Pro。")
        } catch ProSubscriptionError.nothingToRestore {
            message = BSLocalization.text("没有找到可恢复的 Pro。")
        } catch {
            message = BSLocalization.text("恢复购买暂时没有完成。")
        }
    }

    static func defaultStore() -> any ProSubscriptionStore {
        ProPaywallStoreFactory.makeDefault()
    }
}

