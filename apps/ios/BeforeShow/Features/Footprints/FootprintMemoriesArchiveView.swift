import Foundation
import SwiftUI

private struct FootprintMemoryYearGroup: Identifiable {
    let year: Int
    let shows: [Show]
    var id: Int { year }
}

struct FootprintMemoriesArchiveView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void

    private var memoryShows: [Show] {
        archive.shows.filter { covers[$0.id]?.badge == .memory }
    }

    var body: some View {
        FootprintArchivePage(title: BSLocalization.text("全部回忆"), kicker: "", shareCovers: covers) { isForExport in
            if memoryShows.isEmpty {
                emptyState
            } else {
                headerHero
                let visible = isForExport
                    ? FootprintExportContentPolicy.prefix(
                        memoryShows,
                        limit: FootprintExportContentPolicy.memoriesPageLimit
                    )
                    : memoryShows
                let left = Array(visible.enumerated().filter { $0.offset % 2 == 0 })
                let right = Array(visible.enumerated().filter { $0.offset % 2 != 0 })

                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(left, id: \.element.id) { index, show in
                            let isTall = index % 3 == 0
                            footprintExportAwareNavigationLink(isForExport: isForExport) {
                                FootprintDetailView(
                                    show: show,
                                    archive: archive,
                                    onDetailVisibilityChange: onDetailVisibilityChange
                                )
                            } label: {
                                FootprintMemoryCard(
                                    show: show,
                                    cover: covers[show.id],
                                    index: index + 1,
                                    isTall: isTall
                                )
                            }
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(right, id: \.element.id) { index, show in
                            let isTall = index % 3 == 0
                            footprintExportAwareNavigationLink(isForExport: isForExport) {
                                FootprintDetailView(
                                    show: show,
                                    archive: archive,
                                    onDetailVisibilityChange: onDetailVisibilityChange
                                )
                            } label: {
                                FootprintMemoryCard(
                                    show: show,
                                    cover: covers[show.id],
                                    index: index + 1,
                                    isTall: isTall
                                )
                            }
                        }
                    }
                }
                .padding(.top, 12)
                if isForExport {
                    footprintExportRemainingCaption(
                        total: memoryShows.count,
                        limit: FootprintExportContentPolicy.memoriesPageLimit,
                        style: .memories
                    )
                }
            }
        }
    }

    private var headerHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(memoryShows.count))
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("场回忆"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BSColor.Stage.muted)
            }
            Text(BSLocalization.text("照片和视频都留在对应的那一晚里。这里按时间把它们重新铺开。"))
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.muted)
                .lineSpacing(3)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(BSColor.Stage.dim)
            Text(BSLocalization.text("暂无回忆"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("散场后留下照片或视频记忆，在这里筑造你的现场回忆。"))
                .font(.system(size: 12))
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border))
    }
}

struct FootprintMemoryCard: View {
    let show: Show
    let cover: FootprintCover?
    var index: Int? = nil
    var isTall: Bool = false

    private var calendar: Calendar { show.timingCalendar() }

    private var memoryTagText: String {
        if let cover, cover.badge == .memory {
            return BSLocalization.text(cover.isVideoMemory ? "视频" : "照片")
        }
        return BSLocalization.text(show.dynamicCover != nil ? "视频" : "照片")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FootprintCoverView(show: show, cover: cover, showsMetadata: false)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.35),
                    .init(color: Color.black.opacity(0.3), location: 0.60),
                    .init(color: Color.black.opacity(0.78), location: 0.84),
                    .init(color: Color.black.opacity(0.94), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.04), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    if let index {
                        Text(String(format: "%02d", index))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.55))
                            .tracking(1)
                    } else {
                        Text(footprintEnhancementFullDateText(show.effectiveDate, calendar: calendar))
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(BSColor.Stage.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.black.opacity(0.48), in: Capsule())
                            .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.32), lineWidth: 0.5))
                    }

                    Spacer(minLength: 0)

                    Text(memoryTagText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(show.name)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .lineSpacing(1.5)
                        .shadow(color: Color.black.opacity(0.8), radius: 4, x: 0, y: 2)

                    Text(footprintEnhancementFullDateText(show.effectiveDate, calendar: calendar))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(11)
        }
        .frame(height: isTall ? 240 : 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}
