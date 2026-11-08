import SwiftUI

/// iPad 宽屏布局的唯一判定：regular 宽度且容器足够宽。分屏变窄时回到手机排版。
enum BSWideLayout {
    static let minimumWidth: CGFloat = 700

    static func isWide(width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular && width >= minimumWidth
    }

    /// 双栏时左栏宽度：竖屏约等于一台手机，横屏放宽但不超过 520。
    static func leadingColumnWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.46, 390), 520)
    }

    /// 网格列数：手机 2 列，iPad 竖屏 3 列，横屏 4 列。
    static func gridColumnCount(width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> Int {
        guard isWide(width: width, sizeClass: sizeClass) else { return 2 }
        return width >= 1000 ? 4 : 3
    }

    static let columnSpacing: CGFloat = 32
}
