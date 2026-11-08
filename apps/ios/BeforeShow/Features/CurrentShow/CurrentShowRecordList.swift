import SwiftData
import SwiftUI

/// 当前 tab 模块下方的「歌单 / 此刻 / 留下的东西」：与足迹详情同一组记录行，换成首页的磨砂模块。
struct CurrentShowRecordSection: View {
    let show: Show
    let phase: HomeShowPhase

    var body: some View {
        if let title = CurrentShowRecordKit.title(for: phase) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(BSFont.Editorial.caps(13))
                    .tracking(1.5)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
                ShowRecordRows(show: show, kinds: CurrentShowRecordKit.kinds(for: phase), phase: phase)
                    .bsGlassCard(cornerRadius: 24)
            }
        }
    }
}

/// 每行只开一层：现场听到了 / 花销各一张 sheet，周边直接相机或相册；保存结果留在行内。
struct ShowRecordRows: View {
    let show: Show
    let kinds: [CurrentShowRecordKind]
    var phase: HomeShowPhase = .ended

    @Query private var setlist: [ShowSetlistMemory]
    @State private var isShowingSetlist = false
    @State private var isShowingSpending = false
    @State private var merchSource: MerchCaptureSource?
    @State private var merchFailed = false

    init(show: Show, kinds: [CurrentShowRecordKind], phase: HomeShowPhase = .ended) {
        self.show = show
        self.kinds = kinds
        self.phase = phase
        let showID = show.id
        _setlist = Query(filter: #Predicate<ShowSetlistMemory> { $0.showID == showID })
    }

    private var rows: [CurrentShowRecordRow] {
        let facts = CurrentShowRecordFacts(
            setlistCount: setlist.count,
            playedSetlistCount: setlist.filter(\.isPlayed).count,
            merchCount: show.merchItems.count,
            ticketPriceText: show.formattedSpending(show.ticketPrice),
            travelCostText: show.formattedSpending(show.travelCost)
        )
        return kinds.map { CurrentShowRecordKit.row($0, phase: phase, facts: facts) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(Color.white.opacity(0.1)).padding(.leading, 52) }
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
        .sheet(isPresented: $isShowingSetlist) { ShowSetlistSheet(show: show, forcedPhase: phase) }
        .sheet(isPresented: $isShowingSpending) { ShowSpendingSheet(show: show) }
        .merchCapture($merchSource, show: show) { saved in merchFailed = !saved }
        .onChange(of: merchSource) { _, source in if source != nil { merchFailed = false } }
    }

    private func label(_ row: CurrentShowRecordRow) -> some View {
        let failed = row.kind == .merch && merchFailed
        return HStack(spacing: 12) {
            Image(systemName: row.iconName)
                .font(.system(size: 17))
                .foregroundStyle(BSColor.Stage.foreground.opacity(row.isFilled ? 0.9 : 0.4))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                if let subtitle = failed ? BSLocalization.text("照片没有保存，请重试") : row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(failed ? BSColor.Stage.live : BSColor.Stage.muted)
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
        .animation(.easeOut(duration: 0.2), value: row)
    }
}
