import SwiftUI

/// What you bring to the show, laid out as objects: ticket, timetable, a +1 wristband.
/// After the show the same things are what you kept.
struct ShowDetailKit: View {
    let isAfterShow: Bool
    let assets: [ShowAssetManagementEntry]
    let assetFileURL: (ShowAssetKind) -> URL?
    let companionSubtitle: String
    let hasCompanion: Bool
    let onAsset: (ShowAssetKind) -> Void
    let onCompanion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isAfterShow ? BSLocalization.text("留下的东西") : BSLocalization.text("随身带"))
                .font(BSFont.headline)
                .foregroundStyle(BSColor.Stage.foreground)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(assets) { entry in
                    tile(title: entry.kind.title, subtitle: entry.subtitle, action: { onAsset(entry.kind) }) {
                        assetArt(entry)
                    }
                    .accessibilityLabel(BSLocalization.format("管理%@，%@", entry.kind.title, entry.subtitle))
                }
                tile(title: BSLocalization.text("同行"), subtitle: companionSubtitle, action: onCompanion) {
                    wristbands
                }
            }
        }
    }

    private func tile<Art: View>(title: String, subtitle: String, action: @escaping () -> Void, @ViewBuilder art: () -> Art) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                art()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 18)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(height: 150)
            .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(BSPressStyle())
    }

    // MARK: Art

    @ViewBuilder
    private func assetArt(_ entry: ShowAssetManagementEntry) -> some View {
        let tilt: Double = entry.kind == .ticket ? -4 : 4
        if let url = assetFileURL(entry.kind) {
            ZStack(alignment: .top) {
                BSTapedImage(url: url)
                    .frame(width: 66, height: 88)
                    .rotationEffect(.degrees(tilt))
                    .padding(.top, 6)
                tapeStrip(tilt: tilt)
            }
        } else if entry.hasSavedAsset {
            // A timetable saved as data, without a photo: drawn as a printed running order.
            ZStack(alignment: .top) {
                runningOrder
                    .rotationEffect(.degrees(tilt))
                    .padding(.top, 6)
                tapeStrip(tilt: tilt)
            }
        } else {
            emptySlot(width: 66, height: 88, tilt: tilt) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(BSColor.Stage.muted)
            }
        }
    }

    private var runningOrder: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color(white: 0.1)).frame(width: 30, height: 4)
            ForEach(0..<6, id: \.self) { row in
                Capsule()
                    .fill(row == 2 ? BSColor.Stage.accent : Color(white: 0.1).opacity(0.45))
                    .frame(width: [44, 36, 46, 32, 44, 28][row], height: 3)
            }
        }
        .padding(8)
        .frame(width: 66, height: 88, alignment: .topLeading)
        .background(BSColor.Stage.heroIvory, in: RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.55), radius: 9, y: 8)
    }

    /// Wristbands: the +1 you hand a friend, and an empty clasp until they accept.
    private var wristbands: some View {
        ZStack(alignment: .topLeading) {
            Text("+1")
                .font(.system(size: 13, weight: .semibold).width(.condensed))
                .tracking(2)
                .foregroundStyle(Color(white: 0.07))
                .frame(width: 82, height: 28)
                .background(BSColor.Stage.accent, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.5), radius: 7, y: 6)
                .rotationEffect(.degrees(-10))
                .offset(x: -4, y: 18)
            Group {
                if hasCompanion {
                    RoundedRectangle(cornerRadius: 6).fill(BSColor.Stage.accent.opacity(0.55))
                } else {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .frame(width: 82, height: 28)
            .rotationEffect(.degrees(6))
            .offset(x: 2, y: 50)
        }
        .accessibilityHidden(true)
    }

    private func emptySlot<Content: View>(width: CGFloat, height: CGFloat, tilt: Double, @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .frame(width: width, height: height)
            .overlay(content: content)
            .rotationEffect(.degrees(tilt))
            .padding(.top, 6)
    }

    private func tapeStrip(tilt: Double) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color(red: 0.84, green: 0.77, blue: 0.59).opacity(0.7))
            .frame(width: 34, height: 12)
            .rotationEffect(.degrees(tilt * 1.6))
            .offset(x: 16)
    }
}
