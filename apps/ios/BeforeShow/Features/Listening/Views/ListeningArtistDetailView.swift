import SwiftUI

struct ListeningArtistDetailView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @State private var matching: Int?
    @State private var artistID: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text(BSLocalization.text("当前现场")).font(.caption).foregroundStyle(BSColor.Stage.muted)
                        Text(show.name).font(BSFont.V3.title3).lineLimit(2)
                        Text(BSLocalization.text("整场") + " · " + String(show.artists.count) + " " + BSLocalization.text("位艺人"))
                            .font(.caption).foregroundStyle(BSColor.Stage.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BSSpacing.md)
                    .background(BSColor.Stage.surface.opacity(0.60), in: RoundedRectangle(cornerRadius: BSRadius.lg))
                    .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))

                    if room.onlyArtistID != nil {
                        Button(BSLocalization.text("回到整场")) { room.returnToWholeShow(); dismiss() }
                            .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    }

                    LazyVStack(spacing: BSSpacing.sm) {
                        ForEach(Array(show.artists.enumerated()), id: \.offset) { index, artist in
                            artistRow(artist: artist, index: index)
                        }
                        if show.artists.isEmpty {
                            Button(BSLocalization.text("连接艺人")) { matching = 0 }
                                .buttonStyle(BSPrimaryButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, BSSpacing.lg)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.xl)
            }
            .background(BSColor.Stage.background)
            .navigationTitle(BSLocalization.text("艺人详情"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(BSLocalization.text("完成")) { dismiss() } } }
            .sheet(isPresented: Binding(get: { matching != nil }, set: { if !$0 { matching = nil } })) {
                if let matching { ListeningArtistMatchSheet(room: room, slotIndex: matching, query: show.artists.indices.contains(matching) ? show.artists[matching].name : "") }
            }
            .navigationDestination(isPresented: Binding(get: { artistID != nil }, set: { if !$0 { artistID = nil } })) {
                if let artistID { ListeningArtistView(room: room, artistID: artistID, returnToPlayer: { dismiss() }) }
            }
        }.tint(BSColor.Stage.foreground).presentationDragIndicator(.visible)
    }

    private func artistRow(artist: ArtistSlot, index: Int) -> some View {
        let presentation = artist.appleMusicArtistID.flatMap { room.artistPresentation($0) }
        let isScoped = artist.appleMusicArtistID != nil && room.onlyArtistID == artist.appleMusicArtistID
        let isMatched = artist.appleMusicArtistID != nil
        return Group {
            if let id = artist.appleMusicArtistID {
                Button {
                    artistID = id
                } label: {
                    rowContent(artist: artist, presentation: presentation, isScoped: isScoped, isMatched: true)
                }
                .contextMenu {
                    Button {
                        matching = index
                    } label: {
                        Label(BSLocalization.text("重新匹配艺人"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    if isScoped {
                        Button {
                            room.returnToWholeShow()
                        } label: {
                            Label(BSLocalization.text("回到整场"), systemImage: "music.note.list")
                        }
                    } else {
                        Button {
                            room.filterArtist(id)
                        } label: {
                            Label(BSLocalization.text("仅听此艺人"), systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                }
            } else {
                Button {
                    matching = index
                } label: {
                    rowContent(artist: artist, presentation: nil, isScoped: false, isMatched: false)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func rowContent(artist: ArtistSlot, presentation: ListeningArtistPresentation?, isScoped: Bool, isMatched: Bool) -> some View {
        HStack(spacing: BSSpacing.md) {
            ListeningArtistArtwork(url: artist.avatarURL.flatMap(URL.init(string:)), name: artist.name)
                .frame(width: 58, height: 58).clipShape(Circle())
                .overlay(Circle().stroke(isScoped ? BSColor.Stage.accent : BSColor.Stage.border, lineWidth: isScoped ? 2 : 1))
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                HStack(spacing: 6) {
                    Text(artist.name).font(.headline).foregroundStyle(BSColor.Stage.foreground)
                    if isScoped {
                        Text(BSLocalization.text("已聚焦"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BSColor.Stage.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BSColor.Stage.accent.opacity(0.15), in: Capsule())
                    }
                }
                if let presentation {
                    HStack(spacing: BSSpacing.xs) {
                        if let tier = presentation.tier { Text(BSLocalization.text(tier.localizationKey)) }
                        Text(BSLocalization.format("已熟悉 %lld 首", presentation.familiarCount))
                    }.font(.caption).foregroundStyle(BSColor.Stage.muted).lineLimit(1)
                } else {
                    Text(isMatched ? BSLocalization.text("正在准备唱片") : BSLocalization.text("未连接 Apple Music"))
                        .font(.caption).foregroundStyle(BSColor.Stage.muted)
                }
            }
            Spacer(minLength: 0)
            if isMatched {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(BSColor.Stage.muted)
                    .frame(width: 44, height: 44)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "link.badge.plus")
                    Text(BSLocalization.text("连接艺人"))
                }
                .font(BSFont.caption.weight(.medium))
                .foregroundStyle(BSColor.Stage.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(BSSpacing.md)
        .background(BSColor.Stage.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(isScoped ? BSColor.Stage.accent : .clear).frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))
        .accessibilityLabel(artist.name)
    }
}
