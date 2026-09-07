import SwiftUI

struct ListeningArtistView: View {
    @Bindable var room: ListeningRoomCoordinator
    let artistID: String
    let returnToPlayer: () -> Void
    @State private var matching = false
    private var slot: Int? { room.show?.artists.firstIndex { $0.appleMusicArtistID == artistID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSSpacing.lg) {
                if let artist = room.artistPresentation(artistID) {
                    hero(artist)
                    if let editorial = artist.editorialText, !editorial.isEmpty {
                        Text(editorial)
                            .font(.subheadline).foregroundStyle(BSColor.Stage.muted)
                            .lineSpacing(5).lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(BSSpacing.md)
                            .background(BSColor.Stage.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: BSRadius.lg))
                            .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))
                    }
                    Button(BSLocalization.text("不是这个艺人？")) { matching = true }
                        .font(.caption).foregroundStyle(BSColor.Stage.muted).frame(minHeight: 44)
                    ListeningLibraryView(room: room, artist: artist, returnToPlayer: returnToPlayer)
                } else {
                    VStack(alignment: .leading, spacing: BSSpacing.md) {
                        RoundedRectangle(cornerRadius: BSRadius.lg).fill(BSColor.Stage.surfaceRaised).frame(height: 180)
                        Text(BSLocalization.text("正在准备唱片")).foregroundStyle(BSColor.Stage.muted)
                        Button(BSLocalization.text("重试")) { if let show = room.show { Task { await room.load(show: show, force: true) } } }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, BSSpacing.xl)
                }
            }.padding(BSSpacing.lg)
        }
        .background(BSColor.Stage.background).foregroundStyle(BSColor.Stage.foreground)
        .sheet(isPresented: $matching) {
            if let slot { ListeningArtistMatchSheet(room: room, slotIndex: slot, query: room.show?.artists[slot].name ?? "") }
        }
    }

    private func hero(_ artist: ListeningArtistPresentation) -> some View {
        VStack(spacing: BSSpacing.md) {
            ZStack {
                ListeningArtistArtwork(url: artist.artworkURL, name: artist.name)
                    .frame(width: 148, height: 148).clipShape(Circle())
                    .overlay(Circle().stroke(BSColor.borderProminent, lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, BSSpacing.md)
            VStack(spacing: BSSpacing.xs) {
                Text(artist.name).font(.title.bold()).multilineTextAlignment(.center)
                HStack(spacing: BSSpacing.xs) {
                    if let tier = artist.tier { artistChip(BSLocalization.text(tier.localizationKey)) }
                    artistChip(BSLocalization.format("已熟悉 %lld 首", artist.familiarCount))
                }.frame(maxWidth: .infinity)
                if !artist.genres.isEmpty {
                    Text(artist.genres.prefix(3).joined(separator: " · "))
                        .font(.caption).foregroundStyle(BSColor.Stage.muted).lineLimit(1)
                }
                Button {
                    if room.onlyArtistID == artistID {
                        room.returnToWholeShow()
                    } else {
                        room.filterArtist(artistID)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: room.onlyArtistID == artistID ? "checkmark.circle.fill" : "headphones")
                        Text(BSLocalization.text(room.onlyArtistID == artistID ? "已聚焦此艺人" : "只听这位艺人"))
                    }
                    .font(BSFont.caption.weight(.semibold))
                    .foregroundStyle(room.onlyArtistID == artistID ? Color.black : BSColor.Stage.foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(room.onlyArtistID == artistID ? BSColor.Stage.accent : BSColor.Stage.surfaceRaised, in: Capsule())
                    .overlay(Capsule().stroke(room.onlyArtistID == artistID ? Color.clear : BSColor.Stage.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func artistChip(_ text: String) -> some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(BSColor.Stage.muted)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(BSColor.Stage.surfaceRaised.opacity(0.72), in: Capsule())
    }
}
