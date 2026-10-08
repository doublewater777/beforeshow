import SwiftUI

/// Festival body of the home countdown card while live mode is on: one main
/// set, what else is playing at the same time, what is next, and when tomorrow
/// starts. The card chrome and status row stay owned by `HomeCountdownLockup`.
struct HomeLiveTimetableContent: View {
    let state: LiveModeState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The user may promote a parallel set to the main slot; defaults to the engine's first pick.
    @State private var mainID: UUID?

    private var upcoming: [LivePerformanceSnapshot] {
        state.upcomingPerformances.sorted { $0.startsAt < $1.startsAt }
    }

    var body: some View {
        switch state.phase {
        case .active where !state.currentPerformances.isEmpty:
            onStage(state.currentPerformances)
        case .active:
            between
        case .dayEnded(let next):
            dayEnded(next: next)
        case .upcoming(let first):
            beforeFirst(first)
        case .fullyEnded:
            EmptyView()
        }
    }

    // MARK: - On stage

    private func onStage(_ current: [LivePerformanceSnapshot]) -> some View {
        let lead = current.first { $0.id == mainID } ?? current[0]
        let others = current.filter { $0.id != lead.id }
        let total = lead.endsAt.timeIntervalSince(lead.startsAt)
        let progress = total > 0 ? max(0, min(1, 1 - lead.secondsUntilEnd / total)) : 0
        return VStack(alignment: .leading, spacing: 0) {
            names([lead])
            meta(lead.stageName, time: "\(clock(lead.startsAt))–\(clock(lead.endsAt))")

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    HomeLivePulse(reduceMotion: reduceMotion)
                    Text(BSLocalization.text("正在演出"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSColor.Stage.liveTitle)
                }
                Spacer(minLength: 0)
                stat(value: BSLocalization.format("%d 分钟", Int((lead.secondsUntilEnd / 60).rounded(.up))), label: BSLocalization.text("剩余"))
            }
            .padding(.top, 10)

            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule().fill(BSColor.Stage.live).frame(width: geo.size.width * progress)
                    }
            }
            .frame(height: 3)
            .padding(.top, 8)

            if !others.isEmpty {
                parallel(others)
            }
            upcomingRows(Array(upcoming.prefix(2)))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: lead.id)
    }

    /// Other sets on right now. Tapping one makes it the main set.
    private func parallel(_ others: [LivePerformanceSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BSLocalization.text("同时在演"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(BSColor.Stage.dim)
            ForEach(others) { perf in
                Button {
                    mainID = perf.id
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(BSColor.Stage.live.opacity(0.6)).frame(width: 5, height: 5)
                        Text("\(perf.artistName)\(perf.isInterested ? Text("  \(Image(systemName: "heart.fill"))").font(.system(size: 10)).foregroundColor(BSColor.Stage.accent) : Text(""))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(BSColor.Stage.foreground.opacity(0.88))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(perf.stageName)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(BSColor.Stage.dim)
                            .lineLimit(1)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(BSLocalization.text("设为主现场"))
            }
        }
        .padding(.top, 14)
    }

    // MARK: - Between sets

    @ViewBuilder
    private var between: some View {
        if let first = upcoming.first {
            let slot = upcoming.filter { $0.startsAt == first.startsAt }
            let minutes = Int((first.secondsUntilStart / 60).rounded(.up))
            VStack(alignment: .leading, spacing: 0) {
                if minutes < 60 {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(minutes)")
                            .font(.system(size: 72, weight: .ultraLight))
                            .monospacedDigit()
                            .foregroundColor(BSColor.Stage.heroWarmGold)
                            .padding(.vertical, -9)
                        Text(BSLocalization.text("分钟"))
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                    Text(BSLocalization.format("%@ 开演", clock(first.startsAt)))
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(BSColor.Stage.dim)
                        .padding(.top, 10)
                } else {
                    Text(clock(first.startsAt))
                        .font(.system(size: 64, weight: .thin))
                        .monospacedDigit()
                        .foregroundColor(BSColor.Stage.foreground)
                }
                names(slot).padding(.top, 12)
                meta(stages(slot), time: nil)
                upcomingRows(Array(upcoming.dropFirst(slot.count).prefix(2)))
            }
        }
    }

    // MARK: - Before the first set

    private func beforeFirst(_ first: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(clock(first))
                .font(.system(size: 64, weight: .thin))
                .monospacedDigit()
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("首场开演"))
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
                .padding(.top, 6)
            upcomingRows(Array(upcoming.prefix(2)))
        }
    }

    // MARK: - Day ended

    private func dayEnded(next: Date?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(FestivalDay.word(for: next, distance: FestivalDay.distance(from: Date(), to: next, calendar: .current), calendar: .current))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSColor.Stage.muted)
                    Text(clock(next))
                        .font(.system(size: 44, weight: .light))
                        .monospacedDigit()
                        .foregroundColor(BSColor.Stage.foreground)
                }
            }
            if let opener = upcoming.first {
                Text("\(opener.artistName) · \(opener.stageName)")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(BSColor.Stage.dim)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Pieces

    private func names(_ performances: [LivePerformanceSnapshot]) -> some View {
        let joined = performances.enumerated().reduce(Text("")) { text, element in
            element.offset == 0
                ? Text("\(text)\(element.element.artistName)")
                : Text("\(text)\(Text(" ／ ").fontWeight(.light).foregroundColor(BSColor.Stage.accent))\(element.element.artistName)")
        }
        return joined
            .font(.system(size: 22, weight: .semibold))
            .tracking(-0.45)
            .foregroundColor(BSColor.Stage.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func meta(_ stages: String, time: String?) -> some View {
        Text([stages, time].compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 12.5, weight: .regular))
            .monospacedDigit()
            .foregroundColor(BSColor.Stage.muted)
            .padding(.top, 5)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.3)
                .foregroundColor(BSColor.Stage.foreground)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
        }
    }

    @ViewBuilder
    private func upcomingRows(_ rows: [LivePerformanceSnapshot]) -> some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                Rectangle().fill(BSColor.Stage.border).frame(height: 1)
                    .padding(.top, 12)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, perf in
                    if index > 0 {
                        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                    }
                    upcomingRow(perf)
                }
            }
        }
    }

    private func upcomingRow(_ perf: LivePerformanceSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(clock(perf.startsAt))
                .font(.system(size: 12.5, weight: .regular))
                .monospacedDigit()
                .foregroundColor(BSColor.Stage.muted)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(perf.artistName)\(perf.isInterested ? Text("  \(Image(systemName: "heart.fill"))").font(.system(size: 10)).foregroundColor(BSColor.Stage.accent) : Text(""))")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if perf.isStartingSoon {
                    HStack(spacing: 5) {
                        Circle().strokeBorder(BSColor.Stage.live, lineWidth: 1.5).frame(width: 6, height: 6)
                        Text(BSLocalization.format("%d 分钟后", Int((perf.secondsUntilStart / 60).rounded(.up))))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(BSColor.Stage.liveTitle)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(perf.stageName)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(1)
        }
        .padding(.vertical, 9)
    }

    private func stages(_ performances: [LivePerformanceSnapshot]) -> String {
        var seen = Set<String>()
        return performances.map(\.stageName).filter { seen.insert($0).inserted }.joined(separator: " · ")
    }

    private func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
