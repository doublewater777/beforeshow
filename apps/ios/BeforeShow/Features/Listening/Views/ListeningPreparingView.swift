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
                    VStack(spacing: BSSpacing.xs) {
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
                            .padding(.top, -(geometry.viewportTop + BSListeningTokens.stageTopOffset) * scale)
                        Color.clear.frame(height: BSListeningTokens.songHeight)
                   }
                    .coordinateSpace(name: "listeningContent")
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.sm)
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(.black.opacity(0.45))
                .blur(radius: 22)
                .frame(width: 370, height: 130)
                .position(x: 232, y: 679)

            RoundedRectangle(cornerRadius: 34)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.26, blue: 0.24),
                            Color(red: 0.13, green: 0.13, blue: 0.14),
                            Color(red: 0.20, green: 0.18, blue: 0.17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34)
                        .stroke(.white.opacity(0.11), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 31)
                        .stroke(BSColor.Stage.accent.opacity(0.16), lineWidth: 1)
                        .padding(3)
                )
                .frame(width: geometry.body.width, height: geometry.body.height)
                .scaleEffect(
                    x: 1,
                    y: cos(geometry.tiltDegrees * .pi / 180),
                    anchor: UnitPoint(
                        x: 0.5,
                        y: (geometry.hingeY - geometry.body.minY) / geometry.body.height
                    )
                )
                .position(x: geometry.body.midX, y: geometry.body.midY)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.30, green: 0.28, blue: 0.26),
                            Color(red: 0.15, green: 0.145, blue: 0.15),
                            Color(red: 0.075, green: 0.075, blue: 0.085)
                        ],
                        center: .topLeading,
                        startRadius: 18,
                        endRadius: geometry.lid.width * 0.58
                    )
                )
                .overlay(
                    Ellipse()
                        .stroke(BSColor.Stage.accent.opacity(0.24), lineWidth: 2)
                        .padding(2)
                )
                .overlay(
                    Ellipse()
                        .stroke(.white.opacity(0.11), lineWidth: 1)
                        .padding(7)
                )
                .frame(
                    width: geometry.lid.width,
                    height: geometry.lid.height * cos(geometry.tiltDegrees * .pi / 180)
                )
                .position(
                    x: geometry.lid.midX,
                    y: geometry.projectedY(geometry.lid.midY)
                )

            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.026, green: 0.052, blue: 0.061),
                            Color(red: 0.012, green: 0.018, blue: 0.022)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .frame(width: geometry.lcd.width, height: geometry.lcd.height)
                .position(x: geometry.lcd.midX, y: geometry.projectedY(geometry.lcd.midY))

            ForEach(CDControl.allCases) { control in
                if let rect = geometry.controls[control] {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(control == .playPause ? 0.13 : 0.08),
                                    Color.black.opacity(0.46)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle().stroke(
                                control == .playPause
                                    ? BSColor.Stage.accent.opacity(0.44)
                                    : Color.white.opacity(0.12),
                                lineWidth: control == .playPause ? 2 : 1
                            )
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: geometry.projectedY(rect.midY))
                }
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.30), .black, Color(white: 0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(Color(white: 0.48), lineWidth: 1).padding(3))
                .frame(width: 26, height: 26)
                .position(x: geometry.discCenter.x, y: geometry.projectedY(geometry.discCenter.y))
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(
            width: geometry.canvas.width * scale,
            height: geometry.canvas.height * scale,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
