import SwiftData
import SwiftUI

/// 票根、时刻表、歌单、周边、同行、花销在一个网格里：内容简单的半卡成对，有东西可看的占整行。
/// 现场详情与足迹详情共用，同一场在两个页面长得一样。
struct ShowKeepsakeSection: View {
    let title: String
    let show: Show
    let entries: [ShowAssetManagementEntry]
    let assetFor: (ShowAssetKind) -> ShowAsset?
    let recordKinds: [CurrentShowRecordKind]
    var recordPhase: HomeShowPhase = .ended
    let onSelect: (ShowAssetKind) -> Void
    let onEditCompanion: () -> Void

    @Query private var setlist: [ShowSetlistMemory]

    enum Item: Hashable {
        case asset(ShowAssetKind)
        case record(CurrentShowRecordKind)
        case companion
    }

    init(title: String, show: Show, entries: [ShowAssetManagementEntry], assetFor: @escaping (ShowAssetKind) -> ShowAsset?, recordKinds: [CurrentShowRecordKind], recordPhase: HomeShowPhase = .ended, onSelect: @escaping (ShowAssetKind) -> Void, onEditCompanion: @escaping () -> Void) {
        self.title = title
        self.show = show
        self.entries = entries
        self.assetFor = assetFor
        self.recordKinds = recordKinds
        self.recordPhase = recordPhase
        self.onSelect = onSelect
        self.onEditCompanion = onEditCompanion
        let showID = show.id
        _setlist = Query(filter: #Predicate<ShowSetlistMemory> { $0.showID == showID })
    }

    /// 票根、时刻表 → 歌单、周边 → 同行、花销。
    static func items(assetKinds: [ShowAssetKind], recordKinds: [CurrentShowRecordKind]) -> [Item] {
        var items = assetKinds.map(Item.asset)
        items += [CurrentShowRecordKind.setlist, .merch].filter(recordKinds.contains).map(Item.record)
        items.append(.companion)
        if recordKinds.contains(.spending) { items.append(.record(.spending)) }
        return items
    }

    var body: some View {
        let facts = ShowRecordCard.facts(show: show, setlist: setlist)
        let items = Self.items(assetKinds: entries.map(\.kind), recordKinds: recordKinds)
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(FootprintDetailTokens.sectionFont)
                .foregroundStyle(BSColor.Stage.foreground)
            ShowModuleGrid(items: items.map { item in
                if case .record(let kind) = item {
                    return (item, CurrentShowRecordKit.width(kind, phase: recordPhase, facts: facts))
                }
                return (item, .half)
            }) { item in
                switch item {
                case .asset(let kind):
                    Button { onSelect(kind) } label: {
                        ShowAssetPhotoCard(
                            kind: kind,
                            asset: assetFor(kind),
                            hasContentWithoutImage: kind == .timetable && show.timetable != nil,
                            tilt: kind == .ticket ? -5 : 4,
                            surface: .plain
                        )
                    }
                    .buttonStyle(.plain)
                case .record(let kind):
                    ShowRecordCard(show: show, kind: kind, phase: recordPhase, surface: .plain)
                case .companion:
                    Button(action: onEditCompanion) {
                        ShowCompanionCard(names: show.companionNames, surface: .plain)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
