import PostHog
import SwiftUI

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
        BSLocalization.text("免费版基础 5 场，之后每个自然月容量 +1。Pro 不限制新增场次。")
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
            if let trial = product?.trialText { return trial }
            guard let perMonth = product?.perMonthEquivalentText else { return "" }
            return BSLocalization.format("约 %@ / 月", perMonth)
        case .lifetime: return BSLocalization.text("一次买断，永久有效")
        case .yearlyDiscount, .lifetimeDiscount: return ""
        }
    }

    static func ctaTitle(
        _ plan: ProSubscriptionPlan,
        product: ProSubscriptionProduct,
        price: String
    ) -> String {
        switch plan {
        case .yearly:
            if let trial = product.trialText {
                return BSLocalization.format("开始%@", trial)
            }
            return BSLocalization.format("订阅年度 Pro · %@", price)
        case .lifetime:
            return BSLocalization.format("买断终身 Pro · %@", price)
        case .yearlyDiscount, .lifetimeDiscount:
            return BSLocalization.format("以特惠价解锁 Pro · %@", price)
        }
    }

    static func ctaNote(
        _ plan: ProSubscriptionPlan,
        product: ProSubscriptionProduct?,
        priceAmount: String
    ) -> String {
        if plan.isLifetime {
            return BSLocalization.text("一次性购买，永久有效。不升级 Pro，已有现场也仍可查看和编辑。")
        }
        if plan == .yearly, let trial = product?.trialText {
            return BSLocalization.format("%@，之后按 %@/年 自动续订，可随时取消。", trial, priceAmount)
        }
        return BSLocalization.text("订阅将通过 App Store 自动续订，直到取消。已有现场即使 Pro 到期，也仍可查看和编辑。")
    }

    static func winbackSaveLabel(_ plan: ProSubscriptionPlan) -> String {
        switch plan {
        case .yearlyDiscount: return BSLocalization.text("省 40%")
        case .lifetimeDiscount: return BSLocalization.text("省 33%")
        default: return ""
        }
    }
}
