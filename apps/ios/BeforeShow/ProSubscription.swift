import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

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
    case monthly
    case yearly
    case lifetime
    case yearlyDiscount
    case lifetimeDiscount

    /// 终身买断没有续订周期，购买/恢复后也不需要到期日语义。
    var isLifetime: Bool {
        self == .lifetime || self == .lifetimeDiscount
    }
}

struct ProSubscriptionProduct: Equatable {
    let id: String
    let plan: ProSubscriptionPlan
    let displayName: String
    let priceText: String
    let benefitCopy: [String]
    /// StoreKit 是否真实返回了该产品。catalog 参考价仅供占位，不可作为生产购买价格。
    let isAvailable: Bool
    /// 年度方案按月折算的文案（如「约 $0.42 / 月」），仅当 StoreKit 提供真实价格时有值。
    let perMonthEquivalentText: String?

    init(
        id: String,
        plan: ProSubscriptionPlan,
        displayName: String,
        priceText: String,
        benefitCopy: [String],
        isAvailable: Bool = false,
        perMonthEquivalentText: String? = nil
    ) {
        self.id = id
        self.plan = plan
        self.displayName = displayName
        self.priceText = priceText
        self.benefitCopy = benefitCopy
        self.isAvailable = isAvailable
        self.perMonthEquivalentText = perMonthEquivalentText
    }

    func markingAvailable(_ available: Bool = true) -> ProSubscriptionProduct {
        ProSubscriptionProduct(
            id: id,
            plan: plan,
            displayName: displayName,
            priceText: priceText,
            benefitCopy: benefitCopy,
            isAvailable: available,
            perMonthEquivalentText: perMonthEquivalentText
        )
    }
}

enum ProSubscriptionCatalog {
    static let monthlyProductID = "com.doublewaterapps.beforeshow.pro.monthly"
    static let yearlyProductID = "com.doublewaterapps.beforeshow.pro.yearly"
    static let lifetimeProductID = "com.doublewaterapps.beforeshow.pro.lifetime"
    static let yearlyDiscountProductID = "com.doublewaterapps.beforeshow.pro.yearly.discount"
    static let lifetimeDiscountProductID = "com.doublewaterapps.beforeshow.pro.lifetime.discount"

    /// 标准在售方案：月度 / 年度 / 终身。
    static let standardPlans: [ProSubscriptionPlan] = [.monthly, .yearly, .lifetime]
    /// 挽回优惠方案：仅在挽留弹窗与长按图标入口展示。
    static let winbackPlans: [ProSubscriptionPlan] = [.yearlyDiscount, .lifetimeDiscount]

    /// 目录参考价：仅用于 UI 占位（产品 ID / 方案映射），`isAvailable == false`，
    /// 生产环境不会展示这些 USD 价格，也不会据此允许购买。
    static let defaultProducts: [ProSubscriptionProduct] = [
        ProSubscriptionProduct(
            id: monthlyProductID,
            plan: .monthly,
            displayName: BSLocalization.text("BeforeShow Pro 月度"),
            priceText: BSLocalization.text("$1.49/月"),
            benefitCopy: [
                "无限添加现场"
            ]
        ),
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

    #if DEBUG
    static let localDebugDefaultEntitlement = ProEntitlementState.active(
        productID: "debug.local.pro",
        expirationDate: nil
    )
    #endif

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
    case purchasePending
    case unverifiedTransaction
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

#if canImport(StoreKit)
struct StoreKitProSubscriptionStore: ProSubscriptionStore {
    var productIDs: [String] = [
        ProSubscriptionCatalog.monthlyProductID,
        ProSubscriptionCatalog.yearlyProductID,
        ProSubscriptionCatalog.lifetimeProductID,
        ProSubscriptionCatalog.yearlyDiscountProductID,
        ProSubscriptionCatalog.lifetimeDiscountProductID
    ]

    func loadProducts() async throws -> [ProSubscriptionProduct] {
        let storeProducts = try await Product.products(for: productIDs)
        return storeProducts
            .compactMap(Self.subscriptionProduct(from:))
            .sorted { first, second in
                ProSubscriptionPlan.allCases.firstIndex(of: first.plan) ?? 0
                    < ProSubscriptionPlan.allCases.firstIndex(of: second.plan) ?? 0
            }
    }

    func purchase(productID: String) async throws -> ProEntitlementState {
        guard let product = try await Product.products(for: [productID]).first else {
            throw ProSubscriptionError.productNotFound
        }

        switch try await product.purchase() {
        case .success(let verificationResult):
            let transaction = try verifiedTransaction(from: verificationResult)
            await transaction.finish()
            return Self.entitlement(from: transaction)
        case .userCancelled:
            throw ProSubscriptionError.purchaseCancelled
        case .pending:
            throw ProSubscriptionError.purchasePending
        @unknown default:
            throw ProSubscriptionError.purchasePending
        }
    }

    func restorePurchases() async throws -> ProEntitlementState {
        try await AppStore.sync()
        if let entitlement = try await currentEntitlement() {
            return entitlement
        }

        throw ProSubscriptionError.nothingToRestore
    }

    private func currentEntitlement() async throws -> ProEntitlementState? {
        for await verificationResult in Transaction.currentEntitlements {
            let transaction = try verifiedTransaction(from: verificationResult)
            guard productIDs.contains(transaction.productID) else { continue }
            return Self.entitlement(from: transaction)
        }

        return nil
    }

    private func verifiedTransaction(
        from result: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw ProSubscriptionError.unverifiedTransaction
        }
    }

    private static func entitlement(from transaction: Transaction) -> ProEntitlementState {
        if let expirationDate = transaction.expirationDate,
           expirationDate < Date() {
            return .expired(productID: transaction.productID, expirationDate: expirationDate)
        }

        return .active(productID: transaction.productID, expirationDate: transaction.expirationDate)
    }

    private static func subscriptionProduct(from product: Product) -> ProSubscriptionProduct? {
        guard let plan = ProSubscriptionPlan(productID: product.id) else {
            return nil
        }

        let fallback = ProSubscriptionCatalog.defaultProducts.first { $0.id == product.id }
        return ProSubscriptionProduct(
            id: product.id,
            plan: plan,
            displayName: product.displayName,
            priceText: product.displayPrice,
            benefitCopy: fallback?.benefitCopy ?? [],
            isAvailable: true,
            perMonthEquivalentText: plan == .yearly ? Self.perMonthEquivalentText(for: product) : nil
        )
    }

    /// 年度方案按月折算（如 $4.99/年 → 约 $0.42/月），用 StoreKit 真实价格计算。
    private static func perMonthEquivalentText(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
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
        return (product.price / months).formatted(product.priceFormatStyle)
    }
}

extension ProSubscriptionPlan {
    init?(productID: String) {
        switch productID {
        case ProSubscriptionCatalog.monthlyProductID:
            self = .monthly
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
#endif

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

    func canAccessExistingLocalData(entitlement: ProEntitlementState) -> Bool {
        true
    }

    func canEditManualContent(entitlement: ProEntitlementState) -> Bool {
        true
    }
}
