import SwiftUI

// MARK: - Home hero presentation
//
// One module owns the phase+timeState pair that every hero helper used to thread
// as two arguments. Callers pass a single `HomeHeroSnapshot`; HomeShowPhase stays
// in Shared for widget/countdown reuse, but the home poster derives it here.

/// Derivation surface for the home poster: time-state copy + phase, from one `now`.
struct HomeHeroSnapshot: Equatable {
    let timeState: CurrentShowTimeState
    let phase: HomeShowPhase
    let now: Date

    init(show: Show, now: Date, calendar: Calendar = .current) {
        self.now = now
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        self.timeState = state
        self.phase = HomeShowPhase(timeState: state, now: now)
    }

    init(timeState: CurrentShowTimeState, now: Date) {
        self.now = now
        self.timeState = timeState
        self.phase = HomeShowPhase(timeState: timeState, now: now)
    }
}

/// 3:4 cover poster on the home stage: glow, kicker, date line, title, location.
struct HomeHeroStage: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    let coverWidth: CGFloat
    var reduceMotion: Bool = false

    private var coverHeight: CGFloat { coverWidth * 4.0 / 3.0 }
    private var phase: HomeShowPhase { snapshot.phase }
    private var timeState: CurrentShowTimeState { snapshot.timeState }

    var body: some View {
        heroVisual(width: coverWidth, height: coverHeight)
        .accessibilityLabel("现场封面，\(show.name)")
        .accessibilityAddTraits(.isImage)
        .frame(width: coverWidth, height: coverHeight)
    }

    private func heroVisual(width: CGFloat, height: CGFloat) -> some View {
        ShowCoverImageView(
            urlString: show.coverImageURL,
            aspectRatio: 3.0 / 4.0,
            contentMode: .fill,
            alignment: .center,
            enforcesAspectRatio: false,
            cornerRadius: 26
        )
        .frame(width: width, height: height)
        .saturation(phase == .inactive ? 0.35 : (phase == .ended ? 0.72 : 1.0))
        .brightness(phase == .inactive ? -0.18 : (phase == .ended ? -0.05 : 0))
        .overlay {
            heroScrim
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .overlay {
            heroGlow(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .overlay(alignment: .bottomLeading) {
            heroMeta
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        // ShowCoverImageView 先按自身比例布局；外层改成固定 3:4 尺寸后必须再次裁切，
        // 否则图片会越过 352pt 卡片边界，让海报看起来横向错位。
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, y: 15)
    }

    /// V4 hero-scrim:顶部更轻,底部 97% 收进封面下缘,让元信息可读。
    private var heroScrim: some View {
        LinearGradient(
            stops: [
                .init(color: BSColor.Stage.background.opacity(0.18), location: 0.00),
                .init(color: BSColor.Stage.background.opacity(0.06), location: 0.26),
                .init(color: BSColor.Stage.background.opacity(0.10), location: 0.46),
                .init(color: BSColor.Stage.background.opacity(0.44), location: 0.66),
                .init(color: BSColor.Stage.background.opacity(0.86), location: 0.88),
                .init(color: BSColor.Stage.background.opacity(0.97), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// hero-glow:蓝 / 紫两束舞台侧光,screen 混合;live 全开,ended 收半,inactive 几近熄灭。
    private func heroGlow(width: CGFloat, height: CGFloat) -> some View {
        let opacity: Double
        switch phase {
        case .live: opacity = 1.0
        case .pre: opacity = 0.92
        case .ended: opacity = 0.45
        case .inactive: opacity = 0.18
        }
        return ZStack {
            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Stage.glowBlue.opacity(0.30), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.26
                ))
                .frame(width: width * 0.52, height: height * 0.34)
                .position(x: width * 0.16, y: height * 0.70)

            Ellipse()
                .fill(RadialGradient(
                    colors: [BSColor.Stage.prepare.opacity(0.28), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.23
                ))
                .frame(width: width * 0.46, height: height * 0.28)
                .position(x: width * 0.88, y: height * 0.62)
        }
        .blendMode(.screen)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    private var heroMeta: some View {
        VStack(alignment: .leading, spacing: 0) {
            kickerPill
                .padding(.bottom, 10)

            Text(dateLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BSColor.Stage.foreground.opacity(0.78))
                .padding(.bottom, 8)

            Text(show.name)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.6)
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 4)

            if !locationText.isEmpty {
                Text(locationText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(BSColor.Stage.foreground.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private var kickerPill: some View {
        let text = phase == .inactive
            ? timeState.title
            : phase.kickerText(city: show.city, timeState: timeState)
        return HStack(spacing: 8) {
            if phase == .live {
                HomeLivePulse(reduceMotion: reduceMotion)
            } else {
                Circle()
                    .fill(kickerDotColor)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
        }
        .foregroundColor(kickerTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(kickerTint))
        )
        .overlay(Capsule().stroke(kickerBorderColor, lineWidth: 1))
    }

    private var kickerDotColor: Color {
        switch phase {
        case .pre: return BSColor.Stage.accent
        case .live: return BSColor.Stage.live
        case .ended, .inactive: return BSColor.Stage.dim
        }
    }

    private var kickerTextColor: Color {
        switch phase {
        case .pre: return BSColor.Stage.accent
        case .live: return BSColor.Stage.liveTitle
        case .ended, .inactive: return BSColor.Stage.foreground.opacity(0.72)
        }
    }

    private var kickerTint: Color {
        switch phase {
        case .pre: return BSColor.Stage.background.opacity(0.38)
        case .live: return Color(red: 0.31, green: 0.09, blue: 0.13).opacity(0.42)
        case .ended, .inactive: return BSColor.Stage.background.opacity(0.45)
        }
    }

    private var kickerBorderColor: Color {
        switch phase {
        case .pre: return BSColor.Stage.accent.opacity(0.28)
        case .live: return BSColor.Stage.live.opacity(0.42)
        case .ended, .inactive: return Color.white.opacity(0.14)
        }
    }

    /// 海报 event-date 行:「yyyy.MM.dd 周X HH:mm」,填了结束时间再补「预计演出 X 小时 Y 分」;
    /// 没填结束时间不估值、不显示时长。多日每日循环展示「yyyy.MM.dd-MM.dd · 每日 HH:mm[-HH:mm]」。
    private var dateLine: String {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "zh_Hans_CN")
        dayFormatter.dateFormat = "yyyy.MM.dd E"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_Hans_CN")
        timeFormatter.dateFormat = "HH:mm"

        if CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: calendar),
           let endDay = CurrentShowTimeState.effectiveEndDate(for: show, calendar: calendar) {
            var daily = timeFormatter.string(from: show.startTime)
            if let endTime = show.endTime {
                daily += "-\(timeFormatter.string(from: endTime))"
            }
            let year = calendar.component(.year, from: show.effectiveDate)
            return "\(year).\(Self.monthDayText(show.effectiveDate, calendar: calendar))-\(Self.monthDayText(endDay, calendar: calendar)) · 每日 \(daily)"
        }

        let base = "\(dayFormatter.string(from: show.effectiveDate)) \(timeFormatter.string(from: show.startTime))"
        guard let start = timeState.effectiveStartTime,
              let end = timeState.effectiveEndTime, end > start else {
            return base
        }
        let minutes = Int(end.timeIntervalSince(start)) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        let duration: String
        if hours > 0 && rest > 0 {
            duration = "\(hours) 小时 \(rest) 分"
        } else if hours > 0 {
            duration = "\(hours) 小时"
        } else {
            duration = "\(max(1, rest)) 分钟"
        }
        return "\(base) · 预计演出 \(duration)"
    }

    private static func monthDayText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d", components.month ?? 0, components.day ?? 0)
    }

    private var locationText: String {
        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityText = {
            guard let city, !city.isEmpty else { return nil as String? }
            guard let venue, !venue.localizedCaseInsensitiveContains(city) else { return nil as String? }
            return city
        }()

        return [
            venue,
            cityText
        ]
        .compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: " · ")
    }
}
