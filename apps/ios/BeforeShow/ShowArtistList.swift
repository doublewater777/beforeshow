import Foundation

enum ShowArtistList {
    static func names(from raw: String?) -> [String] {
        guard let raw else { return [] }
        let parts = raw
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var unique: [String] = []
        for part in parts {
            let key = part.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(part)
        }
        return unique
    }

    static func lineup(from raw: String?) -> [String] {
        let values = names(from: raw)
        return values.count >= 3 ? values : []
    }

    static func join(_ names: [String]) -> String {
        names.joined(separator: "、")
    }
}
