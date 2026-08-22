import PostHog
import SwiftUI

/// V2 Paywall：标准双档（年度 $4.99 / 终身 $8.99）+ 挽留双档
///（特惠年度 $2.99 / 特惠终身 $5.99）。布局以参考稿
/// beforeshow-settings-paywall-v2-winback.html 为准：居中 hero + 横向并排方案卡。
///
/// sheet 形态（设置 / 限额 / 长按图标 deep link）：`ProPaywallSheetView`，
/// 关闭且未购买时每次弹一次挽留卡片；`initiallyShowsWinback: true` 直接进入挽留态。
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
            ZStack(alignment: .bottom) {
                heroBeams

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
            }
            .frame(height: 150)
            .padding(.bottom, 18)

            Text("BEFORESHOW PRO")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.7)
                .foregroundColor(BSColor.Stage.accent)
                .padding(.bottom, 9)

            Text(BSLocalization.text("把下一场，\n也留下来"))
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
        .padding(.top, showsCloseButton ? 34 : BSSpacing.md)
    }

    /// 顶部静态光束:蓝/金/紫三个光锥从星标处向上散开,呼应「灯亮」时刻,
    /// 同时填掉原本空旷的头部。静态(无动画),与熄灯仪式的光束同一语言。
    private var heroBeams: some View {
        ZStack(alignment: .bottom) {
            heroBeam(color: BSColor.Stage.glowBlue, topWidth: 150, rotation: 30, opacity: 0.75)
            heroBeam(color: BSColor.Stage.accent, topWidth: 150, rotation: -30, opacity: 0.70)
            heroBeam(color: BSColor.Accent.violet, topWidth: 110, rotation: 0, opacity: 0.50)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 单个光锥:顶点在下的三角,自下而上淡出,绕顶点旋转后左右展开。
    private func heroBeam(color: Color, topWidth: CGFloat, rotation: Double, opacity: Double) -> some View {
        PaywallBeamShape()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.85), color.opacity(0.28), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: topWidth, height: 190)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .blur(radius: 7)
            .opacity(opacity)
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
                Text(BSLocalization.text("无限添加现场"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("未来的每一场，都可以继续进入「当前」并最终留进「足迹」。"))
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
        // 给骑在年度卡上边框的推荐徽章留出伸出空间
        .padding(.top, 8)
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

                Text(ProPaywallCopy.planNote(plan, product: product(for: plan)))
                    .font(.system(size: 10.5))
                    .foregroundColor(BSColor.Stage.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 15)
            .frame(minHeight: 109, maxHeight: .infinity, alignment: .topLeading)
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
            .overlay(alignment: .top) {
                // 推荐徽章骑在卡片上边框:不占卡内空间,终身卡顶部不再留空行。
                if plan == .yearly {
                    Text(BSLocalization.text("推荐"))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(BSColor.Stage.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(BSColor.Stage.accent.opacity(0.35), lineWidth: 1)
                        )
                        .offset(y: -9)
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
        .disabled(purchasingProductID != nil || product(for: selectedPlan)?.isAvailable != true)
    }

    private var ctaTitle: String {
        guard product(for: selectedPlan)?.isAvailable == true else {
            return BSLocalization.text("价格暂不可用")
        }
        let price = ctaPrice(for: selectedPlan)
        switch selectedPlan {
        case .yearly:
            return BSLocalization.format("订阅年度 Pro · %@", price)
        case .lifetime:
            return BSLocalization.format("买断终身 Pro · %@", price)
        case .yearlyDiscount, .lifetimeDiscount:
            return BSLocalization.format("以特惠价解锁 Pro · %@", price)
        }
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

    private var ctaNote: some View {
        Text(selectedPlan.isLifetime
             ? BSLocalization.text("一次性购买，永久有效。不升级 Pro，已有现场也仍可查看和编辑。")
             : BSLocalization.text("订阅将通过 App Store 自动续订，直到取消。已有现场即使 Pro 到期，也仍可查看和编辑。"))
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
            Text(BSLocalization.text("Pro 已启用，可以继续添加现场。"))
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
            linkButton(BSLocalization.text("恢复购买")) {
                Task {
                    await restore()
                }
            }
            linkButton(BSLocalization.text("隐私政策")) {
                legalPage = BSInAppBrowserPage(url: localizedSiteURL(ProPaywallCopy.privacyURL))
            }
            linkButton(BSLocalization.text("用户协议")) {
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
            Text(BSLocalization.text("限时优惠 · 最高 40% OFF"))
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
                Text(BSLocalization.text("再想一下？"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("以特惠价升级，错过恢复原价；免费版每月仍可添加 1 场现场。"))
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
            .disabled(purchasingProductID != nil || product(for: selectedWinbackPlan)?.isAvailable != true)

            Button(BSLocalization.text("暂时不要")) {
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
                // 徽章入流:英文「Discounted Annual」很长,悬浮会与之重叠。
                HStack {
                    Spacer(minLength: 0)
                    Text(ProPaywallCopy.winbackSaveLabel(plan))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(BSColor.Stage.accent.opacity(0.13))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 6)

                Text(ProPaywallCopy.planName(plan))
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.bottom, 7)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(priceAmount(for: plan))
                        .font(.system(size: 21, weight: .semibold))
                        .kerning(-0.4)
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(ProPaywallCopy.periodLabel(plan))
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                        .lineLimit(1)
                }

                let originalPrice = standardPriceAmount(for: plan)
                if !originalPrice.isEmpty {
                    Text(originalPrice)
                        .font(.system(size: 10.5))
                        .foregroundColor(BSColor.Stage.dim)
                        .strikethrough()
                        .lineLimit(1)
                        .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        }
        .buttonStyle(.plain)
    }

    private var ctaTitleForWinback: String {
        guard product(for: selectedWinbackPlan)?.isAvailable == true else {
            return BSLocalization.text("价格暂不可用")
        }
        return BSLocalization.format("以特惠价解锁 Pro · %@", ctaPrice(for: selectedWinbackPlan))
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
        // 占位 key（appl_REPLACE_ME）或缺失时回退到 Mock：保证 dashboard 端还没配好
        // key 之前 app 仍能跑，paywall 用 Mock 走通完整流程。
        let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
        if key.isEmpty || key == "appl_REPLACE_ME" {
            #if DEBUG
            print("[Pro] RevenueCatAPIKey missing — falling back to Mock store")
            #endif
            return MockProSubscriptionStore()
        }
        return RevenueCatProSubscriptionStore()
    }
}

// MARK: - Sheet 形态（设置 / 限额 / 长按图标入口）

/// Paywall 顶部的光锥:顶点在下的三角,顶点即光源(星标处)。
private struct PaywallBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

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
    static var summary: String {
        BSLocalization.text("免费版每月可以添加 1 场现场。Pro 让你的足迹继续累积，不限制新增场次。")
    }

    static let privacyURL = URL(string: "https://beforeshow.doublewaterapps.com/privacy")!
    static let termsURL = URL(string: "https://beforeshow.doublewaterapps.com/terms")!

    static func planName(_ plan: ProSubscriptionPlan) -> String {
        switch plan {
        case .yearly: return BSLocalization.text("年度")
        case .lifetime: return BSLocalization.text("终身")
        case .yearlyDiscount: return BSLocalization.text("特惠年度")
        case .lifetimeDiscount: return BSLocalization.text("特惠终身")
        }
    }

    static func periodLabel(_ plan: ProSubscriptionPlan) -> String {
        switch plan {
        case .yearly, .yearlyDiscount: return BSLocalization.text("/ 年")
        case .lifetime, .lifetimeDiscount: return BSLocalization.text("一次性")
        }
    }

    static func planNote(_ plan: ProSubscriptionPlan, product: ProSubscriptionProduct?) -> String {
        switch plan {
        case .yearly:
            guard let perMonth = product?.perMonthEquivalentText else { return "" }
            return BSLocalization.format("约 %@ / 月", perMonth)
        case .lifetime: return BSLocalization.text("一次买断，永久有效")
        case .yearlyDiscount, .lifetimeDiscount: return ""
        }
    }

    static func winbackSaveLabel(_ plan: ProSubscriptionPlan) -> String {
        switch plan {
        case .yearlyDiscount: return BSLocalization.text("省 40%")
        case .lifetimeDiscount: return BSLocalization.text("省 33%")
        default: return ""
        }
    }
}
