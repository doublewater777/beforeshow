import SwiftUI

struct TimetableMatrixCardsView: View {
    let layout: TimetableMatrixLayout
    let lane: CGFloat
    let performances: [UUID: TimetablePerformance]
    let stages: [TimetableStage]
    let viewport: TimetableMatrixViewport
    let wantOnly: Bool
    let timeZone: TimeZone
    let avatarURL: (TimetablePerformance) -> URL?
    let onSelect: (TimetablePerformance) -> Void
    let onToggle: (TimetablePerformance) -> Void

    var body: some View {
        let visibleRect = viewport.visibleRect
        let visibleCards = layout.cards.filter { card in
            CGRect(x: x(for: card), y: card.top, width: lane, height: card.height).intersects(visibleRect)
        }
        ZStack(alignment: .topLeading) {
            ForEach(visibleCards) { card in
                let performance = performances[card.id]
                TimetableMatrixCard(
                    card: card,
                    width: lane,
                    avatarURL: performance.flatMap(avatarURL),
                    artistID: performance?.appleMusicArtistID,
                    isGhost: wantOnly && !card.isInterested,
                    nowOffset: card.status == .live ? layout.nowY.map { $0 - card.top } : nil,
                    stageTint: TimetableStageLight.color(stages[card.laneIndex].sortOrder),
                    timeZone: timeZone,
                    onSelect: { if let performance { onSelect(performance) } },
                    onToggle: { if let performance { onToggle(performance) } }
                )
                .equatable()
                .offset(x: x(for: card), y: card.top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func x(for card: TimetableMatrixLayout.Card) -> CGFloat {
        TimetableStyle.matrixRulerWidth + CGFloat(card.laneIndex) * (lane + TimetableStyle.matrixLaneGap)
    }
}
