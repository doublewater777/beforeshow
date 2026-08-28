import SwiftUI

// MARK: - Passport Card Hero (暗色现场护照卡片)
struct PassportCardHeroView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            HStack(alignment: .center, spacing: BSSpacing.roomy) {
                heroCoverStack
                    .frame(width: 84, height: 108)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(archive.shows.count)")
                            .font(.system(size: 54, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(BSColor.Stage.accent)
                        Text(BSLocalization.text("场现场"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(BSColor.Stage.foreground)
                    }

                    if archive.totalDurationMinutes > 0 {
                        Text(BSLocalization.format("在现场度过 %@", ShowDurationFormatter.aggregate(totalMinutes: archive.totalDurationMinutes)))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(BSColor.Stage.foreground.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    if let topArtist = archive.artists.first {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(BSColor.Stage.accent)
                            Text(BSLocalization.format("最常看 · %@", topArtist.name))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(BSColor.Stage.accent)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: BSSpacing.sm) {
                passportMetric(
                    value: "\(archive.artists.count)",
                    label: BSLocalization.text("位艺人"),
                    systemName: "person"
                )
                passportMetric(
                    value: "\(archive.cities.count)",
                    label: BSLocalization.text("座城市"),
                    systemName: "mappin"
                )
                passportMetric(
                    value: "\(archive.venues.count)",
                    label: BSLocalization.text("个场馆"),
                    systemName: "building.2"
                )
            }
        }
        .padding(BSSpacing.roomy)
        .background(heroBackground)
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [BSColor.Stage.accent.opacity(0.42), BSColor.Stage.border, BSColor.Stage.glowBlue.opacity(0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.34), radius: 18, x: 0, y: 10)
    }

    private var heroBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RadialGradient(
                colors: [BSColor.Stage.accent.opacity(0.20), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 190
            )
            RadialGradient(
                colors: [BSColor.Stage.glowBlue.opacity(0.13), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 220
            )
            GeometryReader { proxy in
                Circle()
                    .stroke(BSColor.Stage.accent.opacity(0.07), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.72)
                    .offset(x: proxy.size.width * 0.57, y: -proxy.size.width * 0.34)
                Circle()
                    .stroke(BSColor.Stage.glowBlue.opacity(0.06), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.56)
                    .offset(x: -proxy.size.width * 0.26, y: proxy.size.height * 0.58)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous))
    }

    private var heroCoverStack: some View {
        ZStack {
            let recentShows = Array(archive.shows.prefix(2))
            if recentShows.isEmpty {
                archiveTicket
                    .frame(width: 76, height: 104)
            } else {
                ForEach(Array(recentShows.enumerated().reversed()), id: \.element.id) { index, show in
                    let isBack = index > 0
                    FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                        .frame(width: 78, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                                .stroke(BSColor.Stage.accent.opacity(isBack ? 0.12 : 0.28), lineWidth: 0.75)
                        )
                        .shadow(color: .black.opacity(0.46), radius: 9, x: 0, y: 5)
                        .scaleEffect(isBack ? 0.90 : 1.0)
                        .rotationEffect(.degrees(isBack ? -6 : 0))
                        .offset(x: isBack ? -6 : 0, y: isBack ? -4 : 0)
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
    }

    /// 系统生成的档案票根：没有封面时作为现场档案的识别元素。
    private var archiveTicket: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 1) {
                Text("LIVE")
                Text("ARCHIVE")
            }
            .font(.system(size: 8, weight: .bold))
            .tracking(1.5)
            .foregroundColor(BSColor.Stage.accent)

            Rectangle()
                .fill(BSColor.Stage.accent.opacity(0.25))
                .frame(height: 0.5)

            Text(String(format: "%03d", archive.shows.count))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(BSColor.Stage.accent)

            Text(String(Calendar.current.component(.year, from: Date())))
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(BSColor.Stage.accent.opacity(0.6))

            Spacer(minLength: 0)

            ticketBarcode
        }
        .padding(9)
        .background(
            LinearGradient(
                colors: [BSColor.Stage.surface, BSColor.Stage.surfaceRaised.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(BSColor.Stage.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        )
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        .accessibilityHidden(true)
    }

    private var ticketBarcode: some View {
        let widths: [CGFloat] = [2, 1, 3, 1, 1, 2, 1, 3, 1, 2, 1, 2]
        return HStack(spacing: 1.5) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                Rectangle()
                    .fill(BSColor.Stage.heroIvory.opacity(0.5))
                    .frame(width: width, height: 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func passportMetric(value: String, label: String, systemName: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BSColor.Stage.dim)
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(BSColor.Stage.accent)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(BSColor.Stage.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}
