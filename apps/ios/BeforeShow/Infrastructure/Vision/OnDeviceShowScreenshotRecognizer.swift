import Foundation
#if canImport(UIKit) && canImport(Vision)
import UIKit
import Vision

enum ShowScreenshotImageRecognitionError: Error, Equatable {
    case missingImageData
    case noRecognizedDraft
}

struct OnDeviceShowScreenshotRecognizer {
    var parser: ShowScreenshotRecognitionService = ShowScreenshotRecognitionService()

    func draft(from image: UIImage) async throws -> ShowDraft {
        try Task.checkCancellation()
        guard let cgImage = image.cgImage else {
            throw ShowScreenshotImageRecognitionError.missingImageData
        }

        let recognizedText = try await recognizedText(from: cgImage)
        try Task.checkCancellation()
        guard let draft = parser.draft(fromRecognizedText: recognizedText) else {
            throw ShowScreenshotImageRecognitionError.noRecognizedDraft
        }

        return draft
    }

    /// Vision `perform` 是阻塞调用；取消时通过 `withTaskCancellationHandler` 调 `request.cancel()`，
    /// 避免页面关闭后仍长时间占 CPU。
    private func recognizedText(from cgImage: CGImage) async throws -> String {
        try Task.checkCancellation()

        // VNRecognizeTextRequest 非 Sendable；用 box 在 onCancel / 后台队列间安全持有。
        let box = VisionTextRequestBox()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        box.request = request

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        guard let request = box.request else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        let handler = VNImageRequestHandler(cgImage: cgImage)
                        try handler.perform([request])
                        let observations = request.results ?? []
                        let lines = observations.compactMap { observation in
                            observation.topCandidates(1).first?.string
                        }
                        continuation.resume(returning: lines.joined(separator: "\n"))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            box.request?.cancel()
        }
    }
}

private final class VisionTextRequestBox: @unchecked Sendable {
    var request: VNRecognizeTextRequest?
}
#endif
