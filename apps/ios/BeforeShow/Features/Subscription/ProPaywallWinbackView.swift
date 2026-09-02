import SwiftUI

struct ProPaywallWinbackView: View {
    let selectedPlan: ProSubscriptionPlan
    let purchasingProductID: String?
    let product: (ProSubscriptionPlan) -> ProSubscriptionProduct?
    let priceAmount: (ProSubscriptionPlan) -> String
    let standardPriceAmount: (ProSubscriptionPlan) -> String
    let ctaPrice: (ProSubscriptionPlan) -> String
    let onSelect: (ProSubscriptionPlan) -> Void
    let onPurchase: (ProSubscriptionPlan) -> Void
    let onDecline: () -> Void

    var body: some View {
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
                dealCard(.yearlyDiscount)
                dealCard(.lifetimeDiscount)
            }

            Button {
                onPurchase(selectedPlan)
            } label: {
                HStack {
                    if let productID = product(selectedPlan)?.id, purchasingProductID == productID {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(ctaTitle)
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(purchasingProductID != nil || product(selectedPlan)?.isAvailable != true)

            Button(BSLocalization.text("暂时不要"), action: onDecline)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BSSpacing.sm)
        }
    }

    private func dealCard(_ plan: ProSubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            onSelect(plan)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
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
                    Text(priceAmount(plan))
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

                let originalPrice = standardPriceAmount(plan)
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

    private var ctaTitle: String {
        guard product(selectedPlan)?.isAvailable == true else {
            return BSLocalization.text("价格暂不可用")
        }
        return BSLocalization.format("以特惠价解锁 Pro · %@", ctaPrice(selectedPlan))
    }
}
