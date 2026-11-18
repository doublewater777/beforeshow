import Foundation

enum ArtistNameMatching {
    private static let simplified = StringTransform("Traditional-Simplified")
    private static let traditional = StringTransform("Simplified-Traditional")

    /// A remote-query cache key must preserve the original script.
    static func searchKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
    }

    static func normalized(_ name: String) -> String {
        let converted = name.applyingTransform(simplified, reverse: false) ?? name
        return searchKey(converted)
    }

    static func contains(_ text: String, query: String) -> Bool {
        let query = normalized(query)
        return query.isEmpty || normalized(text).localizedStandardContains(query)
    }

    /// Local spellings for comparing saved identities; these do not create remote searches.
    static func nameVariants(for name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var queries: [String] = []
        var seen = Set<String>()
        func append(_ value: String) {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && seen.insert(cleaned.lowercased()).inserted { queries.append(cleaned) }
        }
        append(trimmed)
        if let value = trimmed.applyingTransform(simplified, reverse: false) { append(value) }
        if let value = trimmed.applyingTransform(traditional, reverse: false) { append(value) }

        if let open = trimmed.lastIndex(where: { $0 == "(" || $0 == "（" }),
           trimmed.last == ")" || trimmed.last == "）" {
            append(String(trimmed[..<open]))
            append(String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]))
        }

        let isHan: (Character) -> Bool = { character in
            character.unicodeScalars.contains {
                (0x3400...0x9FFF).contains($0.value) || (0x20000...0x2FA1F).contains($0.value)
            }
        }
        let han = String(trimmed.filter(isHan))
        let other = String(trimmed.filter { !isHan($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        let hasLatin = other.unicodeScalars.contains {
            (65...90).contains($0.value) || (97...122).contains($0.value)
        }
        if !han.isEmpty && hasLatin {
            append(han)
            append(other)
        }
        return queries
    }

    static func uniqueExactMatch(for query: String, among candidates: [RecognizedArtist]) -> RecognizedArtist? {
        let key = normalized(query)
        guard !key.isEmpty else { return nil }
        return uniqueID(candidates.filter { normalized($0.canonicalName) == key })
    }

    /// Keep the search provider's order, admitting only candidates with a portrait.
    static func searchCandidates(_ candidates: [RecognizedArtist]) -> [RecognizedArtist] {
        var seen = Set<String>()
        return candidates.filter { $0.avatarURL != nil && seen.insert($0.id).inserted }
    }

    /// Search ranking owns spelling, aliases and suffixes. Only a same-name ID
    /// collision around the preferred result requires a manual choice.
    static func automaticMatch(among candidates: [RecognizedArtist]) -> RecognizedArtist? {
        let eligible = searchCandidates(candidates)
        guard let first = eligible.first else { return nil }
        return uniqueID(eligible.filter { hasSameName($0.canonicalName, first.canonicalName) })
    }

    /// While the user is typing, never replace their text with a different credit
    /// or promote a lower-ranked exact-name artist over the preferred result.
    static func matchForTypedName(_ query: String, among candidates: [RecognizedArtist]) -> RecognizedArtist? {
        guard let match = automaticMatch(among: candidates),
              normalized(query) == normalized(match.canonicalName) else { return nil }
        return match
    }

    static func isConfidentMatch(_ name: String, candidateName: String) -> Bool {
        guard !normalized(name).isEmpty else { return false }
        return normalized(name) == normalized(candidateName)
            || isAliasEquivalent(name, candidateName)
    }

    private static func isAliasEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let left = nameVariants(for: lhs).map(normalized)
        let right = Set(nameVariants(for: rhs).map(normalized))
        if left.contains(where: { right.contains($0) }) { return true }

        return hasSameName(lhs, rhs)
    }

    /// Ignore punctuation, but keep internal spaces significant ("A B" != "AB").
    private static func hasSameName(_ lhs: String, _ rhs: String) -> Bool {
        func withoutPunctuation(_ name: String) -> String {
            let scalars = normalized(name).unicodeScalars.filter {
                !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0)
            }
            return String(String.UnicodeScalarView(scalars))
        }
        let a = withoutPunctuation(lhs)
        return !a.isEmpty && a == withoutPunctuation(rhs)
    }

    private static func uniqueID(_ candidates: [RecognizedArtist]) -> RecognizedArtist? {
        guard !candidates.isEmpty, Set(candidates.map(\.id)).count == 1 else { return nil }
        return candidates.first
    }
}
