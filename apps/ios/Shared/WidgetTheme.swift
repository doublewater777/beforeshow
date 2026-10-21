import SwiftUI

enum WidgetTheme {
    static let background = Color(red: 0.020, green: 0.027, blue: 0.051)
    static let surface = Color(red: 0.051, green: 0.067, blue: 0.106)
    static let surfaceRaised = Color(red: 0.082, green: 0.102, blue: 0.153)
    static let foreground = Color(red: 0.949, green: 0.953, blue: 0.969)
    static let muted = Color(red: 0.576, green: 0.600, blue: 0.667)
    static let dim = Color(red: 0.392, green: 0.420, blue: 0.490)
    static let accent = Color(red: 0.910, green: 0.780, blue: 0.557)
    /// 倒计时 hero 色温递进(对齐 app 端 V4):远场奶白 (#F5EFE2) / 当天暖金 (#F0DCB6)。
    static let heroIvory = Color(red: 0.961, green: 0.937, blue: 0.886)
    static let heroWarmGold = Color(red: 0.941, green: 0.863, blue: 0.714)
    static let live = Color(red: 1.000, green: 0.320, blue: 0.380)
    static let liveTitle = Color(red: 1.000, green: 0.520, blue: 0.580)
    /// 音乐节「今日已结束」的夜色。
    static let night = Color(red: 0.686, green: 0.765, blue: 0.933)
    static let widgetCoverCornerRadius: CGFloat = 12
    /// 中号封面按 App 海报 3:4 收住,不再把高度拉满把间距撑开。
    static let mediumCoverSize = CGSize(width: 81, height: 108)
}
