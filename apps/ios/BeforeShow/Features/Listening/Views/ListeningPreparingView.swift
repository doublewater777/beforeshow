import SwiftUI

/// The overview's own layout while the catalog loads, so arriving content settles in place.
struct ListeningPreparingView: View {
    let show: Show

    private var names: [ListeningPosterName] {
        var seen = Set<String>()
        return show.artists.map(\.name).filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { ListeningPosterName(id: $0, name: $0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: BSSpacing.xl) {
                    Color.clear.frame(height: BSLayout.minTouchTarget + BSLayout.pageHeaderTopPadding)
                    ListeningPosterLayout(show: show, names: names)
                    VStack(alignment: .leading, spacing: BSSpacing.md) {
                        Text(ListeningCopy.text("帮我挑一张")).font(ListeningOverviewStyle.sectionTitle)
                        RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: ListeningOverviewStyle.pickCover + BSSpacing.md * 2)
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                    VStack(alignment: .leading, spacing: BSSpacing.md) {
                        Text(ListeningCopy.text("本场歌单")).font(ListeningOverviewStyle.sectionTitle)
                            .padding(.horizontal, BSSpacing.roomy)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: BSSpacing.sm) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                        .frame(width: ListeningOverviewStyle.playlistTile.width,
                                               height: ListeningOverviewStyle.playlistTile.height)
                                }
                            }
                            .padding(.horizontal, BSSpacing.roomy)
                        }
                        .scrollDisabled(true)
                    }
                }
                .padding(.bottom, BSSpacing.xl)
            }
            .scrollClipDisabled()
            .scrollDisabled(true)

            ListeningRoomHeader(mode: .connecting)
        }
        .bsAdaptiveContentWidth()
        .foregroundStyle(BSColor.Stage.foreground)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
    }
}
