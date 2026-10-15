import Foundation
import XCTest

/// Reads the source-tree String Catalogs so localization tests check what is committed,
/// not what a previous build happened to compile.
struct StringCatalog {
    struct Entry {
        let key: String
        let isTranslatable: Bool
        let isStale: Bool
        let values: [String: String]
    }

    let sourceLanguage: String
    let entries: [Entry]

    init(_ name: String, target: String = "BeforeShow") throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("\(target)/Resources/\(name).xcstrings")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        sourceLanguage = try XCTUnwrap(json["sourceLanguage"] as? String)
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        entries = strings.map { key, entry in
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            return Entry(
                key: key,
                isTranslatable: entry["shouldTranslate"] as? Bool ?? true,
                isStale: entry["extractionState"] as? String == "stale",
                values: localizations.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
            )
        }
    }

    /// Resolved values for one language; the source language falls back to the key itself.
    func table(_ language: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            guard let value = entry.values[language] ?? (language == sourceLanguage ? entry.key : nil) else { return nil }
            return (entry.key, value)
        })
    }
}

final class StringCatalogCompletenessTests: XCTestCase {
    func testEveryLiveTranslatableKeyIsTranslated() throws {
        for (name, target) in [("Localizable", "BeforeShow"), ("Listening", "BeforeShow"), ("TimetableImport", "BeforeShow"), ("Localizable", "BeforeShowWidgets")] {
            let catalog = try StringCatalog(name, target: target)
            for entry in catalog.entries where entry.isTranslatable && !entry.isStale {
                for language in ["en", "zh-Hant"] {
                    XCTAssertFalse(entry.values[language]?.isEmpty ?? true, "\(target)/\(name).xcstrings 缺少 \(language): \(entry.key)")
                }
            }
        }
    }
}
