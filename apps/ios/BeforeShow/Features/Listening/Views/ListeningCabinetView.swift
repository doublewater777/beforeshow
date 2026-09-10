import SwiftUI

struct ListeningCabinetView: View {
    @Bindable var room: ListeningRoomCoordinator
    let showAll: () -> Void
    let showDetails: (ListeningDisc) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("listening.didHintManualDiscDrag") private var didHintManualDiscDrag = false
    @State private var hintedDiscID: String?

    private var shelfTitle: String {
        room.browsingArtist?.name ?? BSLocalization.text("BeforeShow 热门合辑")
    }

   private var shelfCountText: String {
       if room.catalogState == .loading && room.libraryDiscs.isEmpty {
           return BSLocalization.text("加载中…")
       }
        return BSLocalization.format("%d 张唱片", room.libraryDiscs.count)
   }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            // Section header with title, count tag, and View All button
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: BSSpacing.xs) {
                    Text(shelfTitle)
                        .font(BSFont.headline)
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(shelfCountText)
                        .font(BSListeningTokens.badge)
                        .foregroundStyle(BSColor.Stage.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BSColor.Stage.surfaceRaised, in: Capsule())
                }
                Spacer()
                Button(action: showAll) {
                    HStack(spacing: 3) {
                        Text(BSLocalization.text("查看全部"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.accent)
                    .frame(minHeight: BSLayout.minTouchTarget)
                }
                .buttonStyle(BSListeningPressStyle(scale: 0.95))
                .accessibilityIdentifier("listening.allDiscs")
            }
           .padding(.top, 2)

            if room.catalogState == .loading && room.shelfDiscs.isEmpty {
                HStack(spacing: BSSpacing.compact) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)
                            .overlay(
                                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                                    .stroke(BSColor.Stage.border, lineWidth: 1)
                            )
                            .overlay {
                                ProgressView()
                                    .tint(BSColor.Stage.accent)
                                    .scaleEffect(0.8)
                            }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            } else if room.shelfDiscs.isEmpty {
               Text(BSLocalization.text("暂时没有找到可翻的唱片"))
                   .font(BSListeningTokens.caption)
                   .foregroundStyle(BSColor.Stage.muted)
                   .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
           } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: BSSpacing.compact) {
                            ForEach(room.shelfDiscs) { disc in
                                ListeningCabinetDiscButton(
                                    room: room,
                                    disc: disc,
                                    showsPullHint: hintedDiscID == disc.id,
                                    showDetails: showDetails
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }

                    // Physical Rack Beam & Lip
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), BSColor.Stage.accent.opacity(0.35), Color.white.opacity(0.08)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 1)
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.22, blue: 0.24),
                                Color(red: 0.11, green: 0.11, blue: 0.12),
                                Color(red: 0.05, green: 0.05, blue: 0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
                        .shadow(color: Color.black.opacity(0.6), radius: 4, y: 2)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(BSColor.Stage.muted)
        .listeningFrame("cabinet")
        .task(id: hintEligibilityKey) {
            guard !didHintManualDiscDrag, !reduceMotion,
                  room.mechanism.position == .stored,
                  let disc = room.shelfDiscs.first else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            hintedDiscID = disc.id
            try? await Task.sleep(for: .milliseconds(350))
            hintedDiscID = nil
            didHintManualDiscDrag = true
        }
    }

    private var hintEligibilityKey: String {
        "\(room.shelfDiscs.first?.id ?? "none")-\(room.mechanism.position)"
    }
}

private struct ListeningCabinetDiscButton: View {
    @Bindable var room: ListeningRoomCoordinator
    let disc: ListeningDisc
    let showsPullHint: Bool
    let showDetails: (ListeningDisc) -> Void

    private var isLoaded: Bool {
        room.mechanism.disc?.id == disc.id && room.mechanism.position != .stored
    }

    private var accessibilityArtistName: String {
        disc.artistNames.isEmpty
            ? room.browsingArtist?.name ?? "BeforeShow"
            : disc.artistNames.joined(separator: ", ")
    }

    var body: some View {
        Button {
            showDetails(disc)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ListeningSleeveCard(disc: disc, isLoaded: isLoaded, showsPullHint: showsPullHint, show: room.show)
                    .offset(y: room.isRecentDisc(disc) ? -BSListeningTokens.recentLift : 0)
                    .listeningFrame("slot:\(disc.id)")
                ListeningSleeveMarks(room: room, disc: disc)
                HStack(spacing: 3) {
                    if room.isPlayingDisc(disc) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(BSColor.Stage.accent)
                    }
                    Text(disc.title)
                        .font(BSListeningTokens.captionMedium)
                        .lineLimit(1)
                        .foregroundStyle(room.isPlayingDisc(disc) ? BSColor.Stage.accent : BSColor.Stage.foreground)
                }
                .frame(width: 94, alignment: .leading)
                .frame(minHeight: 18)
            }
            .frame(width: 96, alignment: .leading)
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.95))
        .accessibilityLabel("\(disc.title), \(accessibilityArtistName)")
        .accessibilityValue(ListeningSleeveMarks.accessibilityText(room: room, disc: disc))
        .accessibilityAction(named: BSLocalization.text("取出并放入播放机")) {
            room.mechanism.takeFromCabinet(disc)
        }
        .accessibilityIdentifier("listening.disc.\(disc.id)")
    }
}
