import Foundation

struct FootprintLedgerLine: Identifiable, Equatable {
    let showID: UUID
    let date: Date
    let name: String
    let ticket: Decimal?
    let travel: Decimal?

    var id: UUID { showID }
    var total: Decimal { (ticket ?? 0) + (travel ?? 0) }
}

struct FootprintLedgerReceipt: Equatable {
    let year: Int?
    let currencyCode: String
    /// 最近的在前。
    let lines: [FootprintLedgerLine]
    /// 这一范围里还没记花销的场次。
    let unrecordedShowIDs: [UUID]

    var ticketSum: Decimal { lines.reduce(0) { $0 + ($1.ticket ?? 0) } }
    var travelSum: Decimal { lines.reduce(0) { $0 + ($1.travel ?? 0) } }
    var total: Decimal { ticketSum + travelSum }

    var average: Decimal? {
        guard !lines.isEmpty else { return nil }
        var value = total / Decimal(lines.count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded
    }

    /// 并列时取最近的一场。
    var mostExpensive: FootprintLedgerLine? {
        lines.max { $0.total != $1.total ? $0.total < $1.total : $0.date > $1.date }
    }

    var cheapest: FootprintLedgerLine? {
        lines.min { $0.total != $1.total ? $0.total < $1.total : $0.date > $1.date }
    }
}

/// 一年一张小票：只有填了票价或路费的场次进小票；金额只在本页出现，不进分享图。
enum FootprintLedgerArchive {
    static func years(shows: [Show]) -> [Int] {
        Array(Set(shows.filter(\.hasAnySpending).map(year(of:)))).sorted(by: >)
    }

    static func receipt(shows: [Show], year: Int?) -> FootprintLedgerReceipt {
        let scoped = shows
            .filter { year == nil || Self.year(of: $0) == year }
            .sorted { $0.effectiveDate > $1.effectiveDate }
        let recorded = scoped.filter(\.hasAnySpending)
        let currency = dominantCurrency(recorded)
        let lines = recorded
            .filter { $0.spendingCurrencyCode == currency }
            .map { FootprintLedgerLine(showID: $0.id, date: $0.effectiveDate, name: $0.name, ticket: $0.ticketPrice, travel: $0.travelCost) }
        return FootprintLedgerReceipt(
            year: year,
            currencyCode: currency,
            lines: lines,
            unrecordedShowIDs: scoped.filter { !$0.hasAnySpending }.map(\.id)
        )
    }

    static func year(of show: Show) -> Int {
        show.timingCalendar().component(.year, from: show.effectiveDate)
    }

    /// 换过地区时可能混进别的币种；小票只合计最常用的那一种，不做汇率换算。
    private static func dominantCurrency(_ shows: [Show]) -> String {
        var counts: [String: Int] = [:]
        for show in shows { counts[show.spendingCurrencyCode, default: 0] += 1 }
        let fallback = Show.defaultCurrencyCode
        return counts.max { $0.value != $1.value ? $0.value < $1.value : ($0.key == fallback) }?.key ?? fallback
    }

    static func format(_ amount: Decimal?, currencyCode: String) -> String {
        guard let amount else { return "—" }
        return amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0...2)))
    }
}
