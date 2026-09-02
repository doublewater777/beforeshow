import Combine

@MainActor
final class ProOfferDeepLinkRouter: ObservableObject {
    static let shared = ProOfferDeepLinkRouter()

    @Published var shouldPresentProSheet = false
    @Published var shouldShowWinbackOffer = false

    private init() {}

    func routeToPro(showWinbackOffer: Bool = false) {
        shouldShowWinbackOffer = showWinbackOffer
        shouldPresentProSheet = true
    }
}
