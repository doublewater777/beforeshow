import CoreText
import UIKit

/// 宋体不随 iOS 预装,是系统按需下载的字体资源。散场记忆出现前请求下载,
/// 下载完成前 `BSFont.Editorial.song` 自动回退到系统字体。
enum BSEditorialFontLoader {
    private static let postScriptNames = [
        BSFont.Editorial.SongWeight.regular.postScriptName,
        BSFont.Editorial.SongWeight.bold.postScriptName,
        BSFont.Editorial.SongWeight.black.postScriptName
    ]

    static var isSongtiAvailable: Bool {
        postScriptNames.allSatisfy { UIFont(name: $0, size: 12) != nil }
    }

    /// 已就绪直接返回;否则下载缺失字重,结束后返回是否全部可用。
    static func ensureSongtiAvailable() async -> Bool {
        let missing = postScriptNames.filter { UIFont(name: $0, size: 12) == nil }
        guard !missing.isEmpty else { return true }

        let descriptors = missing.map {
            CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary)
        } as CFArray

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors, nil) { state, _ in
                if state == .didFinish {
                    continuation.resume()
                }
                return true
            }
        }
        return isSongtiAvailable
    }
}
