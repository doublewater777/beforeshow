import Observation
import SwiftData
import UIKit

/// Opens the on-disk store while the process is still allowed to hold its lock.
@MainActor
@Observable
final class PersistenceStartup {
    private(set) var container: ModelContainer?
    private(set) var needsRetry = false
    private let isBackgroundLaunch: () -> Bool
    private let begin: (@escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
    private let end: (UIBackgroundTaskIdentifier) -> Void
    private let load: () throws -> ModelContainer
    private let prepare: (ModelContainer) -> Void

    init(
        isBackgroundLaunch: @escaping () -> Bool,
        begin: @escaping (@escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier,
        end: @escaping (UIBackgroundTaskIdentifier) -> Void,
        load: @escaping () throws -> ModelContainer,
        prepare: @escaping (ModelContainer) -> Void
    ) {
        self.isBackgroundLaunch = isBackgroundLaunch
        self.begin = begin
        self.end = end
        self.load = load
        self.prepare = prepare
    }

    static func live() -> PersistenceStartup {
        PersistenceStartup(
            isBackgroundLaunch: { UIApplication.shared.applicationState == .background },
            begin: { expiration in
                UIApplication.shared.beginBackgroundTask(withName: "Open persistent store") {
                    MainActor.assumeIsolated { expiration() }
                }
            },
            end: { UIApplication.shared.endBackgroundTask($0) },
            load: { try ModelContainerFactory.make() },
            prepare: { container in
                ListeningIntentHandler.shared.configure(with: container)
                LocalNotificationCenter.shared.configure(with: container)
                AppPersistenceMigrationRunner.run(in: container.mainContext)
                synchronizeFreeShowCapacity(in: container.mainContext)
                syncLiveActivitiesOnLaunch(in: container.mainContext)
            }
        )
    }

    /// The store open stays on the main thread, so a background-time expiration cannot
    /// end the assertion while SQLite is still inside it. Ending it there is what lets
    /// the system suspend the process with the lock held.
    func start() throws {
        guard container == nil else { return }
        needsRetry = false
        let lease = StartupBackgroundLease(end: end)
        defer { lease.finish() }
        lease.identifier = begin { lease.expire() }
        let canOpen = lease.identifier != .invalid && !lease.expired
        guard canOpen || !isBackgroundLaunch() else {
            needsRetry = true
            return
        }

        let loaded = try load()
        // A background launch whose time expired must not continue into migrations.
        // Foreground still publishes the store: dropping it here would reopen SQLite.
        guard !lease.expired || !isBackgroundLaunch() else {
            needsRetry = true
            return
        }
        prepare(loaded)
        container = loaded
    }
}

@MainActor
private final class StartupBackgroundLease {
    var identifier: UIBackgroundTaskIdentifier = .invalid
    private(set) var expired = false
    private let end: (UIBackgroundTaskIdentifier) -> Void

    init(end: @escaping (UIBackgroundTaskIdentifier) -> Void) {
        self.end = end
    }

    func expire() {
        expired = true
    }

    func finish() {
        guard identifier != .invalid else { return }
        let identifier = identifier
        self.identifier = .invalid
        end(identifier)
    }
}
