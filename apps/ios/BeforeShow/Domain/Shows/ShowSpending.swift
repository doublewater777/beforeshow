import Foundation

enum ShowSpendingError: Error, Equatable {
    case negativeAmount
}

extension Show {
    static var defaultCurrencyCode: String {
        Locale.current.currency?.identifier ?? "CNY"
    }

    var spendingCurrencyCode: String { currencyCode ?? Self.defaultCurrencyCode }

    var hasAnySpending: Bool { ticketPrice != nil || travelCost != nil }

    var hasCompleteSpending: Bool { ticketPrice != nil && travelCost != nil }

    /// nil 表示「还没填」；0 是有效的「免费 / 没花路费」。
    func setSpending(ticketPrice: Decimal?, travelCost: Decimal?, currencyCode: String? = nil) throws {
        if let ticketPrice, ticketPrice < 0 { throw ShowSpendingError.negativeAmount }
        if let travelCost, travelCost < 0 { throw ShowSpendingError.negativeAmount }
        self.ticketPrice = ticketPrice
        self.travelCost = travelCost
        if ticketPrice == nil && travelCost == nil {
            self.currencyCode = nil
        } else {
            self.currencyCode = currencyCode ?? self.currencyCode ?? Self.defaultCurrencyCode
        }
        touch()
    }
}
