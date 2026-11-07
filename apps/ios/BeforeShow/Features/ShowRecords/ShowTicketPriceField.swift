import SwiftData
import SwiftUI

/// 票根查看页底部的票价格：随票根一起填，和「花销」共用 `Show.ticketPrice`。
struct ShowTicketPriceField: View {
    @Query private var shows: [Show]
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @State private var didLoad = false
    @FocusState private var isFocused: Bool

    init(showID: UUID) {
        _shows = Query(filter: #Predicate<Show> { $0.id == showID })
    }

    var body: some View {
        if let show = shows.first {
            HStack(spacing: 10) {
                Text(BSLocalization.text("票价"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer(minLength: 8)
                Text(Locale.current.localizedCurrencySymbol(for: show.spendingCurrencyCode))
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.Stage.muted)
                TextField(BSLocalization.text("还没填"), text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(BSColor.Stage.foreground)
                    .focused($isFocused)
                    .frame(maxWidth: 120)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .bsGlassPanel(in: Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .onAppear {
                guard !didLoad else { return }
                text = ShowSpendingSheet.text(show.ticketPrice)
                didLoad = true
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit(show) }
            }
            .onDisappear { commit(show) }
        }
    }

    private func commit(_ show: Show) {
        let amount = ShowSpendingSheet.amount(text)
        guard amount != show.ticketPrice else { return }
        do {
            try show.setSpending(ticketPrice: amount, travelCost: show.travelCost, currencyCode: show.currencyCode)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            text = ShowSpendingSheet.text(show.ticketPrice)
        }
    }
}
