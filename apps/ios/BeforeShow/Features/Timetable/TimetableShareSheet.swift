import SwiftUI

/// Share a plan, not a screenshot: "我的想看" lays every day's picks on one
/// timeline; "完整时刻表" stacks every day's stage grid. One light sheet, then
/// the system share sheet.
struct TimetableShareSheet: View {
    enum Mode: Hashable { case picks, full }

    let timetable: Timetable
    let show: Show?
    let avatarURL: (String) -> URL?

    @State private var mode: Mode
    @State private var images: [Mode: Image] = [:]
    @Environment(\.dismiss) private var dismiss
    @Namespace private var knob

    init(timetable: Timetable, show: Show?, avatarURL: @escaping (String) -> URL?) {
        self.timetable = timetable
        self.show = show
        self.avatarURL = avatarURL
        let hasPicks = timetable.orderedDays.contains { $0.performances.contains(where: \.isInterested) }
        _mode = State(initialValue: hasPicks ? .picks : .full)
    }

    private var hasPicks: Bool {
        timetable.orderedDays.contains { $0.performances.contains(where: \.isInterested) }
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(BSLocalization.text("分享"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(TimetableStyle.foreground)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TimetableStyle.foreground)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.07), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.text("关闭"))
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            modePicker
                .padding(.horizontal, 20)
                .padding(.top, 14)

            ScrollView(showsIndicators: false) {
                Group {
                    if let image = images[mode] {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08)))
                            .shadow(color: .black.opacity(0.7), radius: 30, y: 24)
                    } else {
                        ProgressView().tint(TimetableStyle.muted).frame(height: 420)
                    }
                }
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }

            Group {
                if let image = images[mode] {
                    ShareLink(item: image, preview: SharePreview(previewTitle, image: image)) { shareLabel }
                } else {
                    shareLabel.opacity(0.35)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(TimetableStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationBackground(TimetableStyle.background)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: mode)
        .task(id: mode) { await render(mode) }
    }

    private var previewTitle: String {
        let what = BSLocalization.text(mode == .picks ? "我的想看" : "完整时刻表")
        return show.map { "\($0.name) · \(what)" } ?? what
    }

    // MARK: - Picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            segment(.picks, tint: TimetableStyle.mine) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.system(size: 12))
                    Text(BSLocalization.text("我的想看"))
                }
            }
            .disabled(!hasPicks)
            .opacity(hasPicks ? 1 : 0.35)
            segment(.full, tint: TimetableStyle.foreground) {
                Text(BSLocalization.text("完整时刻表"))
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func segment<Label: View>(_ value: Mode, tint: Color, @ViewBuilder label: () -> Label) -> some View {
        Button {
            withAnimation(TimetableStyle.pressSpring) { mode = value }
        } label: {
            label()
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(mode == value ? TimetableStyle.background : TimetableStyle.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if mode == value {
                        Capsule().fill(tint).matchedGeometryEffect(id: "knob", in: knob)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }

    private var shareLabel: some View {
        Label(BSLocalization.text("分享"), systemImage: "square.and.arrow.up")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(TimetableStyle.background)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(TimetableStyle.foreground))
    }

    // MARK: - Rendering

    /// Images must be in memory before rendering; the renderer does not wait for loads.
    private func render(_ mode: Mode) async {
        guard images[mode] == nil else { return }
        let days = timetable.orderedDays
        let performers = days.flatMap(\.performances).filter { mode == .full || $0.isInterested }
        var urls = Set(performers.compactMap { avatarURL($0.artistName) })
        if let cover = show?.coverImageURL.flatMap(URL.init(string:)) { urls.insert(cover) }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { _ = await ShowCoverImageCache.shared.image(from: url) }
            }
        }
        // Only hand over avatars that actually loaded; a failed one falls back to
        // the initial instead of a blank placeholder baked into the image.
        let avatarURL = self.avatarURL
        let loadedAvatar: (String) -> URL? = { name in
            avatarURL(name).flatMap { ShowCoverImageCache.shared.memoryImage(for: $0) == nil ? nil : $0 }
        }

        let identity = TimetableShareIdentity(name: show?.name ?? "", coverURL: show?.coverImageURL)
        let content: AnyView
        switch mode {
        case .picks:
            content = AnyView(TimetablePicksPoster(identity: identity, days: days, avatarURL: loadedAvatar, timeZone: timeZone))
        case .full:
            content = AnyView(TimetableFullPoster(identity: identity, days: days, avatarURL: loadedAvatar, timeZone: timeZone))
        }
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark))
        // Every day stacked gets long; keep very long festivals to a sane bitmap.
        renderer.scale = mode == .full && days.count > 2 ? 2 : 3
        images[mode] = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

enum TimetableDayItems {
    static func make(_ days: [TimetableDay], timeZone: TimeZone, now: Date = .now) -> [TimetableDaySwitcher.Item] {
        days.enumerated().map { index, day in
            let start = day.performances.map(\.startsAt).min() ?? day.date
            let end = day.performances.map(\.endsAt).max() ?? day.date
            return .init(
                id: day.id,
                label: BSLocalization.format("第%d天", index + 1),
                date: shortDate(day.date, timeZone: timeZone),
                isToday: start <= now && now < end
            )
        }
    }

    static func shortDate(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    /// 「10月6日 – 10月7日」
    static func longRange(_ days: [TimetableDay], timeZone: TimeZone) -> String {
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        let start = longDate(first, timeZone: timeZone, weekday: false)
        let end = longDate(last, timeZone: timeZone, weekday: false)
        return start == end ? start : "\(start) – \(end)"
    }

    /// 「10月6日 周二」
    static func longDate(_ date: Date, timeZone: TimeZone, weekday: Bool = true) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.month, .day], from: date)
        let text = BSLocalization.format("%d月%d日", parts.month ?? 1, parts.day ?? 1)
        guard weekday else { return text }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return "\(text) \(formatter.string(from: date))"
    }
}

// MARK: - Shared pieces

struct TimetableShareIdentity {
    let name: String
    let coverURL: String?
}

/// Small cover + festival name: the cover is identity, never the background.
private struct TimetableShareHeader: View {
    let identity: TimetableShareIdentity
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ShowCoverImageView(
                urlString: identity.coverURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                enforcesAspectRatio: false,
                cornerRadius: 8,
                restoresPersistedImageOnFirstFrame: true
            )
            .frame(width: 36, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(identity.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TimetableStyle.foreground)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(TimetableStyle.muted)
            }
        }
    }
}

private struct TimetableShareDayHeader: View {
    let number: Int
    let date: Date
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 10) {
            Text(BSLocalization.format("DAY %d", number))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(TimetableStyle.night)
            Text(TimetableDayItems.longDate(date, timeZone: timeZone))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TimetableStyle.dim)
            LinearGradient(colors: [TimetableStyle.night.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
    }
}

private struct TimetableShareFooter: View {
    let summary: Text

    var body: some View {
        VStack(spacing: 16) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack {
                summary
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TimetableStyle.muted)
                Spacer()
                HStack(spacing: 8) {
                    Capsule().fill(BSColor.brandGradient).frame(width: 18, height: 3)
                    Text("BeforeShow")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(TimetableStyle.muted)
                }
            }
        }
    }
}

private struct TimetableShareStageLine: View {
    let stage: TimetableStage?
    let range: String

    var body: some View {
        let index = stage?.sortOrder ?? 0
        let color = TimetableStageLight.color(index)
        HStack(spacing: 6) {
            TimetableStageLight.marker(index).fill(color).frame(width: 7, height: 7)
            Text(stage?.name ?? "")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color)
            Text("· \(range)")
                .font(TimetableStyle.mono(11))
                .foregroundStyle(TimetableStyle.dim)
        }
        .lineLimit(1)
    }
}

// MARK: - 我的想看

/// Every day's picks on one timeline. Picks whose times overlap share a time
/// node and say so, which is the part friends actually reply to.
struct TimetablePicksPoster: View {
    let identity: TimetableShareIdentity
    let days: [TimetableDay]
    let avatarURL: (String) -> URL?
    let timeZone: TimeZone

    private struct Group: Identifiable {
        let id: UUID
        let start: Date
        let picks: [TimetablePerformance]
    }

    private struct Section: Identifiable {
        let id: UUID
        let number: Int
        let day: TimetableDay
        let groups: [Group]
    }

    private var sections: [Section] {
        days.enumerated().compactMap { index, day in
            let picks = day.performances.filter(\.isInterested).sorted { $0.startsAt < $1.startsAt }
            guard !picks.isEmpty else { return nil }
            return Section(id: day.id, number: index + 1, day: day, groups: Self.groups(picks))
        }
    }

    private static func groups(_ picks: [TimetablePerformance]) -> [Group] {
        var groups: [Group] = []
        var current: [TimetablePerformance] = []
        var groupEnd = Date.distantPast
        for pick in picks {
            if !current.isEmpty && pick.startsAt >= groupEnd {
                groups.append(Group(id: current[0].id, start: current[0].startsAt, picks: current))
                current = []
            }
            current.append(pick)
            groupEnd = max(groupEnd, pick.endsAt)
        }
        if !current.isEmpty { groups.append(Group(id: current[0].id, start: current[0].startsAt, picks: current)) }
        return groups
    }

    private var picks: [TimetablePerformance] { days.flatMap { $0.performances.filter(\.isInterested) } }

    var body: some View {
        let stageCount = Set(picks.compactMap { $0.stage?.name }).count
        VStack(alignment: .leading, spacing: 0) {
            TimetableShareHeader(identity: identity, subtitle: TimetableDayItems.longRange(days, timeZone: timeZone))

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(BSLocalization.text("我的想看"))
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.9)
                    .foregroundStyle(TimetableStyle.foreground)
                Image(systemName: "heart.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(TimetableStyle.mine)
            }
            .padding(.top, 22)

            ForEach(sections) { section in
                TimetableShareDayHeader(number: section.number, date: section.day.date, timeZone: timeZone)
                    .padding(.top, 26)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(section.groups.enumerated()), id: \.element.id) { index, group in
                        groupRow(group, isFirst: index == 0, isLast: index == section.groups.count - 1)
                    }
                }
                .padding(.top, 6)
            }

            TimetableShareFooter(
                summary: Text("\(Text("\(picks.count)").foregroundStyle(TimetableStyle.mine).fontWeight(.bold)) \(Text(BSLocalization.format("场想看 · %d 个舞台", stageCount)))")
            )
            .padding(.top, 22)
        }
        .padding(EdgeInsets(top: 26, leading: 24, bottom: 22, trailing: 24))
        .frame(width: 360, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                TimetableStyle.background
                RadialGradient(colors: [TimetableStyle.mine.opacity(0.2), .clear], center: .top, startRadius: 0, endRadius: 260)
                    .frame(height: 380)
                    .offset(y: -60)
            }
        }
    }

    private func groupRow(_ group: Group, isFirst: Bool, isLast: Bool) -> some View {
        let rail = TimetableStyle.mine.opacity(0.28)
        return HStack(alignment: .top, spacing: 10) {
            Text(TimetableTimeFormat.time(group.start, timeZone: timeZone))
                .font(TimetableStyle.mono(13, weight: .semibold))
                .foregroundStyle(TimetableStyle.foreground)
                .frame(width: 44, height: 30, alignment: .leading)
                .padding(.vertical, 10)
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : rail).frame(width: 1.5, height: 20)
                Circle()
                    .fill(TimetableStyle.mine)
                    .frame(width: 10, height: 10)
                    .shadow(color: TimetableStyle.mine.opacity(0.7), radius: 4)
                Rectangle().fill(isLast ? .clear : rail).frame(width: 1.5).frame(maxHeight: .infinity)
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(group.picks, id: \.id) { pick in
                    pickRow(pick)
                }
                if group.picks.count > 1 {
                    Text(BSLocalization.text("时间重叠"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(TimetableStyle.muted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .padding(.leading, 40)
                }
            }
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pickRow(_ pick: TimetablePerformance) -> some View {
        HStack(alignment: .top, spacing: 10) {
            TimetableArtistAvatar(name: pick.artistName, url: avatarURL(pick.artistName), size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(TimetableStyle.mine)
                    Text(pick.artistName)
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(TimetableStyle.foreground)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TimetableShareStageLine(
                    stage: pick.stage,
                    range: TimetableTimeFormat.range(pick.startsAt, pick.endsAt, timeZone: timeZone)
                )
            }
            .padding(.top, 5)
        }
    }
}

// MARK: - 完整时刻表

/// Every day's stage grid, stacked and re-laid for an image: tighter scale, no app
/// chrome, no "now". Picks keep their gold tint and heart.
struct TimetableFullPoster: View {
    let identity: TimetableShareIdentity
    let days: [TimetableDay]
    let avatarURL: (String) -> URL?
    let timeZone: TimeZone

    private static let width: CGFloat = 390
    private static let ruler: CGFloat = 40
    private static let laneGap: CGFloat = 5
    private static let capHeight: CGFloat = 30

    private struct DaySection: Identifiable {
        let id: UUID
        let number: Int
        let day: TimetableDay
    }

    private var sections: [DaySection] {
        days.enumerated().compactMap { index, day in
            day.performances.isEmpty ? nil : DaySection(id: day.id, number: index + 1, day: day)
        }
    }

    var body: some View {
        let all = days.flatMap(\.performances)
        let picks = all.filter(\.isInterested).count
        VStack(alignment: .leading, spacing: 0) {
            TimetableShareHeader(identity: identity, subtitle: TimetableDayItems.longRange(days, timeZone: timeZone))

            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.text("完整时刻表"))
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.9)
                    .foregroundStyle(TimetableStyle.foreground)
                Spacer()
                if picks > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill").font(.system(size: 10))
                        Text(BSLocalization.text("我想看"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TimetableStyle.mine)
                }
            }
            .padding(.top, 20)

            ForEach(sections) { section in
                TimetableShareDayHeader(number: section.number, date: section.day.date, timeZone: timeZone)
                    .padding(.top, 26)
                grid(section.day)
                    .padding(.top, 12)
            }

            TimetableShareFooter(
                summary: Text("\(Text(BSLocalization.format("共 %d 天", sections.count))) · \(Text("\(all.count)").foregroundStyle(TimetableStyle.foreground).fontWeight(.bold)) \(Text(BSLocalization.text("场演出")))\(picks > 0 ? Text(" · \(Text("\(picks)").foregroundStyle(TimetableStyle.mine).fontWeight(.bold)) \(Text(BSLocalization.text("场想看")))") : Text(""))")
            )
            .padding(.top, 22)
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 22, trailing: 20))
        .frame(width: Self.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                TimetableStyle.background
                RadialGradient(colors: [TimetableStyle.night.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 260)
                    .frame(height: 380)
                    .offset(y: -60)
            }
        }
    }

    private func grid(_ day: TimetableDay) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let stages = day.orderedStages
        let layout = TimetableMatrixLayout(
            stages: stages.map { stage in
                .init(id: stage.id, name: stage.name, performances: stage.performances.map {
                    .init(id: $0.id, artistName: $0.artistName, startsAt: $0.startsAt, endsAt: $0.endsAt, isInterested: $0.isInterested)
                })
            },
            now: .distantPast,
            calendar: calendar,
            pointsPerMinute: 1.7
        )
        let count = CGFloat(max(stages.count, 1))
        let gridWidth = Self.width - 40
        let lane = (gridWidth - Self.ruler - Self.laneGap * (count - 1)) / count

        return ZStack(alignment: .topLeading) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                let x = Self.ruler + CGFloat(index) * (lane + Self.laneGap)
                let color = TimetableStageLight.color(stage.sortOrder)
                HStack(spacing: 6) {
                    TimetableStageLight.marker(stage.sortOrder).fill(color).frame(width: 7, height: 7)
                    Text(stage.name).lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color)
                .frame(width: lane, height: Self.capHeight)
                .background(color.opacity(0.12), in: UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
                .offset(x: x)
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                    .fill(TimetableStyle.lane)
                    .frame(width: lane, height: layout.laneHeight)
                    .offset(x: x, y: Self.capHeight)
            }
            ForEach(layout.hours, id: \.date) { mark in
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: gridWidth - Self.ruler, height: 1)
                    .offset(x: Self.ruler, y: Self.capHeight + mark.y)
                Text(TimetableTimeFormat.time(mark.date, timeZone: timeZone))
                    .font(TimetableStyle.mono(10))
                    .foregroundStyle(mark.isMidnight ? TimetableStyle.night : TimetableStyle.dim)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: Self.ruler - 6, alignment: .trailing)
                    .offset(y: Self.capHeight + mark.y - 6)
            }
            ForEach(layout.cards) { card in
                cell(card, width: lane - 6)
                    .frame(width: lane - 6, height: max(card.height - 1, 18), alignment: .topLeading)
                    .offset(x: Self.ruler + CGFloat(card.laneIndex) * (lane + Self.laneGap) + 3, y: Self.capHeight + card.top + 2)
            }
        }
        .frame(width: gridWidth, height: Self.capHeight + layout.laneHeight, alignment: .topLeading)
    }

    /// Avatar above the name on tall cards, beside it on short wide ones, and text
    /// only where an avatar would squeeze the name.
    private func cell(_ card: TimetableMatrixLayout.Card, width: CGFloat) -> some View {
        let height = max(card.height - 1, 18)
        let stacked = height >= 63
        let inline = !stacked && height >= 30 && width >= 110
        let showsTime = height >= 41
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 0) {
                    TimetableArtistAvatar(name: card.artistName, url: avatarURL(card.artistName), size: 18)
                    cellName(card, lines: height >= 77 ? 2 : 1, clearsHeart: false)
                        .padding(.top, 4)
                    cellTime(card).padding(.top, 2)
                }
            } else if inline {
                HStack(alignment: .top, spacing: 6) {
                    TimetableArtistAvatar(name: card.artistName, url: avatarURL(card.artistName), size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        cellName(card, lines: height >= 55 ? 2 : 1, clearsHeart: card.isInterested)
                        if showsTime { cellTime(card) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    cellName(card, lines: height >= 55 ? 2 : 1, clearsHeart: card.isInterested)
                    if showsTime { cellTime(card) }
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, height < 30 ? 3 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(card.isInterested ? TimetableStyle.cardMine : TimetableStyle.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if card.isInterested {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(TimetableStyle.mine)
                    .padding(7)
            }
        }
    }

    private func cellName(_ card: TimetableMatrixLayout.Card, lines: Int, clearsHeart: Bool) -> some View {
        Text(card.artistName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(TimetableStyle.foreground)
            .lineLimit(lines)
            .padding(.trailing, clearsHeart ? 12 : 0)
    }

    private func cellTime(_ card: TimetableMatrixLayout.Card) -> some View {
        Text(TimetableTimeFormat.range(card.startsAt, card.endsAt, timeZone: timeZone))
            .font(TimetableStyle.mono(9.5))
            .foregroundStyle(TimetableStyle.dim)
            .lineLimit(1)
    }
}
