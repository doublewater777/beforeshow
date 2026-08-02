import CloudKit
import SwiftUI
import UIKit

/// Presents system `UICloudSharingController` for an already-prepared `CKShare`.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        context.coordinator.onDismiss = onDismiss
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        var onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {}

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
    var onFinished: () -> Void

    var body: some View {
        Group {
            if let share = try? CloudKitCompanionSharingService.unarchiveShare(from: shareData) {
                CloudSharingView(
                    share: share,
                    container: CKContainer(identifier: containerIdentifier),
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
