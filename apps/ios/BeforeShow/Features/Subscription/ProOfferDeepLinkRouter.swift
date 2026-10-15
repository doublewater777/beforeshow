import Observation

@MainActor
@Observable
final class ProOfferDeepLinkRouter {
    static let shared = ProOfferDeepLinkRouter()

    var shouldPresentProSheet = false
    var shouldShowWinbackOffer = false

    private init() {}

    func routeToPro(showWinbackOffer: Bool = false) {
        shouldShowWinbackOffer = showWinbackOffer
        shouldPresentProSheet = true
    }
}
