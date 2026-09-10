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
            for name in [
                CDPlayerConfiguration.standard.assets.body,
                CDPlayerConfiguration.standard.assets.lidOuter,
                CDPlayerConfiguration.standard.assets.lidInner,
                CDPlayerConfiguration.standard.assets.disc
            ] {
                _ = UIImage(named: name)
            }
            #endif
        }
    }
}
