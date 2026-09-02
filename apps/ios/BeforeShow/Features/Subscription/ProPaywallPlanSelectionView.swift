import SwiftUI

struct ProPaywallPlanSelectionView: View {
    let plans: [ProSubscriptionPlan]
    let selectedPlan: ProSubscriptionPlan
    let product: (ProSubscriptionPlan) -> ProSubscriptionProduct?
    let priceAmount: (ProSubscriptionPlan) -> String
    let onSelect: (ProSubscriptionPlan) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(plans, id: \.self) { plan in
                planCard(plan)
            }
        }
        .padding(.top, 8)
    }

    private func planCard(_ plan: ProSubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            onSelect(plan)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(ProPaywallCopy.planName(plan))
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.bottom, 9)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(priceAmount(plan))
                        .font(.system(size: 21, weight: .semibold))
                        .kerning(-0.4)
                        .foregroundColor(BSColor.Stage.foreground)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(ProPaywallCopy.periodLabel(plan))
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                }

                Text(ProPaywallCopy.planNote(plan, product: product(plan)))
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
}
