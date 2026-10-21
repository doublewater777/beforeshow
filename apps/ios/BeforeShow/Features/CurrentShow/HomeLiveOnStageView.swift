import SwiftUI

struct HomeLiveOnStageView: View {
    let lead: LivePerformanceSnapshot
    let others: [LivePerformanceSnapshot]
    let timetable: Timetable
    let avatars: TimetableArtistAvatarStore
    let stageOrder: [UUID: Int]
    let onSelect: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        let total = lead.endsAt.timeIntervalSince(lead.startsAt)
        return total > 0 ? max(0, min(1, 1 - lead.secondsUntilEnd / total)) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeLiveHeroCard(tint: BSColor.Stage.live) {
                ZStack(alignment: .topLeading) {
                    heroContent
                        .id(lead.id)
                        .transition(reduceMotion ? .identity : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8))
                                .animation(.easeOut(duration: 0.2).delay(0.06)),
                            removal: .opacity.combined(with: .offset(y: -6))
                                .animation(.easeOut(duration: 0.1))
                        ))
                }
            }
            if !others.isEmpty {
                HStack(spacing: 10) {
                    Text(BSLocalization.text("同时在演"))
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(BSColor.Stage.dim)
                    LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1)
                }
                .padding(.top, 26)
                HStack(spacing: 10) {
                    // Stable slots keep outgoing and incoming tiles at the same width.
                    ForEach(Array(others.prefix(2).enumerated()), id: \.offset) { _, perf in
                        ZStack(alignment: .topLeading) {
                            Button { onSelect(perf.id) } label: {
                                parallelTile(perf)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(BSLocalization.text("设为主现场"))
                            .id(perf.id)
                            .transition(reduceMotion ? .identity : .asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.06)),
                                removal: .opacity.animation(.easeOut(duration: 0.1))
                            ))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(BSColor.Stage.live, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: BSColor.Stage.live.opacity(0.7), radius: 6)
                    TimetableArtistAvatar(name: lead.artistName, url: ArtistAvatarResolver.shared.displayURL(performanceID: lead.id, in: timetable, unlinked: avatars.url(for: lead.artistName)), size: 76)
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TimetableEqualizer()
                        Text(BSLocalization.text("正在演出"))
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(BSColor.Stage.liveTitle)
                    }
                    HStack(spacing: 8) {
                        stageChip(lead)
                        Text("\(clock(lead.startsAt))–\(clock(lead.endsAt))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(BSColor.Stage.muted)
                    }
                }
            }
            Text(lead.artistName)
                .font(.system(size: 32, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(BSColor.Stage.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int((lead.secondsUntilEnd / 60).rounded(.up)))")
                    .font(.system(size: 44, weight: .light, design: .monospaced))
                    .tracking(-1.5)
                    .foregroundStyle(BSColor.Stage.foreground)
                Text(BSLocalization.text("分钟后结束"))
                    .font(.system(size: 15))
                    .foregroundStyle(BSColor.Stage.muted)
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
    }

    private func parallelTile(_ perf: LivePerformanceSnapshot) -> some View {
        let color = HomeLiveStyle.stageColor(stageOrder[perf.stageID] ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                TimetableArtistAvatar(name: perf.artistName, url: ArtistAvatarResolver.shared.displayURL(performanceID: perf.id, in: timetable, unlinked: avatars.url(for: perf.artistName)), size: 40)
                Spacer()
                TimetableEqualizer()
            }
            Text(perf.artistName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BSColor.Stage.foreground)
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

    private func stageChip(_ perf: LivePerformanceSnapshot, small: Bool = false) -> some View {
        HomeLiveStageChip(name: perf.stageName, index: stageOrder[perf.stageID] ?? 0, small: small)
    }

    private func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timetable.timeZoneIdentifier) ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
