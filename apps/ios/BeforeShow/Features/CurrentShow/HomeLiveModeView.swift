import SwiftUI

/// Under the stage once a festival timetable is live: who is on, how long is left, who is next.
struct HomeLiveModeView: View {
    let show: Show
    let timetable: Timetable
    let state: LiveModeState
    let avatars: TimetableArtistAvatarStore
    var onEndShow: (() -> Void)?
    let onOpenTimetable: () -> Void

    @AppStorage(LiveModeFocusStore.key, store: LiveModeFocusStore.defaults) private var focusedPerformanceID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var upcoming: [LivePerformanceSnapshot] {
        state.upcomingPerformances.sorted { $0.startsAt < $1.startsAt }
    }

    private var stageOrder: [UUID: Int] {
        var order: [UUID: Int] = [:]
        for day in timetable.orderedDays {
            for stage in day.orderedStages where order[stage.id] == nil { order[stage.id] = stage.sortOrder }
        }
        return order
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state.phase {
            case .active where !state.currentPerformances.isEmpty:
                onStage
            case .active:
                between
            case .upcoming:
                if let opener = upcoming.first {
                    nextUp(opener, label: BSLocalization.text("今日首场"), slotCount: 1)
                }
            case .dayEnded(let next):
                dayEnded(next)
            case .fullyEnded:
                finale
            }

            if state.phase == .fullyEnded, let onEndShow {
                Button(action: onEndShow) {
                    Text(BSLocalization.text("结束现场"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(BSColor.Stage.foreground, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.26), value: state.currentPerformances.first?.id)
    }

    // MARK: - On stage

    @ViewBuilder
    private var onStage: some View {
        let lead = state.currentPerformances[0]
        let total = lead.endsAt.timeIntervalSince(lead.startsAt)
        let progress = total > 0 ? max(0, min(1, 1 - lead.secondsUntilEnd / total)) : 0
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TimetableEqualizer()
                stageChip(lead, small: true)
                Text("\(clock(lead.startsAt))–\(clock(lead.endsAt))")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(BSColor.Stage.muted)
            }
            artistTitle(lead.artistName)
            minutesLine(Int((lead.secondsUntilEnd / 60).rounded(.up)), unit: BSLocalization.text("分钟后结束"))
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(BSColor.Stage.live)
                            .frame(width: geo.size.width * progress)
                            .shadow(color: BSColor.Stage.live.opacity(0.8), radius: 4)
                    }
            }
            .frame(height: 3)
            .padding(.top, 12)
        }
        .id(lead.id)
        setlist(Array(upcoming.prefix(3)), alsoLive: Array(state.currentPerformances.dropFirst()))
    }

    // MARK: - Between sets / before the first set

    @ViewBuilder
    private var between: some View {
        if let first = upcoming.first {
            nextUp(first, label: BSLocalization.text("下一场"), slotCount: upcoming.filter { $0.startsAt == first.startsAt }.count)
        }
    }

    @ViewBuilder
    private func nextUp(_ next: LivePerformanceSnapshot, label: String, slotCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(BSColor.Stage.heroWarmGold)
                stageChip(next, small: true)
            }
            artistTitle(next.artistName)
            let minutes = Int((next.secondsUntilStart / 60).rounded(.up))
            if minutes < 180 {
                minutesLine(minutes, unit: BSLocalization.format("分钟后开演 · %@", clock(next.startsAt)))
            } else {
                minutesLine(nil, unit: BSLocalization.format("%@ 开演", clock(next.startsAt)))
            }
        }
        setlist(Array(upcoming.dropFirst().prefix(3)))
    }

    private func artistTitle(_ name: String) -> some View {
        Text(name)
            .font(BSFont.Editorial.serif(28))
            .foregroundStyle(BSColor.Stage.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    private func minutesLine(_ value: Int?, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let value {
                Text("\(value)")
                    .font(BSFont.Editorial.serif(56))
                    .monospacedDigit()
                    .foregroundStyle(BSColor.Stage.heroIvory)
                    .contentTransition(.numericText(countsDown: true))
            }
            Text(unit)
                .font(.system(size: 14))
                .foregroundStyle(BSColor.Stage.muted)
        }
        .padding(.top, 8)
    }

    // MARK: - Day ended

    @ViewBuilder
    private func dayEnded(_ next: Date?) -> some View {
        let now = Date()
        let calendar = eventCalendar
        let days = timetable.orderedDays.filter { !$0.performances.isEmpty }
        let endedIndex = days.lastIndex { $0.performances.allSatisfy { $0.endsAt <= now } }
        let nextDay = endedIndex.flatMap { $0 + 1 < days.count ? days[$0 + 1] : nil }
        // Festival days to the next set: usually 明天, a date when the festival skips days.
        let ahead = next.map { FestivalDay.distance(from: now, to: $0, calendar: calendar) } ?? 1
        let resumes = next.map { FestivalDay.word(for: $0, distance: ahead, calendar: calendar) } ?? BSLocalization.text("明天")

        if let endedIndex {
            let ended = days[endedIndex]
            let since = FestivalDay.distance(from: ended.performances.map(\.startsAt).max() ?? ended.date, to: now, calendar: calendar)
            VStack(alignment: .leading, spacing: 0) {
                Text(monthDay(ended.date))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(HomeLiveStyle.night)
                Text(BSLocalization.format("DAY %d 已结束", dayNumber(ended)))
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .padding(.top, 8)
                Text(BSLocalization.format(since == 0 ? "今天辛苦了，%@继续" : since == 1 ? "昨天辛苦了，%@继续" : "辛苦了，%@继续", resumes))
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.Stage.muted)
                    .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [HomeLiveStyle.night.opacity(0.12), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }

        if let nextDay, let next {
            let sets = nextDay.performances.sorted(by: TimetablePerformance.chronologicalOrder)
            HomeLiveHeroCard(tint: HomeLiveStyle.night) {
                dayEyebrow(nextDay)
                HStack(alignment: .firstTextBaseline) {
                    Text(BSLocalization.format("%@ %@ 继续", resumes, clock(next)))
                        .font(.system(size: 24, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(BSColor.Stage.foreground)
                    Spacer(minLength: 8)
                    Text(remaining(until: next, from: now, days: ahead))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BSColor.Stage.muted)
                }
                .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(sets.prefix(5)) { perf in
                        tomorrowRow(perf)
                    }
                }
                .background(alignment: .leading) {
                    LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                        .frame(width: 1.5)
                        .padding(.leading, 4.75)
                        .padding(.vertical, 16)
                }
                .padding(.top, 10)
            }
            .padding(.top, 12)
        }
    }

    private func tomorrowRow(_ perf: TimetablePerformance) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(perf.isInterested ? BSColor.Stage.accent : BSColor.Stage.background)
                .overlay(Circle().strokeBorder(perf.isInterested ? .clear : Color.white.opacity(0.25), lineWidth: 1.5))
                .frame(width: 11, height: 11)
                .shadow(color: perf.isInterested ? BSColor.Stage.accent.opacity(0.7) : .clear, radius: 4)
            Text(clock(perf.startsAt))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.8))
                .frame(width: 46, alignment: .leading)
            TimetableArtistAvatar(name: perf.artistName, url: ArtistAvatarResolver.shared.displayURL(performanceID: perf.id, in: timetable, unlinked: avatars.url(for: perf.artistName)), size: 32)
            Text(perf.artistName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BSColor.Stage.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if let stage = perf.stage {
                HomeLiveStageChip(name: stage.name, index: stageOrder[stage.id] ?? stage.sortOrder, small: true)
            }
        }
        .padding(.vertical, 11)
    }

    private func dayEyebrow(_ day: TimetableDay) -> some View {
        Text("\(BSLocalization.format("DAY %d", dayNumber(day))) · \(monthDay(day.date))")
            .font(.system(size: 11, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(HomeLiveStyle.night)
    }

    private func dayNumber(_ day: TimetableDay) -> Int {
        (timetable.orderedDays.firstIndex { $0.id == day.id } ?? 0) + 1
    }

    private func monthDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
        let parts = calendar.dateComponents([.month, .day], from: date)
        return BSLocalization.format("%d月%d日", parts.month ?? 1, parts.day ?? 1)
    }

    private func remaining(until date: Date, from now: Date, days: Int) -> String {
        if days >= 2 { return BSLocalization.format("还有 %d 天", days) }
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return minutes >= 60
            ? BSLocalization.format("还有 %d 小时 %d 分", minutes / 60, minutes % 60)
            : BSLocalization.format("%d 分钟后", minutes)
    }

    // MARK: - Festival finale

    @ViewBuilder
    private var finale: some View {
        let days = timetable.orderedDays.filter { !$0.performances.isEmpty }
        let pickedDays = days.filter { $0.performances.contains(where: \.isInterested) }
        if let first = days.first, let last = days.last {
            HomeLiveHeroCard(tint: BSColor.Stage.accent) {
                Text(days.count > 1 ? "\(monthDay(first.date)) – \(monthDay(last.date))" : monthDay(first.date))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(BSColor.Stage.accent)
                Text(BSLocalization.text("全部结束"))
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-1)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .padding(.top, 10)
                Text(days.count > 1 ? BSLocalization.format("%d 天辛苦了，下次现场见", days.count) : BSLocalization.text("辛苦了，下次现场见"))
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.Stage.muted)
                    .padding(.top, 8)
                finaleRule.padding(.top, 18)
                if !pickedDays.isEmpty {
                    Text(days.count > 1 ? BSLocalization.format("这 %d 天我想看的", days.count) : BSLocalization.text("我想看的"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                    ForEach(Array(pickedDays.enumerated()), id: \.element.id) { index, day in
                        finaleDayRow(day, isFirst: index == 0, isLast: index == pickedDays.count - 1)
                    }
                    finaleRule.padding(.top, 8)
                }
                HStack(spacing: 0) {
                    finaleStat(icon: "music.note", leading: 0, title: BSLocalization.format("共 %d 天", days.count), detail: BSLocalization.format("%d 场演出", days.reduce(0) { $0 + $1.performances.count }))
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 30)
                    finaleStat(icon: "heart", leading: 16, title: BSLocalization.text("我想看"), detail: BSLocalization.format("%d 场", days.reduce(0) { $0 + $1.performances.filter(\.isInterested).count }))
                }
                .padding(.top, 14)
            }
        }
    }

    private var finaleRule: some View {
        LinearGradient(colors: [BSColor.Stage.accent.opacity(0.3), HomeLiveStyle.night.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
    }

    private func finaleDayRow(_ day: TimetableDay, isFirst: Bool, isLast: Bool) -> some View {
        let picks = day.performances.filter(\.isInterested).sorted(by: TimetablePerformance.chronologicalOrder)
        let shown = picks.count > 5 ? 4 : picks.count
        let rail = BSColor.Stage.accent.opacity(0.35)
        return HStack(spacing: 10) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : rail).frame(width: 1.5)
                Circle()
                    .fill(BSColor.Stage.accent)
                    .frame(width: 9, height: 9)
                    .shadow(color: BSColor.Stage.accent.opacity(0.7), radius: 4)
                Rectangle().fill(isLast ? .clear : rail).frame(width: 1.5)
            }
            .frame(width: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(BSLocalization.format("DAY %d", dayNumber(day)))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(HomeLiveStyle.night)
                Text(monthDay(day.date))
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.dim)
            }
            .frame(width: 64, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(picks.prefix(shown)) { perf in
                    TimetableArtistAvatar(name: perf.artistName, url: ArtistAvatarResolver.shared.displayURL(performanceID: perf.id, in: timetable, unlinked: avatars.url(for: perf.artistName)), size: 34)
                }
                if picks.count > shown {
                    Text("+\(picks.count - shown)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.muted)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.06), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
            }
        }
        .frame(height: 58)
    }

    private func finaleStat(icon: String, leading: CGFloat, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(BSColor.Stage.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(BSColor.Stage.muted)
            }
        }
        .padding(.leading, leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Setlist

    @ViewBuilder
    private func setlist(_ rows: [LivePerformanceSnapshot], alsoLive: [LivePerformanceSnapshot] = []) -> some View {
        if !rows.isEmpty || !alsoLive.isEmpty {
            VStack(spacing: 0) {
                ForEach(alsoLive) { perf in
                    Button { focusedPerformanceID = perf.id.uuidString } label: {
                        setlistRow(perf, isLive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(BSLocalization.text("设为主现场"))
                }
                ForEach(rows) { perf in
                    setlistRow(perf, isLive: false)
                }
            }
            .padding(.top, 18)
        }
    }

    private func setlistRow(_ perf: LivePerformanceSnapshot, isLive: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if isLive {
                    Text(verbatim: "LIVE").foregroundStyle(BSColor.Stage.live)
                } else {
                    Text(clock(perf.startsAt))
                        .foregroundStyle(perf.isStartingSoon ? BSColor.Stage.liveTitle : BSColor.Stage.foreground.opacity(0.75))
                }
            }
            .font(.system(size: 12.5, design: .monospaced))
            .frame(width: 44, alignment: .leading)
            TimetableArtistAvatar(name: perf.artistName, url: ArtistAvatarResolver.shared.displayURL(performanceID: perf.id, in: timetable, unlinked: avatars.url(for: perf.artistName)), size: 28)
            Text(perf.artistName)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(1)
            if perf.isInterested {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(BSColor.Stage.accent)
            }
            Spacer(minLength: 6)
            stageChip(perf, small: true)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: - Pieces

    private func stageChip(_ perf: LivePerformanceSnapshot, small: Bool = false) -> some View {
        HomeLiveStageChip(name: perf.stageName, index: stageOrder[perf.stageID] ?? 0, small: small)
    }

    private var eventCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
        return calendar
    }

    private func clock(_ date: Date) -> String {
        let parts = eventCalendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

enum HomeLiveStyle {
    static let night = Color(red: 0.686, green: 0.765, blue: 0.933)
    static func stageColor(_ index: Int) -> Color { TimetableStageLight.color(index) }
}

struct HomeLiveStageChip: View {
    let name: String
    let index: Int
    var small = false

    var body: some View {
        let color = HomeLiveStyle.stageColor(index)
        HStack(spacing: 6) {
            TimetableStageLight.marker(index).fill(color).frame(width: 7, height: 7)
            Text(name).lineLimit(1)
        }
        .font(.system(size: small ? 10.5 : 11.5, weight: .bold))
        .foregroundStyle(color)
        .padding(.horizontal, small ? 7 : 9)
        .padding(.vertical, small ? 2 : 3)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.32), lineWidth: 1))
    }
}

/// Frosted card with a breathing stage light falling from the top.
struct HomeLiveHeroCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content
    @State private var breathe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [tint.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: 170)
                        .frame(width: 340, height: 360)
                        .offset(x: 70, y: -150)
                        .blendMode(.screen)
                        .opacity(breathe ? 1 : 0.65)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 20)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { breathe = true }
            }
    }
}
