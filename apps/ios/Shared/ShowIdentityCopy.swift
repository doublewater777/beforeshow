import Foundation

// MARK: - Show Identity Copy
// App 首页与 widget 共用同一套身份文案:
// 标题只用演出名,城市站 / 场馆走副文案,避免再拼一层「· 北京站」。

struct ShowIdentityCopy: Equatable {
    let title: String
    let venueSummary: String?

    init(name: String, venueName: String? = nil, city: String? = nil) {
        title = name
        venueSummary = Self.venueSummary(venue: venueName, city: city)
    }

    static func venueSummary(venue: String?, city: String?) -> String? {
        let venue = trimmed(venue)
        let city = trimmed(city)
        let cityText: String? = {
            guard let city else { return nil }
            guard let venue else { return city }
            guard !venue.localizedCaseInsensitiveContains(city) else { return nil }
            return city
        }()

        let summary = [venue, cityText].compactMap { $0 }.joined(separator: " · ")
        return summary.isEmpty ? nil : summary
    }

    func dateVenueLine(dateLine: String) -> String {
        let date = Self.trimmed(dateLine)
        return [date, venueSummary].compactMap { $0 }.joined(separator: " · ")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
