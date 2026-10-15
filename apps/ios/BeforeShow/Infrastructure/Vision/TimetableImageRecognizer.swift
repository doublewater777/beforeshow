import Foundation
import UIKit
import Vision
import ImageIO

enum TimetableRecognitionError: Error, Equatable {
    case missingImageData
    case recognitionFailed
    case noTimetableFound
}

struct TimetableImageRecognizer: Sendable {
    let parser: TimetableOCRTextParser
    private static let dayLabelRegex = try! NSRegularExpression(
        pattern: #"^(0?[1-9]|1[0-2])[.・/月-](0?[1-9]|[12][0-9]|3[01])日?$"#
    )

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
            var observations = try await recognizeObservations(from: image)
            var draft = parser.parse(
                observations: observations,
                defaultYear: defaultYear,
                defaultDate: defaultDate
            )
            // Upright OCR can miss the sideways day labels beside stacked schedules.
            if draft.days.count == 1 {
                for orientation in [CGImagePropertyOrientation.right, .left] {
                    let dayLabels = try await recognizeObservations(from: image, orientation: orientation)
                    observations.append(contentsOf: dayLabels)
                }
                draft = parser.parse(observations: observations, defaultYear: defaultYear, defaultDate: defaultDate)
            }
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

    private func recognizeObservations(
        from image: UIImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [TimetableOCRObservation] {
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
                        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                        try handler.perform([activeRequest])
                        guard let results = activeRequest.results else {
                            continuation.resume(returning: [])
                            return
                        }
                        let observations = results.compactMap { (obs: VNRecognizedTextObservation) -> TimetableOCRObservation? in
                            guard let top = obs.topCandidates(1).first else { return nil }
                            let rect = obs.boundingBox
                            let boundingBox: CGRect
                            switch orientation {
                            case .right:
                                boundingBox = CGRect(x: 1 - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
                            case .left:
                                boundingBox = CGRect(x: rect.minY, y: 1 - rect.maxX, width: rect.height, height: rect.width)
                            default:
                                boundingBox = rect
                            }
                            if orientation != .up {
                                let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard let match = Self.dayLabelRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                                      let monthRange = Range(match.range(at: 1), in: text),
                                      let dayRange = Range(match.range(at: 2), in: text),
                                      boundingBox.height * CGFloat(cgImage.height) > boundingBox.width * CGFloat(cgImage.width) else { return nil }
                                // Keep dates such as 10.17 distinct from dotted clock times.
                                return TimetableOCRObservation(text: "\(text[monthRange])月\(text[dayRange])日", boundingBox: boundingBox)
                            }
                            return TimetableOCRObservation(text: top.string, boundingBox: boundingBox)
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
