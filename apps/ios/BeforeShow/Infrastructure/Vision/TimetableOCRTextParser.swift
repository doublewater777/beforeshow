import Foundation
import CoreGraphics

struct TimetableOCRObservation: Equatable, Sendable {
    let text: String
    let boundingBox: CGRect // Vision normalized: (0,0) is bottom-left

    init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }

    var top: CGFloat { 1.0 - (boundingBox.origin.y + boundingBox.size.height) }
    var bottom: CGFloat { 1.0 - boundingBox.origin.y }
    var left: CGFloat { boundingBox.origin.x }
    var right: CGFloat { boundingBox.origin.x + boundingBox.size.width }
    var midX: CGFloat { boundingBox.midX }
    var midY: CGFloat { top + (bottom - top) / 2.0 }
}

struct TimetableOCRTextParser: Sendable {
    let calendar: Calendar
    let timeZone: TimeZone

    init(timeZoneIdentifier: String = "Asia/Shanghai") {
        let tz = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "Asia/Taipei") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        self.calendar = cal
        self.timeZone = tz
    }

    func parse(
        observations: [TimetableOCRObservation],
        defaultYear: Int? = nil,
        defaultDate: Date? = nil
    ) -> TimetableDraft {
        guard !observations.isEmpty else {
            return TimetableDraft(timeZoneIdentifier: timeZone.identifier, days: [])
        }

        let year = resolveYear(from: observations, defaultYear: defaultYear, defaultDate: defaultDate)

        let intervalRegex = try! NSRegularExpression(
            pattern: "(\\d{1,2})[:：.点・](\\d{2})\\s*[-~～—至Nn]\\s*(\\d{1,2}[:：.点・](\\d{2})|END|End|end|结束)"
        )
        let singleTimeRegex = try! NSRegularExpression(
            pattern: "^(\\d{1,2})[:：.点・](\\d{2})$|^END$|^End$"
        )

        let intervalObs = observations.filter { obs in
            guard intervalRegex.firstMatch(in: obs.text, range: NSRange(obs.text.startIndex..., in: obs.text)) != nil else {
                return false
            }
            let isHeaderDateRange = obs.text.contains("202") && (obs.text.contains("杭州") || obs.text.contains("科技城") || obs.text.contains("公园"))
            return !isHeaderDateRange
        }

        let singleTimeObs = observations.filter { obs in
            singleTimeRegex.firstMatch(in: obs.text, range: NSRange(obs.text.startIndex..., in: obs.text)) != nil
        }

        if intervalObs.count < 3 && singleTimeObs.count >= 6 {
            return parsePatternA(
                observations: observations,
                singleTimes: singleTimeObs,
                year: year,
                defaultDate: defaultDate
            )
        } else {
            return parsePatternBC(
                observations: observations,
                intervals: intervalObs,
                year: year,
                defaultDate: defaultDate
            )
        }
    }

    // MARK: - Pattern A: Single-stage vertical time column (e.g. Taihu Bay)

    private func parsePatternA(
        observations: [TimetableOCRObservation],
        singleTimes: [TimetableOCRObservation],
        year: Int,
        defaultDate: Date?
    ) -> TimetableDraft {
        let (month, day) = resolveHeaderDate(from: observations) ?? fallbackMonthDay(from: defaultDate)

        let sortedTimes = singleTimes.sorted { $0.top < $1.top }
        var timePairs: [(startStr: String, endStr: String, midY: CGFloat)] = []

        var i = 0
        while i + 1 < sortedTimes.count {
            let startRaw = cleanTimeColon(sortedTimes[i].text)
            let endRaw = cleanTimeColon(sortedTimes[i + 1].text)
            let midY = (sortedTimes[i].midY + sortedTimes[i + 1].midY) / 2.0
            timePairs.append((startRaw, endRaw, midY))
            i += 2
        }

        let junkKeywords = [
            "太湖", "MUSIC", "FESTIVAL", "喜力", "Heineken", "SILVER", "演出时间表", "时间表",
            "常州", "联合出品", "总冠名", "战略合作", "合作伙伴", "地图", "eneKen", "SIA", "ISLVIR", "Aneken"
        ]

        let singleTimeCheck = try! NSRegularExpression(pattern: "^\\d{1,2}[:：.点・]\\d{2}$|^END$|^End$")
        let candidateArtists = observations.filter { obs in
            guard obs.left >= 0.25, obs.top > 0.35, obs.top < 0.95 else { return false }
            let hasJunk = junkKeywords.contains { obs.text.contains($0) }
            let isTime = singleTimeCheck.firstMatch(in: obs.text, range: NSRange(obs.text.startIndex..., in: obs.text)) != nil
            return !hasJunk && !isTime
        }.sorted { $0.top < $1.top }

        guard !timePairs.isEmpty, !candidateArtists.isEmpty else {
            return TimetableDraft(timeZoneIdentifier: timeZone.identifier, days: [])
        }

        let dayDate = makeDayMidnight(year: year, month: month, day: day)
        var draftPerformances: [TimetableDraftPerformance] = []

        for pair in timePairs {
            guard let bestArtist = candidateArtists.min(by: { abs($0.midY - pair.midY) < abs($1.midY - pair.midY) }) else {
                continue
            }
            let artistName = cleanArtistName(bestArtist.text)
            guard !artistName.isEmpty else { continue }

            if let (startsAt, endsAt) = resolvePerformanceDates(
                dayDate: dayDate,
                startStr: pair.startStr,
                endStr: pair.endStr
            ) {
                draftPerformances.append(
                    TimetableDraftPerformance(
                        artistName: artistName,
                        startsAt: startsAt,
                        endsAt: endsAt
                    )
                )
            }
        }

        guard !draftPerformances.isEmpty else {
            return TimetableDraft(timeZoneIdentifier: timeZone.identifier, days: [])
        }

        let stage = TimetableDraftStage(name: "主舞台", sortOrder: 0, performances: draftPerformances)
        let draftDay = TimetableDraftDay(date: dayDate, stages: [stage])
        return TimetableDraft(timeZoneIdentifier: timeZone.identifier, days: [draftDay])
    }

    // MARK: - Pattern B/C: Multi-stage grid or segmented list

    private func parsePatternBC(
        observations: [TimetableOCRObservation],
        intervals: [TimetableOCRObservation],
        year: Int,
        defaultDate: Date?
    ) -> TimetableDraft {
        let dateRegex = try! NSRegularExpression(
            pattern: "(?:^|[^\\d])(\\d{1,2})[月・\\.\\-/](\\d{1,2})(?:日|[（\\(].*?[）\\)]|DAY\\d+|$|\\b)"
        )
        let singleTimeCheck = try! NSRegularExpression(pattern: "^\\d{1,2}[:：.点・]\\d{2}$|^END$")
        let intervalCheck = try! NSRegularExpression(
            pattern: "(\\d{1,2})[:：.点・](\\d{2})\\s*[-~～—至Nn]\\s*(\\d{1,2}[:：.点・](\\d{2})|END|End|end|结束)"
        )

        var dateHeaders: [(month: Int, day: Int, midX: CGFloat, top: CGFloat, obs: TimetableOCRObservation)] = []
        for o in observations {
            if intervalCheck.firstMatch(in: o.text, range: NSRange(o.text.startIndex..., in: o.text)) != nil { continue }
            if singleTimeCheck.firstMatch(in: o.text, range: NSRange(o.text.startIndex..., in: o.text)) != nil { continue }
            if o.text.contains("¥") || o.text.contains("科技城") || o.text.contains("杭州") || o.text.contains("常州") { continue }
            if let m = dateRegex.firstMatch(in: o.text, range: NSRange(o.text.startIndex..., in: o.text)) {
                if let r1 = Range(m.range(at: 1), in: o.text),
                   let r2 = Range(m.range(at: 2), in: o.text),
                   let mo = Int(o.text[r1]), let da = Int(o.text[r2]),
                   mo >= 1, mo <= 12, da >= 1, da <= 31 {
                    dateHeaders.append((mo, da, o.midX, o.top, o))
                }
            }
        }

        let stageKeywords = ["舞台", "STAGE", "Stage", "LIVEHOUSE", "Livehouse", "BeeBeeHUM"]
        var stageHeaders: [(name: String, midX: CGFloat, top: CGFloat, obs: TimetableOCRObservation)] = []
        for (idx, o) in observations.enumerated() {
            if stageKeywords.contains(where: { o.text.contains($0) }) {
                var name = o.text.trimmingCharacters(in: .whitespacesAndNewlines)
                name = name.replacingOccurrences(of: "＜", with: "")
                    .replacingOccurrences(of: "＞", with: "")
                    .replacingOccurrences(of: "<", with: "")
                    .replacingOccurrences(of: ">", with: "")
                if name == "舞台" && idx > 0 {
                    let prev = observations[idx - 1]
                    if abs(prev.midX - o.midX) < 0.15 && abs(prev.top - o.top) < 0.05 {
                        name = prev.text.trimmingCharacters(in: .whitespacesAndNewlines) + "舞台"
                    }
                }
                stageHeaders.append((name, o.midX, o.top, o))
            }
        }

        struct RawParsedPerformance {
            let month: Int
            let day: Int
            let stageName: String
            let startStr: String
            let endStr: String
            let artistName: String
        }

        var rawPerformances: [RawParsedPerformance] = []
        let junkText = ["¥", "预约", "现场", "时间表", "公众号", "特别呈现"]

        for o in intervals {
            guard let match = intervalCheck.firstMatch(in: o.text, range: NSRange(o.text.startIndex..., in: o.text)),
                  let r1 = Range(match.range(at: 1), in: o.text),
                  let r2 = Range(match.range(at: 2), in: o.text),
                  let r3 = Range(match.range(at: 3), in: o.text) else {
                continue
            }
            let sStr = "\(o.text[r1]):\(o.text[r2])"
            let ePart = String(o.text[r3])
            let eStr: String
            if ePart.uppercased().contains("END") || ePart.contains("结束") {
                let sh = Int(o.text[r1]) ?? 20
                let sm = Int(o.text[r2]) ?? 0
                eStr = String(format: "%02d:%02d", (sh + 1) % 24, sm)
            } else {
                eStr = cleanTimeColon(ePart)
            }

            // Find artist candidate directly below the interval in the same column
            let belowCandidates = observations.filter { c in
                guard c.text != o.text else { return false }
                let yValid = c.top >= o.top - 0.005 && c.top <= o.bottom + 0.06
                let xValid = abs(c.midX - o.midX) < 0.12
                let isInterval = intervalCheck.firstMatch(in: c.text, range: NSRange(c.text.startIndex..., in: c.text)) != nil
                let isTime = singleTimeCheck.firstMatch(in: c.text, range: NSRange(c.text.startIndex..., in: c.text)) != nil
                let isJunk = junkText.contains { c.text.contains($0) }
                let isDateH = dateHeaders.contains { $0.obs.text == c.text }
                return yValid && xValid && !isInterval && !isTime && !isJunk && !isDateH
            }

            var artist = "未知艺人"
            if let best = belowCandidates.min(by: { abs($0.top - o.bottom) < abs($1.top - o.bottom) }) {
                artist = cleanArtistName(best.text)
            } else {
                // Check right candidates (like horizontal layout in Nanjing pre-party)
                let rightCandidates = observations.filter { c in
                    guard c.text != o.text else { return false }
                    let yValid = abs(c.midY - o.midY) < 0.03
                    let xValid = c.midX > o.midX + 0.15
                    let isInterval = intervalCheck.firstMatch(in: c.text, range: NSRange(c.text.startIndex..., in: c.text)) != nil
                    let isJunk = junkText.contains { c.text.contains($0) }
                    let isDateH = dateHeaders.contains { $0.obs.text == c.text }
                    return yValid && xValid && !isInterval && !isJunk && !isDateH
                }
                if let bestR = rightCandidates.min(by: { abs($0.midY - o.midY) < abs($1.midY - o.midY) }) {
                    artist = cleanArtistName(bestR.text)
                }
            }

            if artist.isEmpty { artist = "未知艺人" }

            // Assign Date
            let (assignedMonth, assignedDay): (Int, Int)
            if !dateHeaders.isEmpty {
                let above = dateHeaders.filter { $0.top <= o.top + 0.005 && abs($0.midX - o.midX) < 0.35 }
                if let closest = above.min(by: { ((o.top - $0.top) * 2 + abs(o.midX - $0.midX)) < ((o.top - $1.top) * 2 + abs(o.midX - $1.midX)) }) {
                    assignedMonth = closest.month
                    assignedDay = closest.day
                } else if let closest = dateHeaders.min(by: { abs($0.midX - o.midX) + abs($0.top - o.top) < abs($1.midX - o.midX) + abs($1.top - o.top) }) {
                    assignedMonth = closest.month
                    assignedDay = closest.day
                } else {
                    (assignedMonth, assignedDay) = fallbackMonthDay(from: defaultDate)
                }
            } else {
                (assignedMonth, assignedDay) = fallbackMonthDay(from: defaultDate)
            }

            // Assign Stage
            let assignedStageName: String
            if !stageHeaders.isEmpty {
                let above = stageHeaders.filter { $0.top <= o.top + 0.005 && abs($0.midX - o.midX) < 0.22 }
                if let closest = above.min(by: { ((o.top - $0.top) * 1.5 + abs(o.midX - $0.midX)) < ((o.top - $1.top) * 1.5 + abs(o.midX - $1.midX)) }) {
                    assignedStageName = closest.name
                } else if let closest = stageHeaders.min(by: { abs($0.midX - o.midX) < abs($1.midX - o.midX) }) {
                    assignedStageName = closest.name
                } else {
                    assignedStageName = "主舞台"
                }
            } else {
                assignedStageName = "主舞台"
            }

            rawPerformances.append(
                RawParsedPerformance(
                    month: assignedMonth,
                    day: assignedDay,
                    stageName: assignedStageName,
                    startStr: sStr,
                    endStr: eStr,
                    artistName: artist
                )
            )
        }

        // Group into TimetableDraft
        var dayGroups: [Date: [String: [TimetableDraftPerformance]]] = [:]
        for raw in rawPerformances {
            let dayDate = makeDayMidnight(year: year, month: raw.month, day: raw.day)
            guard let (startsAt, endsAt) = resolvePerformanceDates(
                dayDate: dayDate,
                startStr: raw.startStr,
                endStr: raw.endStr
            ) else {
                continue
            }
            let perf = TimetableDraftPerformance(
                artistName: raw.artistName,
                startsAt: startsAt,
                endsAt: endsAt
            )
            dayGroups[dayDate, default: [:]][raw.stageName, default: []].append(perf)
        }

        let sortedDayDates = dayGroups.keys.sorted()
        var resultDays: [TimetableDraftDay] = []

        for dDate in sortedDayDates {
            let stageDict = dayGroups[dDate] ?? [:]
            let sortedStageNames = stageDict.keys.sorted()
            var stages: [TimetableDraftStage] = []
            for (sIndex, sName) in sortedStageNames.enumerated() {
                var perfs = stageDict[sName] ?? []
                perfs.sort {
                    if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
                    return $0.endsAt < $1.endsAt
                }
                var uniquePerfs: [TimetableDraftPerformance] = []
                for p in perfs {
                    if !uniquePerfs.contains(where: { $0.artistName == p.artistName && $0.startsAt == p.startsAt }) {
                        uniquePerfs.append(p)
                    }
                }
                if !uniquePerfs.isEmpty {
                    stages.append(TimetableDraftStage(name: sName, sortOrder: sIndex, performances: uniquePerfs))
                }
            }
            if !stages.isEmpty {
                resultDays.append(TimetableDraftDay(date: dDate, stages: stages))
            }
        }

        // Defensive check: ensure sorted days do not overlap
        var sanitizedDays = resultDays
        if sanitizedDays.count > 1 {
            for i in 0..<(sanitizedDays.count - 1) {
                let nextStart = sanitizedDays[i + 1].stages.flatMap(\.performances).map(\.startsAt).min()
                if let nextStart {
                    for sIdx in sanitizedDays[i].stages.indices {
                        for pIdx in sanitizedDays[i].stages[sIdx].performances.indices {
                            if sanitizedDays[i].stages[sIdx].performances[pIdx].endsAt > nextStart {
                                let s = sanitizedDays[i].stages[sIdx].performances[pIdx].startsAt
                                if s < nextStart {
                                    sanitizedDays[i].stages[sIdx].performances[pIdx].endsAt = nextStart
                                }
                            }
                        }
                    }
                }
            }
        }

        return TimetableDraft(timeZoneIdentifier: timeZone.identifier, days: sanitizedDays)
    }

    // MARK: - Multi-image combine

    static func combine(drafts: [TimetableDraft], timeZoneIdentifier: String) -> TimetableDraft {
        guard !drafts.isEmpty else {
            return TimetableDraft(timeZoneIdentifier: timeZoneIdentifier, days: [])
        }

        var dayMap: [Date: [String: [TimetableDraftPerformance]]] = [:]

        for draft in drafts {
            for day in draft.days {
                for stage in day.stages {
                    dayMap[day.date, default: [:]][stage.name, default: []].append(contentsOf: stage.performances)
                }
            }
        }

        let sortedDates = dayMap.keys.sorted()
        var finalDays: [TimetableDraftDay] = []

        for date in sortedDates {
            let stageDict = dayMap[date] ?? [:]
            let sortedStageNames = stageDict.keys.sorted()
            var stages: [TimetableDraftStage] = []

            for (sIdx, sName) in sortedStageNames.enumerated() {
                let perfs = stageDict[sName] ?? []
                var deduped: [TimetableDraftPerformance] = []
                for p in perfs {
                    if !deduped.contains(where: { $0.artistName == p.artistName && $0.startsAt == p.startsAt }) {
                        deduped.append(p)
                    }
                }
                deduped.sort {
                    if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
                    return $0.endsAt < $1.endsAt
                }
                if !deduped.isEmpty {
                    stages.append(TimetableDraftStage(name: sName, sortOrder: sIdx, performances: deduped))
                }
            }
            if !stages.isEmpty {
                finalDays.append(TimetableDraftDay(date: date, stages: stages))
            }
        }

        // Defensive boundary check across days
        if finalDays.count > 1 {
            for i in 0..<(finalDays.count - 1) {
                let nextStart = finalDays[i + 1].stages.flatMap(\.performances).map(\.startsAt).min()
                if let nextStart {
                    for sIdx in finalDays[i].stages.indices {
                        for pIdx in finalDays[i].stages[sIdx].performances.indices {
                            if finalDays[i].stages[sIdx].performances[pIdx].endsAt > nextStart {
                                let s = finalDays[i].stages[sIdx].performances[pIdx].startsAt
                                if s < nextStart {
                                    finalDays[i].stages[sIdx].performances[pIdx].endsAt = nextStart
                                }
                            }
                        }
                    }
                }
            }
        }

        return TimetableDraft(timeZoneIdentifier: timeZoneIdentifier, days: finalDays)
    }

    // MARK: - Helpers

    private func resolveYear(
        from observations: [TimetableOCRObservation],
        defaultYear: Int?,
        defaultDate: Date?
    ) -> Int {
        if let defaultYear { return defaultYear }
        if let defaultDate {
            return calendar.component(.year, from: defaultDate)
        }
        for o in observations {
            let pattern = try! NSRegularExpression(pattern: "202[0-9]")
            if let m = pattern.firstMatch(in: o.text, range: NSRange(o.text.startIndex..., in: o.text)),
               let range = Range(m.range, in: o.text),
               let y = Int(o.text[range]) {
                return y
            }
        }
        return calendar.component(.year, from: Date())
    }

    private func resolveHeaderDate(from observations: [TimetableOCRObservation]) -> (Int, Int)? {
        let pattern = try! NSRegularExpression(pattern: "(\\d{1,2})[・\\.\\-/月](\\d{1,2})")
        for o in observations {
            if o.text.contains("时间") || o.text.contains("演出") || o.text.contains("DAY") || o.text.contains("日") {
                if let m = pattern.firstMatch(in: o.text, range: NSRange(o.text.startIndex..., in: o.text)),
                   let r1 = Range(m.range(at: 1), in: o.text),
                   let r2 = Range(m.range(at: 2), in: o.text),
                   let mo = Int(o.text[r1]), let da = Int(o.text[r2]),
                   mo >= 1, mo <= 12, da >= 1, da <= 31 {
                    return (mo, da)
                }
            }
        }
        return nil
    }

    private func fallbackMonthDay(from defaultDate: Date?) -> (Int, Int) {
        if let defaultDate {
            let m = calendar.component(.month, from: defaultDate)
            let d = calendar.component(.day, from: defaultDate)
            return (m, d)
        }
        return (10, 1)
    }

    private func makeDayMidnight(year: Int, month: Int, day: Int) -> Date {
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = day
        comp.hour = 0
        comp.minute = 0
        comp.second = 0
        let date = calendar.date(from: comp) ?? Date()
        return calendar.startOfDay(for: date)
    }

    private func cleanTimeColon(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "・", with: ":")
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: "点", with: ":")
            .replacingOccurrences(of: "：", with: ":")
        let regex = try! NSRegularExpression(pattern: "^(\\d{1,2}):(\\d{2})")
        if let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let r1 = Range(m.range(at: 1), in: s),
           let r2 = Range(m.range(at: 2), in: s) {
            let h = Int(s[r1]) ?? 0
            let minStr = s[r2]
            return String(format: "%02d:%@", h, String(minStr))
        }
        return s
    }

    private func cleanArtistName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"（\d+['‘分].*?）"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\(\d+['‘分].*?\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"（海泡岛定SPECIAL SET）"#, with: "")
        s = s.replacingOccurrences(of: #"大把时间璀璨」90min限定"#, with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    private func resolvePerformanceDates(
        dayDate: Date,
        startStr: String,
        endStr: String
    ) -> (Date, Date)? {
        let sParts = startStr.split(separator: ":").compactMap { Int($0) }
        let eParts = endStr.split(separator: ":").compactMap { Int($0) }
        guard sParts.count == 2, eParts.count == 2 else { return nil }
        var sh = sParts[0]
        let sm = min(59, max(0, sParts[1]))
        let eh = eParts[0]
        let em = min(59, max(0, eParts[1]))

        if sh < 10 && eh >= 12 && eh - (sh + 10) <= 2 {
            sh += 10
        }

        guard let start = calendar.date(bySettingHour: sh, minute: sm, second: 0, of: dayDate),
              let baseEnd = calendar.date(bySettingHour: eh, minute: em, second: 0, of: dayDate) else {
            return nil
        }

        var end = baseEnd
        if end <= start {
            if sh >= 21 && eh <= 6 {
                end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(3600)
            } else {
                end = calendar.date(byAdding: .minute, value: 40, to: start) ?? start.addingTimeInterval(2400)
            }
        }
        guard start < end else { return nil }
        return (start, end)
    }
}
