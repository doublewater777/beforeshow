import SwiftUI

/// Bold live mode for the current tab: once a festival timetable is live, the
/// cover collapses into the header and this view takes over the page.
struct HomeLiveModeView: View {
    let show: Show
    let timetable: Timetable
    let state: LiveModeState
    var onEndShow: (() -> Void)?
    let onOpenTimetable: () -> Void

    @State private var mainID: UUID?
    @State private var avatars = TimetableArtistAvatarStore()
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
            case .upcoming(let first):
                startsAt(first, label: BSLocalization.text("今日首场"), tint: BSColor.Stage.accent, opener: upcoming.first)
                setlist(Array(upcoming.dropFirst().prefix(3)))
            case .dayEnded(let next):
                dayEnded(next)
            case .fullyEnded:
                finale
            }

            if state.phase == .fullyEnded, let onEndShow {
                Button(action: onEndShow) {
                    Text(BSLocalization.text("结束现场"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(BSColor.Stage.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            LinearGradient(colors: [BSColor.Stage.accent.opacity(0.16), BSColor.Stage.accent.opacity(0.07)], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BSColor.Stage.accent.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
                Button(action: onOpenTimetable) {
                    HStack(spacing: 5) {
                        Text(BSLocalization.text("完整时刻表"))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                Button(action: onOpenTimetable) {
                    HStack(spacing: 6) {
                        Text(BSLocalization.text("完整时刻表"))
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [BSColor.Stage.accent.opacity(0.16), BSColor.Stage.accent.opacity(0.07)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BSColor.Stage.accent.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }
        }
        // Breathing room under the header's identity thumbnail.
        .padding(.top, 14)
        .task(id: timetable.id) {
            let names = timetable.orderedDays.flatMap(\.performances).map(\.artistName)
            await avatars.load(artistNames: names, lineup: show.artists)
        }
    }

    // MARK: - On stage

    @ViewBuilder
    private var onStage: some View {
        let current = state.currentPerformances
        let lead = current.first { $0.id == mainID } ?? current[0]
        let others = current.filter { $0.id != lead.id }
        let total = lead.endsAt.timeIntervalSince(lead.startsAt)
        let progress = total > 0 ? max(0, min(1, 1 - lead.secondsUntilEnd / total)) : 0

        HomeLiveHeroCard(tint: BSColor.Stage.live) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(BSColor.Stage.live, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: BSColor.Stage.live.opacity(0.7), radius: 6)
                    TimetableArtistAvatar(name: lead.artistName, url: avatars.url(for: lead.artistName), size: 76)
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TimetableEqualizer()
                        Text(BSLocalization.text("正在演出"))
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1)
                            .foregroundColor(BSColor.Stage.liveTitle)
                    }
                    HStack(spacing: 8) {
                        stageChip(lead)
                        Text("\(clock(lead.startsAt))–\(clock(lead.endsAt))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                }
            }
            Text(lead.artistName)
                .font(.system(size: 32, weight: .heavy))
                .tracking(-0.8)
                .foregroundColor(BSColor.Stage.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int((lead.secondsUntilEnd / 60).rounded(.up)))")
                    .font(.system(size: 44, weight: .light, design: .monospaced))
                    .tracking(-1.5)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("分钟后结束"))
                    .font(.system(size: 15))
                    .foregroundColor(BSColor.Stage.muted)
            }
            .padding(.top, 18)
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [BSColor.Stage.live.opacity(0.4), BSColor.Stage.live], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progress)
                            .shadow(color: BSColor.Stage.live.opacity(0.8), radius: 5)
                    }
            }
            .frame(height: 3)
            .padding(.top, 12)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: lead.id)

        if !others.isEmpty {
            sectionLabel(BSLocalization.text("同时在演"))
            HStack(spacing: 10) {
                ForEach(others.prefix(2)) { perf in
                    Button { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { mainID = perf.id } } label: {
                        parallelTile(perf)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(BSLocalization.text("设为主现场"))
                }
            }
            .padding(.top, 12)
        }
        setlist(Array(upcoming.prefix(3)))
    }

    private func parallelTile(_ perf: LivePerformanceSnapshot) -> some View {
        let color = HomeLiveStyle.stageColor(stageOrder[perf.stageID] ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                TimetableArtistAvatar(name: perf.artistName, url: avatars.url(for: perf.artistName), size: 40)
                Spacer()
                TimetableEqualizer()
            }
            Text(perf.artistName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Spacer(minLength: 8)
            stageChip(perf, small: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            LinearGradient(colors: [color.opacity(0.18), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(color.opacity(0.26), lineWidth: 1))
    }

    // MARK: - Between sets

    @ViewBuilder
    private var between: some View {
        if let first = upcoming.first {
            let slot = upcoming.filter { $0.startsAt == first.startsAt }
            HomeLiveHeroCard(tint: BSColor.Stage.heroWarmGold) {
                Text(BSLocalization.text("下一场"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundColor(BSColor.Stage.heroWarmGold)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int((first.secondsUntilStart / 60).rounded(.up)))")
                        .font(.system(size: 96, weight: .ultraLight, design: .monospaced))
                        .tracking(-5)
                        .foregroundColor(BSColor.Stage.heroWarmGold)
                        .shadow(color: BSColor.Stage.heroWarmGold.opacity(0.35), radius: 20)
                    Text(BSLocalization.text("分钟"))
                        .font(.system(size: 18))
                        .foregroundColor(BSColor.Stage.muted)
                    Spacer()
                    Text(clock(first.startsAt))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(BSColor.Stage.muted)
                }
                .padding(.top, 4)
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(slot.prefix(2).enumerated()), id: \.element.id) { index, perf in
                        if index > 0 {
                            Rectangle().fill(BSColor.Stage.accent.opacity(0.25)).frame(width: 1)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            TimetableArtistAvatar(name: perf.artistName, url: avatars.url(for: perf.artistName), size: 48)
                            Text(perf.artistName)
                                .font(.system(size: 19, weight: .heavy))
                                .foregroundColor(BSColor.Stage.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            stageChip(perf, small: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 18)
            }
            setlist(Array(upcoming.dropFirst(slot.count).prefix(3)))
        }
    }

    // MARK: - Before the first set / day ended

    private func startsAt(_ date: Date?, label: String, tint: Color, opener: LivePerformanceSnapshot?) -> some View {
        HomeLiveHeroCard(tint: tint) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundColor(tint)
            if let date {
                Text(clock(date))
                    .font(.system(size: 84, weight: .ultraLight, design: .monospaced))
                    .tracking(-5)
                    .foregroundColor(BSColor.Stage.foreground)
                    .shadow(color: tint.opacity(0.35), radius: 20)
                    .padding(.top, 6)
            }
            if let opener {
                HStack(spacing: 10) {
                    TimetableArtistAvatar(name: opener.artistName, url: avatars.url(for: opener.artistName), size: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(opener.artistName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(BSColor.Stage.foreground)
                        stageChip(opener, small: true)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Day ended

    @ViewBuilder
    private func dayEnded(_ next: Date?) -> some View {
        let now = Date()
        let calendar = Calendar.current
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
                    .foregroundColor(HomeLiveStyle.night)
                Text(BSLocalization.format("DAY %d 已结束", dayNumber(ended)))
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(BSColor.Stage.foreground)
                    .padding(.top, 8)
                Text(BSLocalization.format(since == 0 ? "今天辛苦了，%@继续" : since == 1 ? "昨天辛苦了，%@继续" : "辛苦了，%@继续", resumes))
                    .font(.system(size: 14))
                    .foregroundColor(BSColor.Stage.muted)
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
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer(minLength: 8)
                    Text(remaining(until: next, from: now, days: ahead))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BSColor.Stage.muted)
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
                .foregroundColor(BSColor.Stage.foreground.opacity(0.8))
                .frame(width: 46, alignment: .leading)
            TimetableArtistAvatar(name: perf.artistName, url: avatars.url(for: perf.artistName), size: 32)
            Text(perf.artistName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
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
            .foregroundColor(HomeLiveStyle.night)
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
                    .foregroundColor(BSColor.Stage.accent)
                Text(BSLocalization.text("全部结束"))
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-1)
                    .foregroundColor(BSColor.Stage.foreground)
                    .padding(.top, 10)
                Text(days.count > 1 ? BSLocalization.format("%d 天辛苦了，下次现场见", days.count) : BSLocalization.text("辛苦了，下次现场见"))
                    .font(.system(size: 14))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.top, 8)
                finaleRule.padding(.top, 18)
                if !pickedDays.isEmpty {
                    Text(days.count > 1 ? BSLocalization.format("这 %d 天我想看的", days.count) : BSLocalization.text("我想看的"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(BSColor.Stage.foreground)
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
                    .foregroundColor(HomeLiveStyle.night)
                Text(monthDay(day.date))
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.dim)
            }
            .frame(width: 64, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(picks.prefix(shown)) { perf in
                    TimetableArtistAvatar(name: perf.artistName, url: avatars.url(for: perf.artistName), size: 34)
                }
                if picks.count > shown {
                    Text("+\(picks.count - shown)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BSColor.Stage.muted)
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
                .foregroundColor(BSColor.Stage.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
            }
        }
        .padding(.leading, leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Setlist

    @ViewBuilder
    private func setlist(_ rows: [LivePerformanceSnapshot]) -> some View {
        if !rows.isEmpty {
            sectionLabel(BSLocalization.text("接下来"))
            VStack(spacing: 0) {
                ForEach(rows) { perf in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(perf.isInterested && !perf.isStartingSoon ? BSColor.Stage.accent : BSColor.Stage.background)
                            .overlay(Circle().strokeBorder(perf.isStartingSoon ? BSColor.Stage.live : (perf.isInterested ? .clear : Color.white.opacity(0.25)), lineWidth: perf.isStartingSoon ? 2 : 1.5))
                            .frame(width: 11, height: 11)
                            .shadow(color: perf.isStartingSoon ? BSColor.Stage.live.opacity(0.7) : (perf.isInterested ? BSColor.Stage.accent.opacity(0.7) : .clear), radius: 4)
                        Text(clock(perf.startsAt))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(BSColor.Stage.foreground.opacity(0.8))
                            .frame(width: 46, alignment: .leading)
                        TimetableArtistAvatar(name: perf.artistName, url: avatars.url(for: perf.artistName), size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(perf.artistName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(BSColor.Stage.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            if perf.isStartingSoon {
                                Text(BSLocalization.format("%d 分钟后", Int((perf.secondsUntilStart / 60).rounded(.up))))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(BSColor.Stage.liveTitle)
                            }
                        }
                        Spacer(minLength: 6)
                        stageChip(perf, small: true)
                    }
                    .padding(.vertical, 11)
                }
            }
            .background(alignment: .leading) {
                LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                    .frame(width: 1.5)
                    .padding(.leading, 4.75)
                    .padding(.vertical, 16)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Pieces

    private func sectionLabel(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundColor(BSColor.Stage.dim)
            LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .padding(.top, 26)
    }

    private func stageChip(_ perf: LivePerformanceSnapshot, small: Bool = false) -> some View {
        HomeLiveStageChip(name: perf.stageName, index: stageOrder[perf.stageID] ?? 0, small: small)
    }

    private func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
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
        .foregroundColor(color)
        .padding(.horizontal, small ? 7 : 9)
        .padding(.vertical, small ? 2 : 3)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.32), lineWidth: 1))
    }
}

/// Frosted card with a breathing stage light falling from the top.
private struct HomeLiveHeroCard<Content: View>: View {
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

/// The cover, blurred into a stage-light backdrop behind the live page.
struct HomeLiveBackdrop: View {
    let show: Show

    var body: some View {
        // Colour.clear owns the size; the cover only paints inside it, so a large
        // image can never widen the page.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 560)
            .overlay {
                ShowCoverImageView(
                    urlString: show.coverImageURL,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fill,
                    alignment: .center,
                    enforcesAspectRatio: false,
                    cornerRadius: 0,
                    restoresPersistedImageOnFirstFrame: true
                )
                .blur(radius: 48)
                .saturation(1.3)
                .opacity(0.8)
            }
            .clipped()
            .overlay(LinearGradient(colors: [BSColor.Stage.background.opacity(0.35), BSColor.Stage.background.opacity(0.75), BSColor.Stage.background], startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.6), location: 0.45), .init(color: .clear, location: 0.9)], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
