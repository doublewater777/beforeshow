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
                .fill(.black.opacity(0.40))
                .blur(radius: 20)
                .frame(width: geometry.lowerDeck.width * 0.92, height: 86)
                .position(
                    x: geometry.lowerDeck.midX,
                    y: geometry.projectedY(geometry.lowerDeck.maxY) + 10
                )

            upperPod
            lowerBridge
            lowerDeck
            closedLid
            lcdPlaceholder
            controlPlaceholders
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

    private var upperPod: some View {
        let rect = geometry.discPod
        let projectedHeight = rect.height * cos(geometry.tiltDegrees * .pi / 180)

        return RoundedRectangle(cornerRadius: 92, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.235, green: 0.225, blue: 0.215),
                        Color(red: 0.115, green: 0.115, blue: 0.125),
                        Color(red: 0.075, green: 0.075, blue: 0.085)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 92, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 87, style: .continuous)
                    .stroke(BSColor.Stage.accent.opacity(0.18), lineWidth: 1.2)
                    .padding(5)
            )
            .frame(width: rect.width, height: projectedHeight)
            .position(x: rect.midX, y: geometry.projectedY(rect.midY))
            .shadow(color: .black.opacity(0.42), radius: 15, y: 8)
    }

    private var lowerBridge: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color(red: 0.095, green: 0.09, blue: 0.09),
                        Color.black.opacity(0.52)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            )
            .frame(width: 116, height: 50)
            .position(
                x: geometry.discPod.midX,
                y: geometry.projectedY(geometry.discPod.maxY) + 19
            )
    }

    private var lowerDeck: some View {
        let rect = geometry.lowerDeck
        let projectedHeight = rect.height * cos(geometry.tiltDegrees * .pi / 180)

        return RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.205, green: 0.19, blue: 0.175),
                        Color(red: 0.095, green: 0.095, blue: 0.105),
                        Color(red: 0.065, green: 0.065, blue: 0.074)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(BSColor.Stage.accent.opacity(0.17), lineWidth: 1)
                    .padding(4)
            )
            .frame(width: rect.width, height: projectedHeight)
            .position(x: rect.midX, y: geometry.projectedY(rect.midY))
            .shadow(color: .black.opacity(0.46), radius: 13, y: 7)
    }

    private var closedLid: some View {
        ZStack {
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
            Ellipse()
                .stroke(BSColor.Stage.accent.opacity(0.24), lineWidth: 2)
                .padding(2)
            Ellipse()
                .stroke(.white.opacity(0.11), lineWidth: 1)
                .padding(7)

            Capsule()
                .fill(Color.black.opacity(0.58))
                .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 1))
                .frame(width: 52, height: 13)
                .offset(y: geometry.lid.height * 0.40)
        }
        .frame(
            width: geometry.lid.width,
            height: geometry.lid.height * cos(geometry.tiltDegrees * .pi / 180)
        )
        .position(
            x: geometry.lid.midX,
            y: geometry.projectedY(geometry.lid.midY)
        )
        .shadow(color: .black.opacity(0.28), radius: 9, y: 5)
    }

    private var lcdPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .frame(width: geometry.lcd.width, height: geometry.lcd.height)
            .position(x: geometry.lcd.midX, y: geometry.projectedY(geometry.lcd.midY))
    }

    private var controlPlaceholders: some View {
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
    }
}
