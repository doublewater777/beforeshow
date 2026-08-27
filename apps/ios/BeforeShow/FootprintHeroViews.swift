import SwiftUI

// MARK: - Passport Card Hero (暗色现场护照卡片)
struct PassportCardHeroView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Row: Passport Badge
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(BSColor.Stage.accent)
                    Text(BSLocalization.text("LIVE ARCHIVE"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(BSColor.Stage.accent)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.3), lineWidth: 1))

                Spacer()
            }

           // Main Body: Poster Stack + Big Number & Stats
           HStack(alignment: .center, spacing: 18) {
               heroCoverStack
                   .frame(width: 76, height: 94)

               VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(archive.shows.count)")
                            .font(.system(size: 46, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BSColor.Stage.heroIvory, BSColor.Stage.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(BSLocalization.text("场现场"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(BSColor.Stage.muted)
                    }

                   if archive.totalDurationMinutes > 0 {
                       HStack(spacing: 4) {
                           Image(systemName: "clock")
                               .font(.system(size: 10))
                               .foregroundColor(BSColor.Stage.accent)
                           Text(BSLocalization.format("在现场度过 %@", ShowDurationFormatter.aggregate(totalMinutes: archive.totalDurationMinutes)))
                               .font(.system(size: 12, weight: .medium))
                               .foregroundColor(BSColor.Stage.foreground.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                       }
                   }

                    if let topArtist = archive.artists.first {
                        Text(BSLocalization.format("最常看：%@ · %lld 场", topArtist.name, topArtist.count))
                            .font(.system(size: 11))
                            .foregroundColor(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                }
            }

           // Divider & Bottom Stats Row
           Divider().background(BSColor.Stage.border)

           HStack(spacing: 8) {
               passportMetric(value: "\(archive.artists.count)", label: BSLocalization.text("位艺人"))
               passportMetric(value: "\(archive.cities.count)", label: BSLocalization.text("座城市"))
               passportMetric(value: "\(archive.venues.count)", label: BSLocalization.text("个场馆"))
               passportMetric(value: "\(archive.currentYearCount)", label: BSLocalization.text("今年"))
           }
       }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(BSColor.Stage.surface)
                RadialGradient(
                    colors: [BSColor.Stage.accent.opacity(0.12), Color.clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 180
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [BSColor.Stage.accent.opacity(0.35), BSColor.Stage.border.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
    }

   private func passportMetric(value: String, label: String) -> some View {
       HStack(alignment: .firstTextBaseline, spacing: 3) {
           Text(value)
               .font(.system(size: 14, weight: .bold, design: .rounded))
               .foregroundColor(BSColor.Stage.foreground)
           Text(label)
               .font(.system(size: 9.5, weight: .medium))
               .foregroundColor(BSColor.Stage.muted)
       }
       .frame(maxWidth: .infinity)
       .padding(.vertical, 7)
       .background(Color.white.opacity(0.038), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
       .overlay(
           RoundedRectangle(cornerRadius: 10, style: .continuous)
               .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
       )
   }

   private var heroCoverStack: some View {
       ZStack {
           let recentShows = Array(archive.shows.prefix(2))
           if recentShows.isEmpty {
               RoundedRectangle(cornerRadius: 10)
                   .fill(Color.white.opacity(0.06))
                   .overlay(
                       Image(systemName: "music.mic")
                           .foregroundColor(BSColor.Stage.dim)
                   )
                   .frame(width: 70, height: 93)
           } else {
               ForEach(Array(recentShows.enumerated().reversed()), id: \.element.id) { index, show in
                   let isBack = index > 0
                   FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                       .frame(width: 70, height: 93)
                       .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                       .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                       .scaleEffect(isBack ? 0.90 : 1.0)
                       .rotationEffect(.degrees(isBack ? -5 : 0))
                       .offset(x: isBack ? -5 : 0, y: isBack ? -3 : 0)
               }
           }
       }
       .padding(.leading, 6)
       .padding(.trailing, 2)
   }
}
