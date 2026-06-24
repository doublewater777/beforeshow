import Foundation
#if canImport(UIKit) && canImport(Vision)
import UIKit
import Vision
#endif

enum ShowDraftSource: String, Equatable {
    case manual
    case screenshotOCR
    case link
}

enum ShowDraftValidationError: Error, Equatable {
    case emptyName
}

struct ShowDraft: Equatable {
    var name: String
    var date: Date
    var startTime: Date?
    var endDate: Date?
    var endTime: Date?
    var city: String
    var venueName: String
    var artist: String
    var seatSection: String
    var coverImageURL: String
    var artistAvatarURLs: [String]
    var type: ShowType
    var source: ShowDraftSource

    init(
        name: String = "",
        date: Date = Date(),
        startTime: Date? = nil,
        endDate: Date? = nil,
        endTime: Date? = nil,
        city: String = "",
        venueName: String = "",
        artist: String = "",
        seatSection: String = "",
        coverImageURL: String = "",
        artistAvatarURLs: [String] = [],
        type: ShowType = .concert,
        source: ShowDraftSource = .manual
    ) {
        self.name = name
        self.date = date
        self.startTime = startTime
        self.endDate = endDate
        self.endTime = endTime
        self.city = city
        self.venueName = venueName
        self.artist = artist
        self.seatSection = seatSection
        self.coverImageURL = coverImageURL
        self.artistAvatarURLs = artistAvatarURLs
        self.type = type
        self.source = source
    }

    init(show: Show) {
        self.init(
            name: show.name,
            date: show.date,
            startTime: show.startTime,
            endDate: show.endDate,
            endTime: show.endTime,
            city: show.city ?? "",
            venueName: show.venueName ?? "",
            artist: show.artist ?? "",
            seatSection: show.seatSection ?? "",
            coverImageURL: show.coverImageURL ?? "",
            artistAvatarURLs: show.artistAvatarURLs,
            type: show.type,
            source: .manual
        )
    }

    func makeShow() throws -> Show {
        return try Show(
            name: name,
            date: date,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime,
            city: trimmedOptional(city),
            venueName: trimmedOptional(venueName),
            artist: trimmedOptional(artist),
            seatSection: trimmedOptional(seatSection),
            coverImageURL: trimmedOptional(coverImageURL),
            artistAvatarURLs: artistAvatarURLs,
            type: type
        )
    }

    func hasValidEndTime(calendar: Calendar = .current) -> Bool {
        Show.hasValidEndTime(
            date: date,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime,
            calendar: calendar
        )
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ShowScreenshotRecognitionService {
    var calendar: Calendar = .current

    func draft(fromRecognizedText text: String) -> ShowDraft? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !containsSensitiveTicketField($0) }

        guard let date = firstDate(in: lines) else {
            return nil
        }

        let combinedText = lines.joined(separator: "\n")
        let name = value(afterAnyPrefix: [
            "演出名称",
            "项目名称",
            "活动名称",
            "场次名称",
            "名称",
            "Event",
            "EVENT"
        ], in: lines) ?? inferredName(from: lines)

        var draft = ShowDraft(name: name, date: date, source: .screenshotOCR)
        draft.startTime = firstTime(on: date, in: lines)
        draft.city = value(afterAnyPrefix: ["城市"], in: lines) ?? inferredCity(from: lines)
        draft.venueName = value(afterAnyPrefix: [
            "演出场馆",
            "演出地点",
            "场馆",
            "场地",
            "地点",
            "Venue",
            "VENUE"
        ], in: lines) ?? inferredVenue(from: lines)
        draft.artist = value(afterAnyPrefix: [
            "演出艺人",
            "艺人",
            "阵容",
            "Artist",
            "Artists",
            "ARTIST",
            "ARTISTS"
        ], in: lines) ?? ""
        draft.seatSection = value(afterAnyPrefix: [
            "座位",
            "座席",
            "区域",
            "票档",
            "票种",
            "看台",
            "Seat",
            "SEAT"
        ], in: lines) ?? ""
        draft.type = inferredType(from: combinedText)
        return draft
    }

    private func containsSensitiveTicketField(_ line: String) -> Bool {
        let sensitiveKeywords = [
            "订单",
            "二维码",
            "条形码",
            "身份证",
            "手机号",
            "购票人",
            "付款",
            "票号",
            "取票码",
            "入场码",
            "核销码",
            "证件号",
            "实名",
            "支付"
        ]
        return sensitiveKeywords.contains { line.contains($0) }
    }

    private func firstDate(in lines: [String]) -> Date? {
        let yearPatterns = [
            #"(\d{4})[./年-](\d{1,2})[./月-](\d{1,2})[日号]?"#
        ]
        if let date = firstDate(in: lines, patterns: yearPatterns, usesCurrentYear: false) {
            return date
        }

        return firstDate(
            in: lines.filter { !isLikelyPriceOrStatusLine($0) },
            patterns: [#"(\d{1,2})[./月-](\d{1,2})[日号]?"#],
            usesCurrentYear: true
        )
    }

    private func firstDate(in lines: [String], patterns: [String], usesCurrentYear: Bool) -> Date? {

        for line in lines {
            for pattern in patterns {
                let captures = captures(for: pattern, in: line)
                guard !captures.isEmpty else { continue }

                let components: DateComponents
                if !usesCurrentYear, captures.count == 3 {
                    components = DateComponents(
                        calendar: calendar,
                        timeZone: calendar.timeZone,
                        year: Int(captures[0]),
                        month: Int(captures[1]),
                        day: Int(captures[2])
                    )
                } else {
                    guard captures.count >= 2 else { continue }
                    components = DateComponents(
                        calendar: calendar,
                        timeZone: calendar.timeZone,
                        year: calendar.component(.year, from: Date()),
                        month: Int(captures[0]),
                        day: Int(captures[1])
                    )
                }
                if let date = components.date {
                    return date
                }
            }
        }

        return nil
    }

    private func firstTime(on date: Date, in lines: [String]) -> Date? {
        let preferredLines = lines.filter { line in
            firstDate(in: [line]) != nil || line.contains("演出时间") || line.contains("开演")
        }
        if let time = firstTimeIgnoringStatusBar(on: date, in: preferredLines) {
            return time
        }

        return firstTimeIgnoringStatusBar(on: date, in: lines)
    }

    private func firstTimeIgnoringStatusBar(on date: Date, in lines: [String]) -> Date? {
        for line in lines where !isLikelyPhoneStatusTime(line) {
            let captures = captures(for: #"(\d{1,2})[:：](\d{2})"#, in: line)
            guard captures.count == 2 else { continue }
            guard let hour = Int(captures[0]), let minute = Int(captures[1]) else {
                continue
            }

            return calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: date
            )
        }

        return nil
    }

    private func value(afterAnyPrefix prefixes: [String], in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let compactLine = compacted(line)
            for prefix in prefixes {
                let compactPrefix = compacted(prefix)
                guard compactLine.localizedCaseInsensitiveContains(compactPrefix) else {
                    continue
                }

                if let inlineValue = valueFromInlineField(line, prefix: prefix) {
                    return inlineValue
                }

                if let nextLine = firstUsefulLine(after: index, in: lines) {
                    return nextLine
                }
            }
        }

        return nil
    }

    private func valueFromInlineField(_ line: String, prefix: String) -> String? {
        let separators = ["：", ":", " "]
        for separator in separators where line.contains(separator) {
            let parts = line.components(separatedBy: separator)
            guard let firstPart = parts.first,
                  compacted(firstPart).localizedCaseInsensitiveContains(compacted(prefix)) else {
                continue
            }

            let value = parts.dropFirst().joined(separator: separator)
            let cleanedValue = cleanedFieldValue(value)
            if !cleanedValue.isEmpty {
                return cleanedValue
            }
        }

        let compactLine = compacted(line)
        let compactPrefix = compacted(prefix)
        guard compactLine.hasPrefix(compactPrefix),
              line.count > prefix.count else {
            return nil
        }

        let startIndex = line.index(line.startIndex, offsetBy: min(prefix.count, line.count))
        return cleanedFieldValue(String(line[startIndex...]))
    }

    private func firstUsefulLine(after index: Int, in lines: [String]) -> String? {
        guard index + 1 < lines.count else { return nil }

        for nextLine in lines[(index + 1)...].prefix(3) {
            let value = cleanedFieldValue(nextLine)
            guard !value.isEmpty,
                  !isFieldLabelOnly(value),
                  firstDate(in: [value]) == nil else {
                continue
            }
            return value
        }

        return nil
    }

    private func inferredName(from lines: [String]) -> String {
        let titleLines = mergedTitleLines(from: lines)
        if let strongTitle = titleLines
            .map(cleanedFieldValue)
            .filter({ !$0.isEmpty && !isLikelyMetadataLine($0) })
            .max(by: { titleScore($0) < titleScore($1) }),
           titleScore(strongTitle) > 0 {
            return strongTitle
        }

        for line in lines {
            let value = cleanedFieldValue(line)
            guard !value.isEmpty,
                  !isLikelyMetadataLine(value),
                  firstDate(in: [value]) == nil,
                  captures(for: #"(\d{1,2})[:：](\d{2})"#, in: value).isEmpty else {
                continue
            }

            return value
        }

        return ""
    }

    private func inferredVenue(from lines: [String]) -> String {
        for line in lines {
            let value = cleanedFieldValue(line)
            guard !value.isEmpty else { continue }
            if value.contains("馆") || value.contains("中心") || value.contains("剧场") || value.contains("剧院")
                || value.contains("体育场") || value.contains("体育馆") || value.contains("Livehouse")
                || value.contains("酒球会")
                || value.localizedCaseInsensitiveContains("arena")
                || value.localizedCaseInsensitiveContains("stadium")
                || value.localizedCaseInsensitiveContains("theatre") {
                return value
            }
        }

        return ""
    }

    private func inferredCity(from lines: [String]) -> String {
        let joinedText = lines.joined(separator: " ")
        let cityPatterns = [
            #"([北京上海天津重庆杭州市]{2,3})市"#,
            #"([北京上海天津重庆杭州成都广州深圳南京武汉西安长沙苏州厦门青岛]{2,4})[•· 　]"#,
            #"([北京上海天津重庆杭州成都广州深圳南京武汉西安长沙苏州厦门青岛]{2,4})站"#
        ]

        for pattern in cityPatterns {
            let captures = captures(for: pattern, in: joinedText)
            if let city = captures.first, !city.isEmpty {
                return city.hasSuffix("市") ? city : "\(city)市"
            }
        }

        return ""
    }

    private func inferredType(from text: String) -> ShowType {
        if text.localizedCaseInsensitiveContains("Livehouse") || text.localizedCaseInsensitiveContains("live house") {
            return .livehouse
        }

        if text.contains("音乐节") || text.localizedCaseInsensitiveContains("festival") {
            return .musicFestival
        }

        return .concert
    }

    private func cleanedFieldValue(_ value: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:|｜-— "))
        return normalizeCommonOCRErrors(cleaned)
    }

    private func normalizeCommonOCRErrors(_ value: String) -> String {
        value
            .replacingOccurrences(of: "美怡良", with: "艾怡良")
            .replacingOccurrences(of: "逆明会", with: "演唱会")
            .replacingOccurrences(of: "大脚院", with: "大剧院")
            .replacingOccurrences(of: "华黑生物", with: "华熙生物")
            .replacingOccurrences(of: "將百酸", with: "润百颜")
            .replacingOccurrences(of: "E0M", with: "ECM")
    }

    private func compacted(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "　", with: "")
    }

    private func isFieldLabelOnly(_ line: String) -> Bool {
        let labels = [
            "演出名称",
            "项目名称",
            "活动名称",
            "演出时间",
            "时间",
            "日期",
            "演出场馆",
            "场馆",
            "场地",
            "地点",
            "座位",
            "票档",
            "票种",
            "艺人",
            "阵容",
            "DATE",
            "TIME",
            "VENUE",
            "SEAT"
        ]
        return labels.contains { compacted(line).caseInsensitiveCompare(compacted($0)) == .orderedSame }
    }

    private func titleScore(_ line: String) -> Int {
        var score = 0
        let strongKeywords = ["演唱会", "巡回", "联合演出", "音乐节", "LIVE", "Live", "live"]
        let weakKeywords = ["站", "HI LIVE", "工人体育馆", "内心引力", "LOVE", "DESIRE"]
        for keyword in strongKeywords where line.localizedCaseInsensitiveContains(keyword) {
            score += 10
        }
        for keyword in weakKeywords where line.localizedCaseInsensitiveContains(keyword) {
            score += 3
        }
        if line.count >= 8 {
            score += 1
        }
        if firstDate(in: [line]) != nil || isLikelyPriceOrStatusLine(line) {
            score -= 10
        }
        return score
    }

    private func mergedTitleLines(from lines: [String]) -> [String] {
        var candidates = lines
        guard lines.count > 1 else { return candidates }

        for index in 0..<(lines.count - 1) {
            let current = cleanedFieldValue(lines[index])
            let next = cleanedFieldValue(lines[index + 1])
            guard !current.isEmpty, !next.isEmpty else { continue }
            let shouldMerge = current.contains("「")
                || current.localizedCaseInsensitiveContains("HI LIVE")
                || next.contains("巡回")
                || next.contains("演唱会")
                || next.contains("联合演出")
                || current.hasSuffix("工人")
            if shouldMerge {
                candidates.append("\(current)\(next)")
            }
        }

        return candidates
    }

    private func isLikelyMetadataLine(_ line: String) -> Bool {
        let metadataKeywords = [
            "时间",
            "日期",
            "场馆",
            "场地",
            "地点",
            "座位",
            "票价",
            "票档",
            "票种",
            "订单",
            "电子票",
            "取票",
            "入场",
            "观演人",
            "购票",
            "须知",
            "DATE",
            "TIME",
            "VENUE",
            "SEAT",
            "PRICE",
            "TICKET"
        ]
        return metadataKeywords.contains { line.localizedCaseInsensitiveContains($0) }
    }

    private func isLikelyPhoneStatusTime(_ line: String) -> Bool {
        captures(for: #"^\d{1,2}[:：]\d{2}$"#, in: line).count == 2
    }

    private func isLikelyPriceOrStatusLine(_ line: String) -> Bool {
        let compactLine = compacted(line)
        if captures(for: #"^¥?\d+[-~]\d+$"#, in: compactLine).count >= 2 {
            return true
        }
        if captures(for: #"^\d{1,2}[:：]\d{2}$"#, in: compactLine).count == 2 {
            return true
        }
        return line.contains("热卖") || line.contains("缺货") || line.contains("想看")
    }

    private func captures(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return []
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }
}

#if canImport(UIKit) && canImport(Vision)
enum ShowScreenshotImageRecognitionError: Error, Equatable {
    case missingImageData
    case noRecognizedDraft
}

struct OnDeviceShowScreenshotRecognizer {
    var parser: ShowScreenshotRecognitionService = ShowScreenshotRecognitionService()

    func draft(from image: UIImage) async throws -> ShowDraft {
        guard let cgImage = image.cgImage else {
            throw ShowScreenshotImageRecognitionError.missingImageData
        }

        let recognizedText = try await recognizedText(from: cgImage)
        guard let draft = parser.draft(fromRecognizedText: recognizedText) else {
            throw ShowScreenshotImageRecognitionError.noRecognizedDraft
        }

        return draft
    }

    private func recognizedText(from cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif

struct ShowLinkDraftParser {
    enum ParseError: Error, Equatable {
        case unsupportedSource
        case missingDate
    }

    var calendar: Calendar
    private var service: ShowLinkParsingService?

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.service = nil
    }

    init(service: ShowLinkParsingService, calendar: Calendar = .current) {
        self.calendar = calendar
        self.service = service
    }

    func draft(from urlString: String) async throws -> ShowDraft {
        if let service {
            return try await service.parse(link: urlString)
        }

        return try localDraft(from: urlString)
    }

    func draft(from urlString: String) throws -> ShowDraft {
        try localDraft(from: urlString)
    }

    private func localDraft(from urlString: String) throws -> ShowDraft {
        guard let host = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))?.host()?.lowercased(),
              isSupportedHost(host) else {
            throw ParseError.unsupportedSource
        }

        let query = Dictionary(
            uniqueKeysWithValues: (URLComponents(string: urlString)?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        guard let dateString = query["date"],
              let date = parseDate(dateString) else {
            throw ParseError.missingDate
        }

        var draft = ShowDraft(
            name: query["name"] ?? "",
            date: date,
            city: query["city"] ?? "",
            venueName: query["venue"] ?? "",
            artist: query["artist"] ?? "",
            type: type(from: query["type"]),
            source: .link
        )

        if let time = query["time"] {
            draft.startTime = parseTime(time, on: date)
        }
        if let endDate = query["endDate"] {
            draft.endDate = parseDate(endDate)
        }
        if let endTime = query["endTime"] {
            draft.endTime = parseTime(endTime, on: draft.endDate ?? date)
        }

        return draft
    }

    private func isSupportedHost(_ host: String) -> Bool {
        ["damai", "showstart"].contains { host.contains($0) }
    }

    private func parseDate(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ).date
    }

    private func parseTime(_ string: String, on date: Date) -> Date? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }

    private func type(from rawValue: String?) -> ShowType {
        guard let rawValue else { return .concert }
        return ShowType(rawValue: rawValue) ?? .concert
    }
}
