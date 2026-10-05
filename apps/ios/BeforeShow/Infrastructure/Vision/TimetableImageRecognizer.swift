import Foundation
#if canImport(UIKit) && canImport(Vision)
import UIKit
import Vision

enum TimetableRecognitionError: Error, Equatable {
    case missingImageData
    case recognitionFailed
    case noTimetableFound
}

struct TimetableImageRecognizer: Sendable {
    let parser: TimetableOCRTextParser

    init(timeZoneIdentifier: String = "Asia/Shanghai") {
        self.parser = TimetableOCRTextParser(timeZoneIdentifier: timeZoneIdentifier)
    }

    func recognize(
        images: [UIImage],
        defaultYear: Int? = nil,
        defaultDate: Date? = nil
    ) async throws -> TimetableDraft {
        try Task.checkCancellation()
        guard !images.isEmpty else {
            throw TimetableRecognitionError.missingImageData
        }

        var drafts: [TimetableDraft] = []
        for image in images {
            try Task.checkCancellation()
            let observations = try await recognizeObservations(from: image)
            let draft = parser.parse(
                observations: observations,
                defaultYear: defaultYear,
                defaultDate: defaultDate
            )
            if !draft.days.isEmpty {
                drafts.append(draft)
            }
        }

        guard !drafts.isEmpty else {
            throw TimetableRecognitionError.noTimetableFound
        }

        let combined = TimetableOCRTextParser.combine(
            drafts: drafts,
            timeZoneIdentifier: parser.timeZone.identifier
        )
        guard !combined.days.isEmpty else {
            throw TimetableRecognitionError.noTimetableFound
        }
        return combined
    }

    func recognizeObservations(from image: UIImage) async throws -> [TimetableOCRObservation] {
        try Task.checkCancellation()
        guard let cgImage = image.cgImage else {
            throw TimetableRecognitionError.missingImageData
        }

        let box = VisionRequestBox()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        box.request = request

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        guard let activeRequest = box.request else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try handler.perform([activeRequest])
                        guard let results = activeRequest.results else {
                            continuation.resume(returning: [])
                            return
                        }
                        let observations = results.compactMap { (obs: VNRecognizedTextObservation) -> TimetableOCRObservation? in
                            guard let top = obs.topCandidates(1).first else { return nil }
                            return TimetableOCRObservation(text: top.string, boundingBox: obs.boundingBox)
                        }
                        continuation.resume(returning: observations)
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

private final class VisionRequestBox: @unchecked Sendable {
    var request: VNRecognizeTextRequest?
}
#endif
