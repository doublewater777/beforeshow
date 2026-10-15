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
                return BSLocalization.text("今天开场")
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
        guard let city, !city.isEmpty else { return BSLocalization.text(key: bare) }
        return BSLocalization.format(key: formatKey, city)
    }

    static func dateText(
        for show: Show,
        timeState: CurrentShowTimeState,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard timeState.hasKnownEffectiveDate else { return nil }
        let calendar = show.timingCalendar(fallback: calendar)

        let endTimeZone = show.endTimingCalendar(fallback: calendar).timeZone

        if CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: calendar),
           let endDay = CurrentShowTimeState.effectiveEndDate(for: show, calendar: calendar) {
            var daily = BSDateFormat.clock(show.startTime, timeZone: calendar.timeZone)
            if let endTime = show.endTime {
                daily += "-\(BSDateFormat.clock(endTime, timeZone: endTimeZone))"
            }
            let startYear = calendar.component(.year, from: show.effectiveDate)
            let endYear = calendar.component(.year, from: endDay)
            let endDateText = startYear == endYear
                ? monthDayText(endDay, calendar: calendar)
                : "\(endYear).\(monthDayText(endDay, calendar: calendar))"
            return BSLocalization.format("%@-%@ · 每日 %@", "\(startYear).\(monthDayText(show.effectiveDate, calendar: calendar))", endDateText, daily)
        }

        let weekday = show.effectiveDate.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
        )
        let base = "\(BSDateFormat.dottedDate(show.effectiveDate, calendar: calendar)) \(weekday) \(BSDateFormat.clock(show.startTime, timeZone: calendar.timeZone))"

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

    private static func monthDayText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d", components.month ?? 0, components.day ?? 0)
    }
}

/// V4 首页倒计时卡片:封面之后的深色卡片。
/// pre 远场超大天数、当天秒级时钟、临近 1 小时金色时钟;
/// live 脉冲 + 已进行;ended 冷静收束;inactive 文本态(时间待定 / 已取消)。
