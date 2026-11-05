import SwiftUI

/// "That day" — a candle lit for a whole-year anniversary of an archived show.
struct FootprintCandleView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let anniversary: FootprintAnniversary

    @State private var isLit = true
    @State private var detailTarget: FootprintDetailDestination?

    var body: some View {
        let show = archive.shows(for: [anniversary.showID]).first
        let others = FootprintAnniversaryFinder.sameMonth(as: anniversary, in: archive.shows)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    if let show {
                        polaroid(show)
                            .offset(x: -70, y: -20)
                    }
                    Button {
                        if isLit { FootprintSoundPlayer.shared.play(.breath) }
                        withAnimation(.easeInOut(duration: 1.2)) { isLit.toggle() }
                    } label: {
                        FootprintCandleFigure(isLit: isLit, scale: 1)
                            .frame(width: 110, height: 290)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 80)
                    .accessibilityLabel(isLit ? BSLocalization.text("吹灭蜡烛") : BSLocalization.text("重新点亮蜡烛"))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 330)
                .padding(.top, 20)
                if let show { story(show) }
                if !others.isEmpty { otherAnniversaries(others) }
            }
            .bsAdaptiveContentWidth()
            .padding(.bottom, BSSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .background { room.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { FootprintNavigationTitle(title: BSLocalization.text("那年今日")) } }
        .navigationDestination(item: $detailTarget) { FootprintDetailView(show: $0.show, archive: archive) }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: isLit)
    }

    private var room: some View {
        ZStack {
            FootprintRoomPalette.candleRoom
            RadialGradient(colors: [FootprintRoomPalette.flame.opacity(0.28), FootprintRoomPalette.flameEdge.opacity(0.08), .clear], center: .init(x: 0.62, y: 0.28), startRadius: 0, endRadius: 300)
                .opacity(isLit ? 1 : 0.12)
        }
    }

    private func polaroid(_ show: Show) -> some View {
        Button { detailTarget = FootprintDetailDestination(show: show) } label: {
            VStack(spacing: 6) {
                FootprintResolvedCoverImage(show: show, cover: covers[show.id])
                    .frame(width: 150, height: 200)
                    .clipped()
                Text(String(format: "%02d.%02d", anniversary.month, anniversary.day))
                    .font(.system(size: 16, design: .serif).italic())
                    .foregroundStyle(Color(red: 0.23, green: 0.19, blue: 0.15))
                    .padding(.bottom, 4)
            }
            .padding(8)
            .background(FootprintRoomPalette.wax)
            .overlay {
                // Candlelight falls on the side facing the flame; the photo dims when it goes out.
                LinearGradient(colors: [FootprintRoomPalette.flame.opacity(0.3), .clear], startPoint: .trailing, endPoint: .leading)
                    .blendMode(.softLight)
                    .opacity(isLit ? 1 : 0)
            }
            .overlay { Color.black.opacity(isLit ? 0 : 0.55) }
            .rotationEffect(.degrees(-7), anchor: .bottom)
            .shadow(color: .black.opacity(0.6), radius: 15, y: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(show.name)
    }

    private func story(_ show: Show) -> some View {
        let calendar = show.timingCalendar()
        let parts = calendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
        let ordinal = (FootprintArchiveRankingBuilder.chronological(archive.shows).firstIndex { $0.id == show.id } ?? 0) + 1
        let place = FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) ?? FootprintTextNormalizer.nonEmptyTrimmed(show.city)
        let recollection = place.map {
            BSLocalization.format("%lld 年 %lld 月 %lld 日，%@，%@。那是你的第 %lld 场现场。", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, show.name, $0, ordinal)
        } ?? BSLocalization.format("%lld 年 %lld 月 %lld 日，%@。那是你的第 %lld 场现场。", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, show.name, ordinal)
        let when = anniversary.daysUntil == 0
            ? BSLocalization.text("就是今天")
            : BSLocalization.format("还有 %lld 天", anniversary.daysUntil)
        return VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.format("%@ · %lld 周年 · %@", String(format: "%02d.%02d", anniversary.month, anniversary.day), anniversary.years, when))
                .font(.system(size: 12))
                .tracking(2)
                .foregroundStyle(FootprintRoomPalette.candleGold)
            Text(BSLocalization.format("%lld 年前的那一场", anniversary.years))
                .font(.system(size: 26, weight: .heavy, design: .serif))
                .foregroundStyle(FootprintRoomPalette.candleText)
            Text(recollection)
            .font(.system(size: 14, design: .serif))
            .lineSpacing(8)
            .foregroundStyle(FootprintRoomPalette.candleText.opacity(0.78))
            Text(isLit
                 ? BSLocalization.text("轻点火焰，把它吹灭")
                 : BSLocalization.format("收下了。明年 %@ 再为它点亮", String(format: "%02d.%02d", anniversary.month, anniversary.day)))
                .font(.system(size: 13))
                .foregroundStyle(isLit ? FootprintRoomPalette.candleText.opacity(0.45) : FootprintRoomPalette.candleGold)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private func otherAnniversaries(_ others: [FootprintAnniversary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.text("这个月的其他周年"))
                .font(.system(size: 11))
                .tracking(2)
                .foregroundStyle(FootprintRoomPalette.candleText.opacity(0.45))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(others) { other in
                        if let show = archive.shows(for: [other.showID]).first {
                            Button { detailTarget = FootprintDetailDestination(show: show) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: "%02d.%02d", other.month, other.day))
                                        .font(.system(size: 16, design: .serif))
                                        .foregroundStyle(FootprintRoomPalette.candleText)
                                    Text(BSLocalization.format("%@ · %lld 周年", show.name, other.years))
                                        .font(.system(size: 12))
                                        .foregroundStyle(FootprintRoomPalette.candleText.opacity(0.62))
                                        .lineLimit(1)
                                }
                                .frame(width: 150, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FootprintRoomPalette.flame.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
    }
}

/// Wax, wick and a living flame; blowing it out leaves an ember and a curl of smoke.
struct FootprintCandleFigure: View {
    let isLit: Bool
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            // Wax with two drips.
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.85, green: 0.8, blue: 0.71), FootprintRoomPalette.wax, Color(red: 0.78, green: 0.73, blue: 0.61)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 60 * scale, height: 180 * scale)
                .offset(y: 104 * scale)
            Capsule().fill(FootprintRoomPalette.wax).frame(width: 9 * scale, height: 34 * scale).offset(x: -21 * scale, y: 104 * scale)
            Capsule().fill(FootprintRoomPalette.wax.opacity(0.92)).frame(width: 7 * scale, height: 52 * scale).offset(x: 18 * scale, y: 104 * scale)
            Ellipse().fill(Color(red: 1, green: 0.97, blue: 0.92)).frame(width: 60 * scale, height: 14 * scale).offset(y: 98 * scale)
            Capsule().fill(Color(red: 0.11, green: 0.08, blue: 0.06)).frame(width: 3 * scale, height: 22 * scale).offset(y: 80 * scale)
            if isLit {
                flame.transition(.scale(scale: 0.1, anchor: .bottom).combined(with: .opacity))
            } else {
                FootprintSmoke(isRising: !reduceMotion, scale: scale).offset(y: 20 * scale)
                Circle().fill(FootprintRoomPalette.flameEdge).frame(width: 3 * scale).shadow(color: FootprintRoomPalette.flameEdge, radius: 3).offset(y: 80 * scale)
            }
        }
        .frame(width: 110 * scale, height: 290 * scale, alignment: .top)
        .accessibilityHidden(true)
    }

    private var flame: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let sway = reduceMotion ? 0 : sin(t * 3.1) * 0.04 + sin(t * 7.3) * 0.02
            let stretch = reduceMotion ? 1 : 1 + sin(t * 5.2) * 0.05
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [FootprintRoomPalette.flame.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 50 * scale))
                    .frame(width: 100 * scale, height: 120 * scale)
                    .offset(y: 16 * scale)
                Ellipse()
                    .fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.95, blue: 0.78), FootprintRoomPalette.flame, FootprintRoomPalette.flameEdge.opacity(0)], center: .init(x: 0.5, y: 0.78), startRadius: 0, endRadius: 30 * scale))
                    .frame(width: 24 * scale, height: 58 * scale)
                    .scaleEffect(x: 2 - stretch, y: stretch, anchor: .bottom)
                    .rotationEffect(.radians(sway), anchor: .bottom)
                    // The flame's base sits on the wick tip (80pt down at scale 1).
                    .offset(y: 24 * scale)
            }
        }
    }
}

private struct FootprintSmoke: View {
    let isRising: Bool
    let scale: CGFloat
    @State private var risen = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { puff in
                Circle()
                    .fill(Color(white: 0.85).opacity(0.45))
                    .frame(width: (22 + CGFloat(puff) * 6) * scale, height: (40 + CGFloat(puff) * 6) * scale)
                    .blur(radius: (4 + CGFloat(puff) * 2) * scale)
                    .offset(x: risen ? 14 * scale : 0, y: risen ? -150 * scale : 30 * scale)
                    .scaleEffect(risen ? 2.4 : 0.6)
                    .opacity(risen ? 0 : 0.6)
                    .animation(.easeOut(duration: 3.2 + Double(puff) * 0.4).delay(Double(puff) * 0.3), value: risen)
            }
        }
        .onAppear { if isRising { risen = true } }
    }
}
