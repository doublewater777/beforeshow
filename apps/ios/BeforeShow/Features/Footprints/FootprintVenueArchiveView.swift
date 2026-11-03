import SwiftUI

struct FootprintVenueCoverStack: View {
    let shows: [Show]
    let covers: [UUID: FootprintCover]
    var maxCovers: Int = 2
    var width: CGFloat = 64
    var height: CGFloat = 84

    var body: some View {
        ZStack {
            let stackShows = Array(shows.prefix(maxCovers))
            if stackShows.isEmpty {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Image(systemName: "building.2")
                            .font(.system(size: 16))
                            .foregroundStyle(BSColor.Stage.dim)
                    )
                    .frame(width: width, height: height)
            } else {
               ForEach(Array(stackShows.enumerated().reversed()), id: \.element.id) { index, show in
                   let isBack = index > 0
                   FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                       .frame(width: width, height: height)
                       .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                       .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
                       .scaleEffect(isBack ? 0.90 : 1.0)
                       .rotationEffect(.degrees(isBack ? -4 : 0))
                       .offset(x: isBack ? -4 : 0, y: isBack ? -2 : 0)
               }
           }
       }
       .padding(.leading, 4)
   }
}
