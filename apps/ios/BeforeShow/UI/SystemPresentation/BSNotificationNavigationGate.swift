import UIKit

@MainActor
enum BSNotificationNavigationGate {
    /// Keep an incoming notification pending until editing or another presentation ends.
    static func waitUntilAvailable() async -> Bool {
        while !Task.isCancelled {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController,
               root.presentedViewController == nil {
                return true
            }
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return false }
        }
        return false
    }
}
