import SwiftUI

struct ListeningPreparingView: View {
    let show: Show

    private var artists: [ListeningBrowseArtist] {
        let artists = show.artists.enumerated().map { index, artist in
            ListeningBrowseArtist(
                slotIndex: index, id: artist.appleMusicArtistID ?? "unconnected-\(index)", name: artist.name,
                artworkURL: artist.avatarURL.flatMap(URL.init(string:)),
                appleMusicArtistID: artist.appleMusicArtistID, albums: []
            )
        }
        return artists.filter(\.isConnected) + artists.filter { !$0.isConnected }
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ListeningRoomHeader(mode: .connecting)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BSSpacing.sm) {
                        if !artists.isEmpty {
                            ListeningArtistSelector(artists: artists, selection: .all, select: { _ in }, onConnect: { _, _ in })
                        }
                        ListeningShelfView(title: BSLocalization.text("BeforeShow 热门合辑"), count: BSLocalization.format("%d 张唱片", 0), isLoading: true) {
                            ListeningShelfSkeleton()
                        }
                        .listeningFrame("cabinet")
                        let geometry = CDPlayerConfiguration.standard.geometry
                        let scale = (proxy.size.width - BSSpacing.roomy * 2) * BSListeningTokens.playerWidthFraction / geometry.body.width
                        ListeningPreparingMachineView(scale: scale)
                            .listeningFrame("stage")
                            .frame(maxWidth: .infinity)
                            .padding(.top, -geometry.viewportTop * scale)
                    }
                    .coordinateSpace(name: "listeningContent")
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.sm)
                    .padding(.bottom, BSLayout.tabBarContentInset)
                }
                .scrollDisabled(true)
            }
        }
        .foregroundStyle(BSColor.Stage.foreground)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
    }
}

private struct ListeningPreparingMachineView: View {
    let scale: CGFloat
    private var geometry: CDPlayerConfiguration.Geometry { CDPlayerConfiguration.standard.geometry }
    private var assets: CDPlayerConfiguration.Assets { CDPlayerConfiguration.standard.assets }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(.black.opacity(0.45)).blur(radius: 22)
                .frame(width: 370, height: 130).position(x: 232, y: 679)
            Image(assets.body).resizable()
                .frame(width: geometry.body.width, height: geometry.body.height)
                .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180),
                             anchor: UnitPoint(x: 0.5, y: (geometry.hingeY - geometry.body.minY) / geometry.body.height))
                .position(x: geometry.body.midX, y: geometry.body.midY)
            Image(assets.lidOuter).resizable()
                .frame(width: geometry.lid.width, height: geometry.lid.height)
                .scaleEffect(x: 1, y: cos(geometry.tiltDegrees * .pi / 180), anchor: .top)
                .position(x: geometry.lid.midX, y: geometry.lid.midY)
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.30), .black, Color(white: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Color(white: 0.48), lineWidth: 1).padding(4))
                .overlay(Circle().fill(Color(white: 0.12)).padding(12))
                .frame(width: 42, height: 42)
                .position(x: geometry.discCenter.x, y: geometry.projectedY(geometry.discCenter.y))
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: geometry.canvas.width * scale, height: geometry.canvas.height * scale, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
