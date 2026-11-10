import Foundation

/// How 帮我挑一张 lays out the albums. The 3D shelf is Pro; free users get a few opens of it to try.
enum ListeningPickStyle: String, CaseIterable, Identifiable {
    case shelf3D
    case feed
    case rack

    static let storageKey = "listeningPickStyle"
    static let trialOpensKey = "listeningPickShelf3DTrialOpens"
    static let trialOpens = 3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf3D: ListeningCopy.text("3D 唱片柜")
        case .feed: ListeningCopy.text("一屏一张")
        case .rack: ListeningCopy.text("正面唱片架")
        }
    }

    var isPro: Bool { self == .shelf3D }

    /// RealityView needs iOS 18; on iOS 17 the 3D shelf is not offered.
    static var supportsShelf3D: Bool {
        if #available(iOS 18.0, *) { true } else { false }
    }

    static func available(supportsShelf3D: Bool = supportsShelf3D) -> [Self] {
        allCases.filter { $0 != .shelf3D || supportsShelf3D }
    }

    /// The style an open shows. A new user starts on the 3D shelf; once a free user's trial opens run out it falls back
    /// to 一屏一张, though an open already counted keeps the 3D shelf until it closes.
    static func resolved(
        storedRawValue: String,
        isPro: Bool,
        trialOpensUsed: Int,
        countedThisOpen: Bool,
        supportsShelf3D: Bool = supportsShelf3D
    ) -> Self {
        let stored = Self(rawValue: storedRawValue) ?? .shelf3D
        guard stored == .shelf3D else { return stored }
        guard supportsShelf3D else { return .feed }
        return isPro || countedThisOpen || trialOpensUsed < trialOpens ? .shelf3D : .feed
    }

    /// Trial opens left for a free user; nil for Pro.
    static func trialOpensLeft(isPro: Bool, used: Int) -> Int? {
        isPro ? nil : max(0, trialOpens - used)
    }
}
