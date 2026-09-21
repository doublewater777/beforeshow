#if canImport(UIKit)
import UIKit
#endif

@MainActor enum ListeningPlayerWarmup {
    private static var didPrepare = false

    static func prepareIfNeeded() {
        guard !didPrepare else { return }
        didPrepare = true
        Task(priority: .utility) { @MainActor in
            CDSoundPlayer.shared.warmup()
            #if canImport(UIKit)
            _ = UIImage(named: CDPlayerConfiguration.standard.assets.disc)
            #endif
        }
    }
}
