import Foundation

/// Companion names are plain trimmed text. There is no cross-show identity: the same
/// name is the same person, a rename stops matching (ADR 0027).
enum CompanionNameList {
    static func normalized(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    static func joined(_ names: [String]) -> String? {
        let items = normalized(names)
        return items.isEmpty ? nil : items.joined(separator: "、")
    }
}

extension Show {
    var hasCompanions: Bool { !companionNames.isEmpty }

    @discardableResult
    func addCompanion(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !companionNames.contains(trimmed) else { return false }
        setCompanionNames(companionNames + [trimmed])
        return true
    }

    func removeCompanion(_ name: String) {
        setCompanionNames(companionNames.filter { $0 != name })
    }

    /// Fixes a typo in place. A blank replacement is ignored; renaming onto an
    /// existing name merges the two.
    func renameCompanion(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setCompanionNames(companionNames.map { $0 == oldName ? trimmed : $0 })
    }
}

/// One counting rule for「与 A 第 N 次」everywhere: every footprint whose companion
/// names include A counts, whoever else came along.
enum CompanionHistory {
    static func shows(
        with name: String,
        from candidates: [Show],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Show] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }
        return candidates
            .filter { show in
                guard show.changeStatus != .canceled, show.companionNames.contains(name) else { return false }
                let kind = CurrentShowTimeState(show: show, calendar: calendar, now: now).kind
                return kind == .postShow || kind == .ended
            }
            .sorted { lhs, rhs in
                if lhs.effectiveDate == rhs.effectiveDate { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.effectiveDate > rhs.effectiveDate
            }
    }

    /// Names typed on other shows, most recently seen first.
    static func recentNames(from shows: [Show], excluding current: [String] = [], limit: Int = 8) -> [String] {
        let excluded = Set(current)
        let ordered = shows
            .sorted { $0.effectiveDate > $1.effectiveDate }
            .flatMap(\.companionNames)
            .filter { !excluded.contains($0) }
        return Array(CompanionNameList.normalized(ordered).prefix(limit))
    }
}
