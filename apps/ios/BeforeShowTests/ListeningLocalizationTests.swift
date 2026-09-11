import XCTest
@testable import BeforeShow

final class ListeningLocalizationTests: XCTestCase {
    func testAllListeningLiteralKeysAndTierNamesExistInThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow")
        var keys = Set(ListeningFamiliarityTier.allCases.map(\.localizationKey))
        keys.formUnion(["想现场听", "开场前想现场听", "当前现场", "只听这位", "回到整场", "不听这位", "恢复", "接下来", "下一位", "热门", "全部", "尚未匹配艺人", "暂时无法更新", "暂时无法载入音乐"])
        let regex = try NSRegularExpression(pattern: #"BSLocalization\.text\("([^"\\]+)"\)"#)
        for subdir in ["Features/Listening", "Features/Footprints"] {
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent(subdir), includingPropertiesForKeys: nil))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                if subdir.contains("Footprints") && !url.lastPathComponent.contains("Listening") && !url.lastPathComponent.contains("Setlist") { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                let ns = source as NSString
                for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) { keys.insert(ns.substring(with: match.range(at: 1))) }
            }
        }
        for locale in ["zh-Hans", "zh-Hant", "en"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Resources/\(locale).lproj/Localizable.strings"))
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            for key in keys { XCTAssertFalse(values[key]?.isEmpty ?? true, "Missing \(locale): \(key)") }
        }
    }

    func testListeningCapabilityProjectionCopyExistsInThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow")
        let keys: Set<String> = [
            "连接中…", "完整播放", "试听模式", "仅歌曲信息", "暂不可播放",
            "立即授权", "打开设置", "重试", "试听", "部分曲目可试听", "30 秒试听",
            "正在准备播放", "试听中 · 剩余 %d 秒", "播放中", "试听暂停 · 剩余 %d 秒",
            "暂停", "停止", "播放结束", "暂时无法播放", "选择一张唱片开始播放",
            "当前仅提供歌曲信息", "当前暂不可播放", "请先合上播放器上盖", "热门合辑",
            "仅提供歌曲信息", "授权后载入唱片"
        ]

        for locale in ["zh-Hans", "zh-Hant", "en"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Resources/\(locale).lproj/Listening.strings"))
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertEqual(Set(values.keys), keys)
            for key in keys {
                XCTAssertFalse(values[key]?.isEmpty ?? true, "Missing \(locale): \(key)")
            }
            XCTAssertTrue(values["试听中 · 剩余 %d 秒"]?.contains("%d") == true)
            XCTAssertTrue(values["试听暂停 · 剩余 %d 秒"]?.contains("%d") == true)
        }
    }
}
