import Foundation

/// How 帮我挑一张 lays out the albums. The 3D shelf and the carousel are Pro; free users share a few opens of them to try.
enum ListeningPickStyle: String, CaseIterable, Identifiable {
    case shelf3D
    case feed
    case rack
    case ring

    static let storageKey = "listeningPickStyle"
    static let trialOpensKey = "listeningPickShelf3DTrialOpens"
    static let trialOpens = 3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf3D: ListeningCopy.text("3D 唱片柜")
        case .feed: ListeningCopy.text("一屏一张")
        case .rack: ListeningCopy.text("正面唱片架")
        case .ring: ListeningCopy.text("旋转木马")
        }
    }

    var isPro: Bool { self == .shelf3D || self == .ring }

    /// RealityView needs iOS 18; on iOS 17 the 3D shelf is not offered.
    static var supportsShelf3D: Bool {
        if #available(iOS 18.0, *) { true } else { false }
    }

    static func available(supportsShelf3D: Bool = supportsShelf3D) -> [Self] {
        allCases.filter { $0 != .shelf3D || supportsShelf3D }
    }

    /// The style an open shows. A new user starts on the 3D shelf; once a free user's trial opens run out a Pro style
    /// falls back to 一屏一张, though an open already counted keeps it until it closes.
    static func resolved(
        storedRawValue: String,
        isPro: Bool,
        trialOpensUsed: Int,
        countedThisOpen: Bool,
        supportsShelf3D: Bool = supportsShelf3D
    ) -> Self {
        let stored = Self(rawValue: storedRawValue) ?? .shelf3D
        if stored == .shelf3D, !supportsShelf3D { return .feed }
        guard stored.isPro else { return stored }
        return isPro || countedThisOpen || trialOpensUsed < trialOpens ? stored : .feed
    }

    /// Trial opens left for a free user; nil for Pro.
    static func trialOpensLeft(isPro: Bool, used: Int) -> Int? {
        isPro ? nil : max(0, trialOpens - used)
    }
}
