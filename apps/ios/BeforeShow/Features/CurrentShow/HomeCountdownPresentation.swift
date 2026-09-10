import Foundation

enum HomeShowIdentityPresentation {
    static func statusPillText(
        for timeState: CurrentShowTimeState,
        city: String?,
        now: Date
    ) -> String {
        switch timeState.kind {
        case .before:
            return timeState.isDatedPostponement ? BSLocalization.text("新日期") : BSLocalization.text("下一场")
        case .today:
            guard let start = timeState.effectiveStartTime, now >= start else {
                return citySiteText("今天开场 · %@站", city: city, bare: "今天开场")
            }
            return BSLocalization.text("LIVE · 开场中")
        case .dayEnded:
            return citySiteText("已落幕 · %@站", city: city, bare: "已落幕")
        case .postShow:
            return citySiteText("已落幕 · %@站", city: city, bare: "已落幕")
        case .ended:
            return citySiteText("已落幕 · %@站", city: city, bare: "已落幕")
        case .canceled:
            return BSLocalization.text("已取消")
        case .postponed:
            return BSLocalization.text("延期 · 时间待定")
        }
    }

    static func statusText(
        for timeState: CurrentShowTimeState,
        now: Date
    ) -> String {
        switch timeState.kind {
        case .before: return BSLocalization.text("开场前")
        case .today:
            guard let start = timeState.effectiveStartTime, now >= start else {
                return BSLocalization.text("马上开场")
            }
            return BSLocalization.text("开场了")
        case .dayEnded: return BSLocalization.text("今日已落幕")
        case .postShow: return BSLocalization.text("散场后")
        case .ended: return BSLocalization.text("已结束")
        case .canceled: return BSLocalization.text("已取消")
        case .postponed: return BSLocalization.text("时间待定")
        }
    }

    private static func citySiteText(_ formatKey: String, city: String?, bare: String) -> String {
        let city = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let city, !city.isEmpty else { return BSLocalization.text(bare) }
        return BSLocalization.format(formatKey, city)
    }

    static func venueSummary(venue: String?, city: String?) -> String? {
        let venue = trimmed(venue)
        let city = trimmed(city)
        let cityText = {
            guard let city else { return nil as String? }
            guard let venue else { return city }
            guard !venue.localizedCaseInsensitiveContains(city) else { return nil }
            return city
        }()

        let summary = [venue, cityText].compactMap { $0 }.joined(separator: " · ")
        return summary.isEmpty ? nil : summary
    }

    static func dateText(
        for show: Show,
        timeState: CurrentShowTimeState,
        calendar: Calendar = .current,
        locale: Locale = AppLanguageManager.persisted.locale
    ) -> String? {
        guard timeState.hasKnownEffectiveDate else { return nil }
        let calendar = show.timingCalendar(fallback: calendar)

        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy.MM.dd E"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        let endTimeFormatter = DateFormatter()
        endTimeFormatter.locale = locale
        endTimeFormatter.calendar = show.endTimingCalendar(fallback: calendar)
        endTimeFormatter.timeZone = show.endTimingCalendar(fallback: calendar).timeZone
        endTimeFormatter.dateFormat = "HH:mm"

        if CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: calendar),
           let endDay = CurrentShowTimeState.effectiveEndDate(for: show, calendar: calendar) {
            var daily = timeFormatter.string(from: show.startTime)
            if let endTime = show.endTime {
                daily += "-\(endTimeFormatter.string(from: endTime))"
            }
            let startYear = calendar.component(.year, from: show.effectiveDate)
            let endYear = calendar.component(.year, from: endDay)
            let endDateText = startYear == endYear
                ? monthDayText(endDay, calendar: calendar)
                : "\(endYear).\(monthDayText(endDay, calendar: calendar))"
            return BSLocalization.format("%@-%@ · 每日 %@", "\(startYear).\(monthDayText(show.effectiveDate, calendar: calendar))", endDateText, daily)
        }

        let base = "\(dayFormatter.string(from: show.effectiveDate)) \(timeFormatter.string(from: show.startTime))"

        // 已确认散场的现场展示实际时长(开场→散场),不再说「预计」。
        if let endedAt = show.endedAt,
           let actual = ShowDurationFormatter.single(from: timeState.effectiveStartTime ?? show.startTime, to: endedAt) {
            return BSLocalization.format("%@ · 实际演出 %@", base, actual)
        }

        guard let start = timeState.effectiveStartTime,
              let end = timeState.effectiveEndTime,
              let duration = ShowDurationFormatter.single(from: start, to: end) else {
            return base
        }
        return BSLocalization.format("%@ · 预计演出 %@", base, duration)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func monthDayText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d", components.month ?? 0, components.day ?? 0)
    }
}

/// V4 首页倒计时卡片:封面之后的深色卡片。
/// pre 远场超大天数、当天秒级时钟、临近 1 小时金色时钟;
/// live 脉冲 + 已进行;ended 冷静收束;inactive 文本态(时间待定 / 已取消)。
