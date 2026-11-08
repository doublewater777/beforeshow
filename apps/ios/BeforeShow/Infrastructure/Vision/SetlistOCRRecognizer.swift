import Foundation
import CoreGraphics
import UIKit
import Vision

struct SetlistRecognitionResult: Equatable, Sendable {
    let artistName: String?
    let songTitles: [String]
}

enum SetlistOCRRecognizer {
    private static let timeIntervalRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})[:：.点・](\d{2})\s*[-~～—至Nn]\s*(\d{1,2}[:：.点・](\d{2})|END|End|end|结束)"#
    )

    private static let singleTimeRegex = try! NSRegularExpression(
        pattern: #"^(\d{1,2})[:：.点・](\d{2})$"#
    )

    private static let trackPrefixRegex = try! NSRegularExpression(
        pattern: #"^([0-9]{1,2}|[IVXLCDM]+)[\s.、/\\)）-]\s*|^[-•*·]\s*"#,
        options: .caseInsensitive
    )

    private static let setlistHeaderRegex = try! NSRegularExpression(
        pattern: #"(SETLIST|Setlist|setlist|歌单|曲目|节目单|Songlist|Tracklist)"#
    )

    /// Scans OCR observations. If there are no performance time intervals but multiple
    /// candidate song lines exist, returns a detected Setlist.
    static func detect(
        observations: [TimetableOCRObservation],
        showArtist: String? = nil
    ) -> SetlistRecognitionResult? {
        guard !observations.isEmpty else { return nil }

        // If there are time intervals or multiple explicit timestamps, this is likely a timetable.
        let intervalCount = observations.filter { obs in
            timeIntervalRegex.firstMatch(in: obs.text, range: NSRange(obs.text.startIndex..., in: obs.text)) != nil
        }.count

        let singleTimeCount = observations.filter { obs in
            singleTimeRegex.firstMatch(in: obs.text, range: NSRange(obs.text.startIndex..., in: obs.text)) != nil
        }.count

        if intervalCount >= 2 || singleTimeCount >= 4 {
            return nil
        }

        // Sort top-to-bottom.
        let sorted = observations.sorted { $0.top < $1.top }
        var detectedArtist = showArtist
        var songCandidates: [String] = []

        for obs in sorted {
            let line = obs.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if setlistHeaderRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                // Header line like "Artist Setlist"
                let stripped = setlistHeaderRegex.stringByReplacingMatches(
                    in: line,
                    range: NSRange(line.startIndex..., in: line),
                    withTemplate: ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty && detectedArtist == nil {
                    detectedArtist = stripped
                }
                continue
            }

            let cleaned = cleanSongTitle(line)
            guard isLikelySongTitle(cleaned) else { continue }
            if !songCandidates.contains(cleaned) {
                songCandidates.append(cleaned)
            }
        }

        // Require at least 2 distinct song titles to be considered a setlist.
        guard songCandidates.count >= 2 else { return nil }
        return SetlistRecognitionResult(artistName: detectedArtist, songTitles: songCandidates)
    }

    static func cleanSongTitle(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(text.startIndex..., in: text)
        if let match = trackPrefixRegex.firstMatch(in: text, range: range),
           let swiftRange = Range(match.range, in: text) {
            text.removeSubrange(swiftRange)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLikelySongTitle(_ text: String) -> Bool {
        guard text.count >= 1 && text.count <= 40 else { return false }
        // Exclude dates, stages, or common timetable header noise
        if text.contains("202") || text.contains("演出时间") || text.contains("舞台") || text.contains("入场") {
            return false
        }
        return true
    }

    /// Vision OCR directly on a UIImage.
    static func recognize(from image: UIImage, showArtist: String? = nil) async -> SetlistRecognitionResult? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                guard error == nil, let results = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let observations = results.compactMap { obs -> TimetableOCRObservation? in
                    guard let topCandidate = obs.topCandidates(1).first else { return nil }
                    return TimetableOCRObservation(text: topCandidate.string, boundingBox: obs.boundingBox)
                }
                let detected = detect(observations: observations, showArtist: showArtist)
                continuation.resume(returning: detected)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
