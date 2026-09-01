import AVFoundation
import SwiftUI
import UIKit

// MARK: - Camera

enum MemoryCameraResult {
    case photo(Data)
    case video(URL)
}

struct SystemMemoryCameraPicker: UIViewControllerRepresentable {
    let onComplete: (MemoryCameraResult?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (MemoryCameraResult?) -> Void

        init(onComplete: @escaping (MemoryCameraResult?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let mediaType = info[.mediaType] as? String
            if mediaType == UTType.movie.identifier, let url = info[.mediaURL] as? URL {
                onComplete(.video(url))
                return
            }
            guard let image = info[.originalImage] as? UIImage else {
                onComplete(nil)
                return
            }
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let data = image.jpegData(compressionQuality: 0.92) else {
                    await MainActor.run { self?.onComplete(nil) }
                    return
                }
                await MainActor.run { self?.onComplete(.photo(data)) }
            }
        }
    }
}
