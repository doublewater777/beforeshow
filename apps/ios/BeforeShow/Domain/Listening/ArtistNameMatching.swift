import Foundation

enum ArtistNameMatching {
    static func normalized(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split { $0.isWhitespace || $0.isNewline }
        .joined(separator: " ")
    }

    static func contains(_ text: String, query: String) -> Bool {
        let query = normalized(query)
        return query.isEmpty || normalized(text).localizedStandardContains(query)
    }

    static func uniqueExactMatch(
        for query: String,
        among candidates: [RecognizedArtist]
    ) -> RecognizedArtist? {
        let query = normalized(query)
        guard !query.isEmpty else { return nil }
        let exact = candidates.filter { normalized($0.canonicalName) == query }
        guard Set(exact.map(\.id)).count == 1 else { return nil }
        return exact.first
    }
}
