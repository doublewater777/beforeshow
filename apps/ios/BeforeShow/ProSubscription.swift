import Foundation
import RevenueCat

@MainActor
final class ProOfferDeepLinkRouter: ObservableObject {
    static let shared = ProOfferDeepLinkRouter()

    @Published var shouldPresentProSheet = false
    @Published var shouldShowWinbackOffer = false

    private init() {}

    func routeToPro(showWinbackOffer: Bool = false) {
        shouldShowWinbackOffer = showWinbackOffer
        shouldPresentProSheet = true
    }
}

enum ProSubscriptionPlan: String, CaseIterable, Equatable {
    case yearly
    case lifetime
    case yearlyDiscount
    case lifetimeDiscount

    /// 终身买断没有续订周期，购买/恢复后也不需要到期日语义。
    var isLifetime: Bool {
        self == .lifetime || self == .lifetimeDiscount
    }

    /// 挽留方案仅在用户从免费 / 过期重新购买时使用，已订阅 Pro 时购买会与已有订阅重叠。
    var isWinback: Bool {
        self == .yearlyDiscount || self == .lifetimeDiscount
    }
}

struct ProSubscriptionProduct: Equatable {
    let id: String
    let plan: ProSubscriptionPlan
    let displayName: String
    let priceText: String
    let benefitCopy: [String]
    /// Store 是否真实返回了该产品。catalog 参考价仅供占位，不可作为生产购买价格。
    let isAvailable: Bool
    /// 年度方案按月折算的文案（如「约 $0.42 / 月」），仅当 store 提供真实价格时有值。
    let perMonthEquivalentText: String?
    /// 免费试用文案（如「3 天免费试用」），仅当 store 提供零价 intro offer 且用户有试用资格时有值。
    let trialText: String?

    init(
        id: String,
        plan: ProSubscriptionPlan,
        displayName: String,
        priceText: String,
        benefitCopy: [String],
        isAvailable: Bool = false,
        perMonthEquivalentText: String? = nil,
        trialText: String? = nil
    ) {
        self.id = id
        self.plan = plan
        self.displayName = displayName
        self.priceText = priceText
        self.benefitCopy = benefitCopy
        self.isAvailable = isAvailable
        self.perMonthEquivalentText = perMonthEquivalentText
        self.trialText = trialText
    }

    func markingAvailable(_ available: Bool = true) -> ProSubscriptionProduct {
        ProSubscriptionProduct(
            id: id,
            plan: plan,
            displayName: displayName,
            priceText: priceText,
            benefitCopy: benefitCopy,
            isAvailable: available,
            perMonthEquivalentText: perMonthEquivalentText,
            trialText: trialText
        )
    }
}

enum ProSubscriptionCatalog {
    static let yearlyProductID = "com.doublewaterapps.beforeshow.pro.yearly"
    static let lifetimeProductID = "com.doublewaterapps.beforeshow.pro.lifetime"
    static let yearlyDiscountProductID = "com.doublewaterapps.beforeshow.pro.yearly.discount"
    static let lifetimeDiscountProductID = "com.doublewaterapps.beforeshow.pro.lifetime.discount"

    /// 标准在售方案：年度 / 终身。
    static let standardPlans: [ProSubscriptionPlan] = [.yearly, .lifetime]
    /// 挽回优惠方案：仅在挽留弹窗与长按图标入口展示。
    static let winbackPlans: [ProSubscriptionPlan] = [.yearlyDiscount, .lifetimeDiscount]

    /// 目录参考价：仅用于 UI 占位（产品 ID / 方案映射），`isAvailable == false`，
    /// 生产环境不会展示这些 USD 价格，也不会据此允许购买。
    static let defaultProducts: [ProSubscriptionProduct] = [
        ProSubscriptionProduct(
            id: yearlyProductID,
            plan: .yearly,
            displayName: BSLocalization.text("BeforeShow Pro 年度"),
            priceText: BSLocalization.text("$4.99/年"),
            benefitCopy: [
                "无限添加现场"
            ]
        ),
        ProSubscriptionProduct(
            id: lifetimeProductID,
            plan: .lifetime,
            displayName: BSLocalization.text("BeforeShow Pro 终身"),
            priceText: BSLocalization.text("$8.99"),
            benefitCopy: [
                "无限添加现场"
            ]
        ),
        ProSubscriptionProduct(
            id: yearlyDiscountProductID,
            plan: .yearlyDiscount,
            displayName: BSLocalization.text("BeforeShow Pro 特惠年度"),
            priceText: BSLocalization.text("$2.99/年"),
            benefitCopy: [
                "无限添加现场"
            ]
        ),
        ProSubscriptionProduct(
            id: lifetimeDiscountProductID,
            plan: .lifetimeDiscount,
            displayName: BSLocalization.text("BeforeShow Pro 特惠终身"),
            priceText: BSLocalization.text("$5.99"),
            benefitCopy: [
                "无限添加现场"
            ]
        )
    ]
}

enum ProEntitlementState: Equatable {
    case free
    case active(productID: String, expirationDate: Date?)
    case expired(productID: String, expirationDate: Date)

    var isProActive: Bool {
        if case .active = self {
            return true
        }

        return false
    }
}

enum ProEntitlementStorage {
    private struct StoredEntitlement: Codable, Equatable {
        var state: String
        var productID: String?
        var expirationDate: Date?
    }

    static let appStorageKey = "proEntitlementState"

    static func encode(_ entitlement: ProEntitlementState) -> String {
        let stored: StoredEntitlement
        switch entitlement {
        case .free:
            stored = StoredEntitlement(state: "free", productID: nil, expirationDate: nil)
        case .active(let productID, let expirationDate):
            stored = StoredEntitlement(state: "active", productID: productID, expirationDate: expirationDate)
        case .expired(let productID, let expirationDate):
            stored = StoredEntitlement(state: "expired", productID: productID, expirationDate: expirationDate)
        }

        guard let data = try? JSONEncoder().encode(stored),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }

        return string
    }

    static func decode(_ rawValue: String) -> ProEntitlementState {
        guard let data = rawValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredEntitlement.self, from: data) else {
            return .free
        }

        switch stored.state {
        case "active":
            guard let productID = stored.productID else { return .free }
            return .active(productID: productID, expirationDate: stored.expirationDate)
        case "expired":
            guard let productID = stored.productID,
                  let expirationDate = stored.expirationDate else {
                return .free
            }
            return .expired(productID: productID, expirationDate: expirationDate)
        default:
            return .free
        }
    }
}

enum ProSubscriptionError: Error, Equatable {
    case productNotFound
    case nothingToRestore
    case purchaseCancelled
    /// 挽留方案（特惠年度 / 特惠终身）只在用户从免费 / 过期状态购买时可用；
    /// Pro 已启用时再购买会与已有订阅重叠，模型层直接拒绝以避免重复扣款。
    case winbackNotAvailableWhileActive
}

protocol ProSubscriptionStore: Sendable {
    func loadProducts() async throws -> [ProSubscriptionProduct]
    func purchase(productID: String) async throws -> ProEntitlementState
    func restorePurchases() async throws -> ProEntitlementState
}

actor MockProSubscriptionStore: ProSubscriptionStore {
    private let products: [ProSubscriptionProduct]
    private var entitlement: ProEntitlementState
    private var restorableEntitlement: ProEntitlementState?
    private var simulatedError: Error?

    init(
        products: [ProSubscriptionProduct] = ProSubscriptionCatalog.defaultProducts,
        entitlement: ProEntitlementState = .free,
        restorableEntitlement: ProEntitlementState? = nil,
        simulatedError: Error? = nil
    ) {
        self.products = products
        self.entitlement = entitlement
        self.restorableEntitlement = restorableEntitlement
        self.simulatedError = simulatedError
    }

    func setSimulatedError(_ error: Error?) {
        self.simulatedError = error
    }

    func loadProducts() async throws -> [ProSubscriptionProduct] {
        if let error = simulatedError {
            throw error
        }
        return products.map { $0.markingAvailable() }
    }

    func purchase(productID: String) async throws -> ProEntitlementState {
        if let error = simulatedError {
            throw error
        }
        guard products.contains(where: { $0.id == productID }) else {
            throw ProSubscriptionError.productNotFound
        }
        // 模型层不变量：已激活 Pro 时不能再购买挽留方案。
        // lifetimeDiscount 是 NonConsumable，App Store 不会自动取消已有订阅，
        // 允许通过会导致重复扣款；yearlyDiscount 会与已有订阅重叠续费。
        if let plan = ProSubscriptionPlan(productID: productID), plan.isWinback,
           entitlement.isProActive {
            throw ProSubscriptionError.winbackNotAvailableWhileActive
        }

        let purchased = ProEntitlementState.active(productID: productID, expirationDate: nil)
        entitlement = purchased
        restorableEntitlement = purchased
        return purchased
    }

    func restorePurchases() async throws -> ProEntitlementState {
        if let error = simulatedError {
            throw error
        }
        if entitlement.isProActive {
            return entitlement
        }

        guard let restorableEntitlement else {
            throw ProSubscriptionError.nothingToRestore
        }

        entitlement = restorableEntitlement
        return restorableEntitlement
    }
}

struct RevenueCatProSubscriptionStore: ProSubscriptionStore {
    /// Dashboard 当前 entitlement identifier 是 "beforeshow Pro"；
    /// 同时接受 "pro"，方便以后改成更短的 id。
    static let proEntitlementID = "beforeshow Pro"
    static let proEntitlementIDs: Set<String> = ["beforeshow Pro", "pro"]

    /// store product identifier → 内部 plan。
    /// App Store ID 和 Test Store 短 ID 都要认，
    /// 否则 Test Store offering 拉回来后会被全部丢掉。
    static let planForProductID: [String: ProSubscriptionPlan] = [
        ProSubscriptionCatalog.yearlyProductID: .yearly,
        "yearly": .yearly,
        "yearly.v2": .yearly,
        "yearly.trial3d": .yearly,
        ProSubscriptionCatalog.lifetimeProductID: .lifetime,
        "lifetime": .lifetime,
        "lifetime.v2": .lifetime,
        ProSubscriptionCatalog.yearlyDiscountProductID: .yearlyDiscount,
        "yearly.discount": .yearlyDiscount,
        ProSubscriptionCatalog.lifetimeDiscountProductID: .lifetimeDiscount,
        "lifetime.discount": .lifetimeDiscount,
    ]

    func loadProducts() async throws -> [ProSubscriptionProduct] {
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else { return [] }
        let packages = current.availablePackages
        // 试用资格必须在展示前确认：无资格用户看到「免费试用」会构成误导。
        // unknown 也按无资格处理（RC 建议 unknown 时展示正常价格）。
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: packages.map { $0.storeProduct.productIdentifier }
        )
        return packages
            .compactMap { package in
                Self.product(
                    from: package,
                    trialEligible: eligibility[package.storeProduct.productIdentifier]?.status == .eligible
                )
            }
            .sorted { lhs, rhs in
                ProSubscriptionPlan.allCases.firstIndex(of: lhs.plan) ?? 0
                    < ProSubscriptionPlan.allCases.firstIndex(of: rhs.plan) ?? 0
            }
    }

    func purchase(productID: String) async throws -> ProEntitlementState {
        let offerings = try await Purchases.shared.offerings()
        guard let package = offerings.current?.availablePackages
                .first(where: { $0.storeProduct.productIdentifier == productID }) else {
            throw ProSubscriptionError.productNotFound
        }

        // 模型层不变量：已激活 Pro 时不能再购买挽留方案。
        // lifetimeDiscount 是 NonConsumable，App Store 不会自动取消已有订阅，
        // 允许通过会导致重复扣款；yearlyDiscount 会与已有订阅重叠续费。
        if let plan = Self.planForProductID[productID], plan.isWinback,
           let current = try await Self.currentEntitlement(), current.isProActive {
            throw ProSubscriptionError.winbackNotAvailableWhileActive
        }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            // RC 5.x async purchase 返回 PurchaseResultData 元组：
            // (transaction, customerInfo, userCancelled)。取消既可能是 flag，
            // 也可能是 ErrorCode.purchaseCancelledError。
            if result.userCancelled {
                throw ProSubscriptionError.purchaseCancelled
            }
            return Self.entitlement(from: result.customerInfo) ?? .free
        } catch {
            if Self.isPurchaseCancelled(error) {
                throw ProSubscriptionError.purchaseCancelled
            }
            throw error
        }
    }

    func restorePurchases() async throws -> ProEntitlementState {
        let info = try await Purchases.shared.restorePurchases()
        guard let state = Self.entitlement(from: info) else {
            throw ProSubscriptionError.nothingToRestore
        }
        return state
    }

    static func currentEntitlement() async throws -> ProEntitlementState? {
        let info = try await Purchases.shared.customerInfo()
        return entitlement(from: info)
    }

    static func isPurchaseCancelled(_ error: Error) -> Bool {
        (error as NSError).code == ErrorCode.purchaseCancelledError.rawValue
    }

    /// 把 RC 的 `CustomerInfo` 映射成本地 `ProEntitlementState`。
    /// 仅在 RC entitlement 名为 "pro" 时返回非空；否则视为 free。
    static func entitlement(from info: CustomerInfo) -> ProEntitlementState? {
        let entry = proEntitlementIDs.lazy.compactMap { info.entitlements[$0] }.first
        guard let entry else { return nil }
        return entitlement(
            isActive: entry.isActive,
            expirationDate: entry.expirationDate,
            productIdentifier: entry.productIdentifier
        )
    }

    /// `entitlement(from info:)` 的纯函数核心。拆出来便于在测试里直接喂基本类型，
    /// 不用手工构造 `CustomerInfo` / `EntitlementInfo`。
    /// - active → `.active`
    /// - expirationDate < referenceDate → `.expired`
    /// - 其他（包括 nil / 还没到过期时间）→ nil（视为 free）
    static func entitlement(
        isActive: Bool,
        expirationDate: Date?,
        productIdentifier: String,
        referenceDate: Date = Date()
    ) -> ProEntitlementState? {
        if isActive {
            return .active(productID: productIdentifier, expirationDate: expirationDate)
        }
        if let exp = expirationDate, exp < referenceDate {
            return .expired(productID: productIdentifier, expirationDate: exp)
        }
        return nil
    }

    private static func product(from package: Package, trialEligible: Bool) -> ProSubscriptionProduct? {
        let id = package.storeProduct.productIdentifier
        guard let plan = planForProductID[id] else { return nil }
        let fallback = ProSubscriptionCatalog.defaultProducts.first { $0.id == id }
        return ProSubscriptionProduct(
            id: id,
            plan: plan,
            displayName: package.storeProduct.localizedTitle,
            priceText: package.storeProduct.localizedPriceString,
            benefitCopy: fallback?.benefitCopy ?? [],
            isAvailable: true,
            perMonthEquivalentText: plan == .yearly
                ? Self.perMonthEquivalentText(for: package.storeProduct)
                : nil,
            trialText: plan == .yearly && trialEligible
                ? Self.freeTrialText(for: package.storeProduct)
                : nil
        )
    }

    /// 免费试用文案（如「3 天免费试用」）。仅识别零价 introductory offer；
    /// 非天单位的配置不展示，避免与 ASC 实际配置不符的文案。
    private static func freeTrialText(for product: StoreProduct) -> String? {
        guard let discount = product.introductoryDiscount, discount.price == 0 else { return nil }
        return freeTrialText(periodUnit: discount.subscriptionPeriod.unit, value: discount.subscriptionPeriod.value)
    }

    static func freeTrialText(periodUnit: SubscriptionPeriod.Unit, value: Int) -> String? {
        guard periodUnit == .day else { return nil }
        return BSLocalization.format("免费试用 %lld 天", value)
    }

    /// 年度方案按月折算（如 $4.99/年 → 约 $0.42/月），用 RC 真实价格计算。
    private static func perMonthEquivalentText(for product: StoreProduct) -> String? {
        guard let period = product.subscriptionPeriod else { return nil }
        let months: Decimal
        switch period.unit {
        case .day: months = Decimal(period.value) / 30
        case .week: months = Decimal(period.value) * 12 / 52
        case .month: months = Decimal(period.value)
        case .year: months = Decimal(period.value) * 12
        @unknown default:
            return nil
        }
        guard months > 0 else { return nil }
        let monthly = product.price / months
        if let formatter = product.priceFormatter {
            return formatter.string(from: monthly as NSDecimalNumber)
        }
        guard let currencyCode = product.currencyCode else { return nil }
        return monthly.formatted(.currency(code: currencyCode))
    }
}

extension ProSubscriptionPlan {
    init?(productID: String) {
        switch productID {
        case ProSubscriptionCatalog.yearlyProductID:
            self = .yearly
        case ProSubscriptionCatalog.lifetimeProductID:
            self = .lifetime
        case ProSubscriptionCatalog.yearlyDiscountProductID:
            self = .yearlyDiscount
        case ProSubscriptionCatalog.lifetimeDiscountProductID:
            self = .lifetimeDiscount
        default:
            return nil
        }
    }
}

enum ProLimitReason: Equatable {
    case saveLimit

    var title: String {
        switch self {
        case .saveLimit:
            return BSLocalization.text("免费版每月可添加 1 场现场")
        }
    }

    var message: String {
        switch self {
        case .saveLimit:
            return BSLocalization.text("开通 Pro 后可以无限保存现场。")
        }
    }
}

struct ProFeatureGate {
    /// 免费用户每个自然月可添加的现场数量。
    let freeMonthlyShowLimit: Int

    init(freeMonthlyShowLimit: Int = 1) {
        self.freeMonthlyShowLimit = freeMonthlyShowLimit
    }

    func canAddShow(showsAddedThisMonth: Int, entitlement: ProEntitlementState) -> Bool {
        entitlement.isProActive || showsAddedThisMonth < freeMonthlyShowLimit
    }

    /// 统计当自然月（本地时区）新增的现场数。
    func showsAddedThisMonth(
        from createdDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        createdDates.filter { calendar.isDate($0, equalTo: now, toGranularity: .month) }.count
    }

    /// 免费额度只统计用户自己添加的现场（`creationOrigin == .user`）。
    /// 仅因接受 CloudKit 同行邀请而新建的 participant 侧现场不占额度；
    /// 把邀请合并进用户已有现场不会退还已经占用的额度。
    func showsAddedThisMonth(
        from shows: [Show],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        showsAddedThisMonth(
            from: shows.filter { $0.countsTowardFreeMonthlyQuota }.map(\.createdAt),
            now: now,
            calendar: calendar
        )
    }

    func canAccessExistingLocalData(entitlement: ProEntitlementState) -> Bool {
        true
    }

    func canEditManualContent(entitlement: ProEntitlementState) -> Bool {
        true
    }
}
