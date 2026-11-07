import SwiftData
import SwiftUI

/// 「留下的东西」下面的三项记录：现场听到了、周边、花销。每项只开一层 sheet 或直接相机 / 相册。
struct FootprintKeepsakeRecords: View {
    let show: Show
    let onMerchFinished: (Bool) -> Void

    @Query private var setlist: [ShowSetlistMemory]
    @State private var isShowingSetlist = false
    @State private var isShowingSpending = false
    @State private var merchSource: MerchCaptureSource?

    init(show: Show, onMerchFinished: @escaping (Bool) -> Void) {
        self.show = show
        self.onMerchFinished = onMerchFinished
        let showID = show.id
        _setlist = Query(filter: #Predicate<ShowSetlistMemory> { $0.showID == showID })
    }

    private var rows: [CurrentShowRecordRow] {
        let facts = CurrentShowRecordFacts(
            setlistCount: setlist.count,
            merchCount: show.merchItems.count,
            ticketPriceText: show.formattedSpending(show.ticketPrice),
            travelCostText: show.formattedSpending(show.travelCost)
        )
        return [.setlist, .merch, .spending].map { CurrentShowRecordKit.row($0, phase: .ended, facts: facts) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52) }
                if row.kind == .merch {
                    MerchCaptureMenu(source: $merchSource) { label(row) }.buttonStyle(.plain)
                } else {
                    Button {
                        if row.kind == .setlist { isShowingSetlist = true } else { isShowingSpending = true }
                    } label: { label(row) }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07)))
        .sheet(isPresented: $isShowingSetlist) { ShowSetlistSheet(show: show) }
        .sheet(isPresented: $isShowingSpending) { ShowSpendingSheet(show: show) }
        .merchCapture($merchSource, show: show, onFinished: onMerchFinished)
    }

    private func label(_ row: CurrentShowRecordRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.iconName)
                .font(.system(size: 17))
                .foregroundStyle(BSColor.Stage.foreground.opacity(row.isFilled ? 0.9 : 0.4))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            Text(row.action)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(row.emphasizesAction ? BSColor.Stage.accent : BSColor.Stage.foreground.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
