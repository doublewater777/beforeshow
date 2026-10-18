import SwiftUI

struct OnboardingWidgetFeatureVisual: View {
    @State private var showStart = Date.now.addingTimeInterval(2 * 3600 + 14 * 60 + 36)
    private let showName = BSLocalization.text("「夜航」巡演 · 上海站")

    var body: some View {
        VStack(spacing: BSSpacing.compact) {
            mediumWidget
            liveActivity
            reminder
        }
        .frame(maxWidth: 330)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            BSLocalization.text("小组件显示现场倒计时，锁屏实时活动倒数开场，开场前会在重要节点提醒")
        )
    }

    // 对齐 CountdownWidgetViews.MediumCountdownView 的 far 态。
    private var mediumWidget: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(BSLocalization.text("距离开场"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(BSColor.Stage.muted)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "3")
                        .font(.system(size: 44, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(BSColor.Stage.heroIvory)
                    Text(BSLocalization.text("天"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BSColor.Stage.muted)
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(showName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(1)
                    Text(BSLocalization.text("10月14日 19:30 · 回声剧场"))
                        .font(.system(size: 10))
                        .foregroundStyle(BSColor.Stage.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("default_cover")
                .resizable()
                .scaledToFill()
                .frame(width: 81, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .frame(height: 150)
        .background {
            ZStack {
                BSColor.Stage.background
                RadialGradient(
                    colors: [BSColor.Stage.glowBlue.opacity(0.38), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 180
                )
                RadialGradient(
                    colors: [BSColor.Stage.accent.opacity(0.22), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 160
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BSColor.Stage.border))
        .shadow(color: .black.opacity(0.30), radius: 26, y: 14)
    }

    // 对齐 ShowLiveActivity.LiveActivityBannerView 的开场前态。
    private var liveActivity: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(BSLocalization.text("距离开场"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.muted)
                Text(showStart, style: .timer)
                    .font(.system(size: 21, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(BSColor.Stage.heroWarmGold)
            }
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(showName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(
                    BSLocalization.format(
                        "%1$@ · %2$@",
                        BSLocalization.format("%@ 开场", "19:30"),
                        BSLocalization.text("回声剧场")
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(BSColor.Stage.muted)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            ZStack {
                Color.black.opacity(0.72)
                RadialGradient(
                    colors: [BSColor.Stage.accent.opacity(0.22), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 200
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BSColor.Stage.border))
    }

    private var reminder: some View {
        HStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(BSLocalization.text("准备这场"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Text(
                    BSLocalization.format("还有 %lld 天。", Int64(3))
                        + BSLocalization.format("先听听 %@ 的歌。", BSLocalization.text("夜航"))
                )
                .font(.system(size: 9))
                .foregroundStyle(BSColor.Stage.muted)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(BSColor.Stage.surfaceRaised.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
        .shadow(color: .black.opacity(0.24), radius: 18, y: 9)
    }
}

struct OnboardingTimetableFeatureVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct MockSet: Identifiable {
        let id: Int
        let lane: Int
        let artist: String
        let start: Double
        let end: Double
        var isInterested = false
    }

    private let stages = ["主舞台", "星空舞台"]
    private let sets = [
        MockSet(id: 0, lane: 0, artist: "回声乐队", start: 19.0, end: 19.75),
        MockSet(id: 1, lane: 0, artist: "夜航", start: 20.0, end: 21.0, isInterested: true),
        MockSet(id: 2, lane: 0, artist: "Lumen", start: 21.25, end: 22.25),
        MockSet(id: 3, lane: 1, artist: "雾港", start: 19.5, end: 20.25),
        MockSet(id: 4, lane: 1, artist: "白日梦", start: 20.75, end: 21.75)
    ]
    private let firstHour = 19.0
    private let now = 20.6
    private let hourHeight: CGFloat = 76
    private let rulerWidth: CGFloat = 36
    private let laneGap: CGFloat = 6
    private let headerHeight: CGFloat = 34

    var body: some View {
        GeometryReader { proxy in
            let laneWidth = (proxy.size.width - rulerWidth - laneGap) / CGFloat(stages.count)
            ZStack(alignment: .topLeading) {
                ForEach(stages.indices, id: \.self) { index in
                    header(stages[index], index: index)
                        .frame(width: laneWidth, height: headerHeight)
                        .offset(x: laneX(index, laneWidth))
                }
                ForEach(0..<4) { hour in
                    Text(String(format: "%02d:00", Int(firstHour) + hour))
                        .font(TimetableStyle.mono(9, weight: .medium))
                        .foregroundStyle(TimetableStyle.dim)
                        .offset(y: y(firstHour + Double(hour)) - 5)
                }
                ForEach(sets) { item in
                    card(item)
                        .frame(width: laneWidth, height: y(item.end) - y(item.start) - 4)
                        .offset(x: laneX(item.lane, laneWidth), y: y(item.start))
                }
                nowLine(width: proxy.size.width)
                    .offset(y: y(now))
            }
        }
        .frame(height: headerHeight + hourHeight * 3.5)
        .padding(14)
        .frame(maxWidth: 304)
        .background(TimetableStyle.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(BSColor.Stage.border))
        .shadow(color: .black.opacity(0.32), radius: 28, y: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("时刻表按舞台显示，正在演夜航"))
    }

    private func laneX(_ lane: Int, _ laneWidth: CGFloat) -> CGFloat {
        rulerWidth + CGFloat(lane) * (laneWidth + laneGap)
    }

    private func y(_ hour: Double) -> CGFloat {
        headerHeight + CGFloat(hour - firstHour) * hourHeight
    }

    private func isLive(_ item: MockSet) -> Bool {
        (item.start..<item.end).contains(now)
    }

    private func header(_ name: String, index: Int) -> some View {
        HStack(spacing: 6) {
            TimetableStageLight.marker(index)
                .fill(TimetableStageLight.color(index))
                .frame(width: 7, height: 7)
            Text(BSLocalization.text(key: name))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TimetableStyle.foreground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 8)
    }

    private func card(_ item: MockSet) -> some View {
        let live = isLive(item)
        let ended = item.end <= now
        let tint = TimetableStageLight.color(item.lane)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(item.artist)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ended ? TimetableStyle.dim : TimetableStyle.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.isInterested {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(TimetableStyle.mine)
                }
            }
            Text(String(format: "%02d:%02d", Int(item.start), Int((item.start.truncatingRemainder(dividingBy: 1) * 60).rounded())))
                .font(TimetableStyle.mono(9, weight: .medium))
                .foregroundStyle(live ? TimetableStyle.nowSoft : TimetableStyle.dim)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            (item.isInterested ? TimetableStyle.cardMine : TimetableStyle.card)
                .overlay(live ? tint.opacity(0.12) : .clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(live ? tint.opacity(0.85) : Color.white.opacity(0.08), lineWidth: live ? 1.5 : 1)
        )
        .phaseAnimator(live && !reduceMotion ? [false, true] : [false]) { content, glowing in
            content.shadow(color: live ? tint.opacity(glowing ? 0.6 : 0.3) : .clear, radius: glowing ? 14 : 6)
        } animation: { _ in .easeInOut(duration: 1.2) }
    }

    private func nowLine(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: "20:36")
                .font(TimetableStyle.mono(8.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(TimetableStyle.now))
                .shadow(color: TimetableStyle.now.opacity(0.6), radius: 4)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, beat in
                    content.scaleEffect(beat ? 1.1 : 1)
                } animation: { _ in .easeInOut(duration: 1) }
            Rectangle()
                .fill(TimetableStyle.now)
                .frame(height: 1.5)
        }
        .frame(width: width)
        .offset(y: -7)
    }
}

struct OnboardingMemoryFeatureVisual: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emojiLanded = false
    private let selectedRating = DispersalRating.golden

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            HStack(spacing: 10) {
                photoTile
                textTile
            }

            ratingCard
        }
        .frame(maxWidth: 304)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            BSLocalization.text("记忆碎片包含照片和文字，散场评价当前选择人上人，明显高于预期")
        )
        .task(id: isActive) {
            guard isActive else {
                emojiLanded = false
                return
            }
            guard !reduceMotion else {
                emojiLanded = true
                return
            }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                emojiLanded = true
            }
        }
    }

    private var photoTile: some View {
        VStack(spacing: 0) {
            Image("default_cover")
                .resizable()
                .scaledToFill()
                .frame(height: 148)
                .clipped()
            memoryMetadata(kind: BSLocalization.text("照片"), time: "20:48")
        }
        .frame(maxWidth: .infinity)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
    }

    private var textTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("“")
                .font(.custom("Songti SC", size: 24, relativeTo: .headline))
                .foregroundStyle(BSColor.Stage.accent)
            Text(BSLocalization.text("最后一首歌结束的时候，灯亮得特别慢。"))
                .font(.system(size: 11))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineSpacing(4)
                .padding(.top, 7)
            Spacer(minLength: 0)
            memoryMetadata(kind: BSLocalization.text("文字"), time: "22:06")
                .padding(.horizontal, -12)
                .padding(.bottom, -12)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 184)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
    }

    private func memoryMetadata(kind: String, time: String) -> some View {
        HStack {
            Text(kind)
            Spacer()
            Text(time)
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundStyle(BSColor.Stage.dim)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.black.opacity(0.18))
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text(selectedRating.emoji)
                    .font(.system(size: 27))
                    .scaleEffect(emojiLanded ? 1 : 0.4)
                    .opacity(emojiLanded ? 1 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedRating.label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selectedRating.tint)
                    Text(selectedRating.sub)
                        .font(.system(size: 8.5))
                        .foregroundStyle(BSColor.Stage.dim)
                }
            }

            HStack(spacing: 0) {
                ForEach(DispersalRating.allCases) { rating in
                    let selected = rating == selectedRating
                    VStack(spacing: 3) {
                        Circle()
                            .fill(selected ? rating.tint : Color(red: 0.165, green: 0.188, blue: 0.251))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(selected ? rating.tint : Color.white.opacity(0.14), lineWidth: 1.5))
                        Text(rating.emoji)
                            .font(.system(size: 12))
                            .grayscale(selected ? 0 : 0.75)
                            .opacity(selected ? 1 : 0.55)
                        Text(rating.label)
                            .font(.system(size: 7.5, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? BSColor.Stage.foreground : BSColor.Stage.dim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 3)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    .zIndex(-1)
            }
        }
        .padding(14)
        .background(BSColor.Stage.surfaceRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(BSColor.Stage.border))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
    }
}

struct OnboardingStartFeatureVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(BSColor.Stage.glowBlue.opacity(0.16))
                .frame(width: 210, height: 210)
                .blur(radius: 45)
            Circle()
                .fill(BSColor.Stage.accent.opacity(0.12))
                .frame(width: 150, height: 150)
                .offset(x: 62, y: 45)
                .blur(radius: 42)

            VStack(alignment: .leading, spacing: 0) {
                Text(BSLocalization.text("距离开场"))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(BSColor.Stage.muted)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("--")
                        .font(.system(size: 43, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.heroIvory.opacity(0.42))
                    Text(BSLocalization.text("天"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BSColor.Stage.dim)
                }
                .padding(.top, 10)
                Spacer(minLength: 5)
                Text(BSLocalization.text("你的下一场"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.muted)
            }
            .padding(16)
            .frame(maxWidth: 320, alignment: .leading)
            .frame(height: 150)
            .background(BSColor.Stage.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(BSColor.Stage.accent)
                    .frame(width: 44, height: 44)
                    .background(BSColor.Stage.accent.opacity(0.12), in: Circle())
                    .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, beat in
                        content.scaleEffect(beat ? 1.12 : 1).opacity(beat ? 0.75 : 1)
                    } animation: { _ in .easeInOut(duration: 0.9) }
                    .padding(.trailing, 22)
            }
        }
        .accessibilityHidden(true)
    }
}
