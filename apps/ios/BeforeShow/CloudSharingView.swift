import CloudKit
import SwiftUI
import UIKit

/// Events from system `UICloudSharingController` that the coordinator must reconcile.
enum CloudSharingControllerEvent: Equatable {
    case didSave
    case didStopSharing
    case failedToSave
}

/// Presents system `UICloudSharingController` for an already-prepared `CKShare`.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onEvent: (CloudSharingControllerEvent, CKShare?, Error?) -> Void
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.onDismiss = onDismiss
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        var onEvent: (CloudSharingControllerEvent, CKShare?, Error?) -> Void
        var onDismiss: () -> Void

        init(
            onEvent: @escaping (CloudSharingControllerEvent, CKShare?, Error?) -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.onEvent = onEvent
            self.onDismiss = onDismiss
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onEvent(.didSave, csc.share, nil)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onEvent(.didStopSharing, csc.share, nil)
            onDismiss()
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            onEvent(.failedToSave, csc.share, error)
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? { nil }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String
        }
    }
}

/// Full-screen cover host so SwiftUI can present `UICloudSharingController` modally.
struct CloudSharingPresenter: View {
    let shareData: Data
    let containerIdentifier: String
    let show: Show
    let coordinator: CompanionSharingCoordinator
    var onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let share = try? CloudKitCompanionSharingService.unarchiveShare(from: shareData) {
                CloudSharingView(
                    share: share,
                    container: CKContainer(identifier: containerIdentifier),
                    onEvent: { event, share, error in
                        Task { @MainActor in
                            switch event {
                            case .didSave:
                                await coordinator.handleShareControllerDidSave(
                                    share: share,
                                    for: show,
                                    in: modelContext
                                )
                            case .didStopSharing:
                                await coordinator.handleShareControllerDidStopSharing(
                                    for: show,
                                    in: modelContext
                                )
                            case .failedToSave:
                                if let error {
                                    coordinator.handleShareControllerFailure(error)
                                }
                            }
                        }
                    },
                    onDismiss: onFinished
                )
                .ignoresSafeArea()
            } else {
                Color.clear
                    .onAppear(perform: onFinished)
            }
        }
        .onDisappear(perform: onFinished)
    }
}
