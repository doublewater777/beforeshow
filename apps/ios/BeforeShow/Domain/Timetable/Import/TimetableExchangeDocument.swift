import Foundation

/// Version 1 of the structured timetable format produced outside the app.
/// Kept apart from the persisted model: every value may be missing or wrong.
struct TimetableExchangeDocument: Decodable, Equatable, Sendable {
    static let supportedVersion = 1

    var version: Int
    var timeZone: String?
    var days: [Day]

    struct Day: Decodable, Equatable, Sendable {
        var date: String?
        var stages: [Stage]
    }

    struct Stage: Decodable, Equatable, Sendable {
        var name: String?
        var performances: [Performance]
    }

    struct Performance: Decodable, Equatable, Sendable {
        var artist: String?
        var start: String?
        var end: String?
    }
}

enum TimetableImportError: Error, Equatable, Sendable {
    case empty
    case noData
    case invalidFormat
    case unsupportedVersion
    case tooLarge
    case invalidTimeZone
    case missingDate
    case invalidDate
    case noSchedule
    case conflictingDays
}

/// Turns pasted text into a document. Code fences and stray text around the
/// object are dropped; anything else that does not decode is rejected as-is.
enum TimetableImportParser {
    static let maxCharacters = 200_000

    private struct VersionProbe: Decodable {
        var version: Int?
    }

    static func document(from text: String) throws -> TimetableExchangeDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TimetableImportError.empty }
        guard trimmed.utf16.count <= maxCharacters else { throw TimetableImportError.tooLarge }
        guard let json = extractObject(from: trimmed) else { throw TimetableImportError.noData }
        let data = Data(json.utf8)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw TimetableImportError.invalidFormat
        }
        guard let version = (try? JSONDecoder().decode(VersionProbe.self, from: data))?.version else {
            throw TimetableImportError.invalidFormat
        }
        guard version == TimetableExchangeDocument.supportedVersion else {
            throw TimetableImportError.unsupportedVersion
        }
        do {
            return try JSONDecoder().decode(TimetableExchangeDocument.self, from: data)
        } catch {
            throw TimetableImportError.invalidFormat
        }
    }

    static func extractObject(from text: String) -> String? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else {
            return nil
        }
        return String(text[open...close])
    }
}
