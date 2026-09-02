import Foundation

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
