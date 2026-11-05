import Foundation

/// One day of a show and its forecast; `weather` is nil when the forecast doesn't reach that day yet.
struct ShowWeatherDay: Identifiable, Equatable {
    /// 1-based, as in "Day 2".
    let index: Int
    let date: Date
    let weather: ShowWeatherDTO?

    var id: Int { index }
}

/// Which days a show's weather covers, which of them matters now, and what to pack for all of them.
enum ShowWeatherDays {
    /// A festival longer than this is shown as its first week.
    static let maximumDays = 7

    /// Every day of a multi-day show that repeats daily, otherwise just its one day.
    static func dates(timing: ShowTimingFields, calendar: Calendar) -> [Date] {
        let first = calendar.startOfDay(for: timing.effectiveDate)
        guard CurrentShowTimeState.isMultiDayDailyCycle(timing: timing, calendar: calendar),
              let end = CurrentShowTimeState.effectiveEndDate(timing: timing, calendar: calendar) else {
            return [first]
        }
        let last = calendar.startOfDay(for: end)
        var days: [Date] = []
        var day = first
        while day <= last, days.count < maximumDays {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days.isEmpty ? [first] : days
    }

    /// The day to open on: today while the show runs, otherwise the next day still to come,
    /// and the last day once it has all passed.
    static func relevantIndex(of dates: [Date], now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        return dates.firstIndex { calendar.startOfDay(for: $0) >= today } ?? max(0, dates.count - 1)
    }

    /// One list for the whole trip. Items every forecast day needs stay as they are; items only some
    /// days need say which days, so packing once for the festival covers all of it.
    static func packingList(for days: [ShowWeatherDay]) -> [ShowWeatherPackingItemDTO] {
        let forecast = days.compactMap { day in day.weather.map { (day.index, $0) } }
        guard forecast.count > 1 else { return forecast.first?.1.packingList ?? [] }
        var order: [String] = []
        var firstSeen: [String: ShowWeatherPackingItemDTO] = [:]
        var neededOn: [String: [Int]] = [:]
        for (index, weather) in forecast {
            for item in weather.packingList {
                if firstSeen[item.id] == nil {
                    order.append(item.id)
                    firstSeen[item.id] = item
                }
                neededOn[item.id, default: []].append(index)
            }
        }
        return order.compactMap { id in
            guard let item = firstSeen[id], let days = neededOn[id] else { return nil }
            guard days.count < forecast.count else { return item }
            let label = days.map { "Day \($0)" }.joined(separator: "、")
            return ShowWeatherPackingItemDTO(id: item.id, emoji: item.emoji, title: item.title, subtitle: "\(label) · \(item.subtitle)")
        }
    }
}
