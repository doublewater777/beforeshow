import SwiftData
import SwiftUI

/// 当前 tab 的记录清单：一块磨砂分组，背后是海报取色的模糊光。
struct CurrentShowRecordSection: View {
    let show: Show
    let phase: HomeShowPhase
    let leading: [CurrentShowRecordKind]
    let onSelect: (CurrentShowRecordKind) -> Void
    @Binding var merchSource: MerchCaptureSource?

    @Query private var setlist: [ShowSetlistMemory]

    init(
        show: Show,
        phase: HomeShowPhase,
        leading: [CurrentShowRecordKind],
        merchSource: Binding<MerchCaptureSource?>,
        onSelect: @escaping (CurrentShowRecordKind) -> Void
    ) {
        self.show = show
        self.phase = phase
        self.leading = leading
        self.onSelect = onSelect
        _merchSource = merchSource
        let showID = show.id
        _setlist = Query(filter: #Predicate<ShowSetlistMemory> { $0.showID == showID })
    }

    private var facts: CurrentShowRecordFacts {
        CurrentShowRecordFacts(
            hasTicket: ShowAssetManagementPolicy.hasSavedAsset(for: show, kind: .ticket, assets: show.assets),
            hasTimetable: ShowAssetManagementPolicy.hasSavedAsset(for: show, kind: .timetable, assets: show.assets),
            companionStatus: show.companionStatus,
            companionNames: show.companionNames,
            memoryCount: show.memoryFragments.count,
            setlistCount: setlist.count,
            merchCount: show.merchItems.count,
            ticketPriceText: show.formattedSpending(show.ticketPrice),
            travelCostText: show.formattedSpending(show.travelCost)
        )
    }

    var body: some View {
        let rows = CurrentShowRecordKit.rows(phase: phase, facts: facts, leading: leading)
        VStack(alignment: .leading, spacing: 8) {
            Text(CurrentShowRecordKit.title(for: phase))
                .font(.system(size: 13, weight: .semibold))
                .tracking(1)
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.6))
                .padding(.leading, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(Color.white.opacity(0.12)).padding(.leading, 52) }
                    rowButton(row)
                }
            }
            .bsGlassPanel(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .background(alignment: .top) { posterGlow }
        .animation(.easeOut(duration: 0.25), value: rows)
    }

    @ViewBuilder
    private func rowButton(_ row: CurrentShowRecordRow) -> some View {
        if row.kind == .merch {
            MerchCaptureMenu(source: $merchSource) { rowLabel(row) }
                .buttonStyle(.plain)
        } else {
            Button { onSelect(row.kind) } label: { rowLabel(row) }
                .buttonStyle(.plain)
        }
    }

    private func rowLabel(_ row: CurrentShowRecordRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.iconName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(row.isFilled ? BSColor.Stage.foreground.opacity(0.9) : BSColor.Stage.foreground.opacity(0.4))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(row.isFilled ? 0.6 : 0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            Text(row.action)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(row.emphasizesAction ? BSColor.Stage.accent : BSColor.Stage.foreground.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 海报模糊成一团光，让磨砂有东西可透。
    private var posterGlow: some View {
        ShowCoverImageView(urlString: show.coverImageURL, aspectRatio: 3.0 / 4.0, contentMode: .fill, enforcesAspectRatio: false, cornerRadius: 0)
            .frame(height: 320)
            .blur(radius: 60)
            .saturation(1.3)
            .opacity(0.55)
            .padding(.horizontal, -40)
            .offset(y: -40)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
