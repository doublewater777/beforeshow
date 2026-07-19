import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

enum ProSubscriptionPlan: String, CaseIterable, Equatable {
    case monthly
    case yearly
}

struct ProSubscriptionProduct: Equatable {
    let id: String
    let plan: ProSubscriptionPlan
    let displayName: String
    let priceText: String
    let benefitCopy: [String]
}

enum ProSubscriptionCatalog {
    static let monthlyProductID = "com.doublewaterapps.beforeshow.pro.monthly"
    static let yearlyProductID = "com.doublewaterapps.beforeshow.pro.yearly"

    static let defaultProducts: [ProSubscriptionProduct] = [
        ProSubscriptionProduct(
            id: monthlyProductID,
            plan: .monthly,
            displayName: "BeforeShow Pro 月度",
            priceText: "¥12/月",
            benefitCopy: [
                "无限添加现场",
                "重复生成歌单猜想"
            ]
        ),
        ProSubscriptionProduct(
            id: yearlyProductID,
            plan: .yearly,
            displayName: "BeforeShow Pro 年度",
            priceText: "¥68/年",
            benefitCopy: [
                "无限添加现场",
                "重复生成歌单猜想"
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
        return products
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
        ProSubscriptionCatalog.yearlyProductID
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
            benefitCopy: fallback?.benefitCopy ?? []
        )
    }
}

extension ProSubscriptionPlan {
    init?(productID: String) {
        switch productID {
        case ProSubscriptionCatalog.monthlyProductID:
            self = .monthly
        case ProSubscriptionCatalog.yearlyProductID:
            self = .yearly
        default:
            return nil
        }
    }
}
#endif

enum ProFeature: String, CaseIterable, Equatable, Hashable {
    case savedShows
    case candidateSongs
    case outboundTripDraft
    case returnTripDraft
}

enum ProUsageStorage {
    static let usedFreeGenerationFeaturesKey = "usedFreeGenerationFeatures"

    static func encodeUsedFreeGenerationFeatures(_ features: Set<ProFeature>) -> String {
        features
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    static func decodeUsedFreeGenerationFeatures(_ rawValue: String) -> Set<ProFeature> {
        Set(
            rawValue
                .split(separator: ",")
                .compactMap { ProFeature(rawValue: String($0)) }
        )
    }

    static func markUsed(_ feature: ProFeature, in rawValue: String) -> String {
        var features = decodeUsedFreeGenerationFeatures(rawValue)
        features.insert(feature)
        return encodeUsedFreeGenerationFeatures(features)
    }
}

struct ProUsageSnapshot: Equatable {
    var savedShowCount: Int
    var usedFreeGenerationFeatures: Set<ProFeature>

    init(savedShowCount: Int, usedFreeGenerationFeatures: Set<ProFeature> = []) {
        self.savedShowCount = savedShowCount
        self.usedFreeGenerationFeatures = usedFreeGenerationFeatures
    }

    func hasUsedFreeAllowance(for feature: ProFeature) -> Bool {
        usedFreeGenerationFeatures.contains(feature)
    }
}

enum ProLimitReason: Equatable {
    case saveLimit
    case candidateSongsRegeneration
    case roundTripRegeneration

    var title: String {
        switch self {
        case .saveLimit:
            return "免费版可保存 1 场现场"
        case .candidateSongsRegeneration, .roundTripRegeneration:
            return "重复生成需要 Pro"
        }
    }

    var message: String {
        switch self {
        case .saveLimit:
            return "开通 Pro 后可以无限保存现场。"
        case .candidateSongsRegeneration:
            return "免费版每类 AI 内容可体验一次。开通 Pro 后可以重复生成歌单猜想。"
        case .roundTripRegeneration:
            return "免费版每类 AI 内容可体验一次。开通 Pro 后可以重复生成去程计划。"
        }
    }
}

struct ProFeatureGate {
    let freeSavedShowLimit: Int

    init(freeSavedShowLimit: Int = 1) {
        self.freeSavedShowLimit = freeSavedShowLimit
    }

    func canAddShow(savedShowCount: Int, entitlement: ProEntitlementState) -> Bool {
        entitlement.isProActive || savedShowCount < freeSavedShowLimit
    }

    func canAddShow(usage: ProUsageSnapshot, entitlement: ProEntitlementState) -> Bool {
        canAddShow(savedShowCount: usage.savedShowCount, entitlement: entitlement)
    }

    func canGenerate(feature: ProFeature, hasUsedFreeAllowance: Bool, entitlement: ProEntitlementState) -> Bool {
        switch feature {
        case .candidateSongs, .outboundTripDraft, .returnTripDraft:
            return entitlement.isProActive || !hasUsedFreeAllowance
        case .savedShows:
            return entitlement.isProActive
        }
    }

    func canGenerate(feature: ProFeature, usage: ProUsageSnapshot, entitlement: ProEntitlementState) -> Bool {
        canGenerate(
            feature: feature,
            hasUsedFreeAllowance: usage.hasUsedFreeAllowance(for: feature),
            entitlement: entitlement
        )
    }

    func canAddShowFragment(entitlement: ProEntitlementState) -> Bool {
        true
    }

    func canAccessExistingLocalData(entitlement: ProEntitlementState) -> Bool {
        true
    }

    func canEditManualContent(entitlement: ProEntitlementState) -> Bool {
        true
    }
}
