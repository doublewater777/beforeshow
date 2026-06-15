import Foundation

struct StartupState: Equatable {
    var hasCompletedOnboarding: Bool
    var hasShows: Bool
}

enum StartupRoute: Equatable {
    case currentHome
}

enum StartupRouter {
    static func route(for state: StartupState) -> StartupRoute {
        .currentHome
    }
}
