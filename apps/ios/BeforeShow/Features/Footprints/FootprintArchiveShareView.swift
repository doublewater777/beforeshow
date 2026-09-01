import SwiftUI

// MARK: - Footprint Archive Share

struct FootprintArchiveShareSheet: View {
    let archive: FootprintArchiveSnapshot
    let category: FootprintCategory
    let onSaved: () -> Void
    @State private var scaledContentHeight: CGFloat?
    @State private var selectedDetent: PresentationDetent = .large

    var body: some View {
        FootprintShareActionSheet(
            title: FootprintArchiveShareCopy.title(for: category),
            subtitle: FootprintArchiveShareCopy.subtitle(for: category),
            previewHeight: FootprintPageSharePreviewLayout.height(for: scaledContentHeight),
            exportSize: CGSize(width: FootprintArchiveShareExportLayout.width, height: 0),
            usesIntrinsicHeight: true,
            exportScale: FootprintArchiveShareExportLayout.scale,
            flexiblePreviewHeight: true,
            previewMaxHeight: scaledContentHeight,
            preview: {
                FootprintArchiveSharePreview(
                    archive: archive,
                    category: category,
                    onScaledContentHeightChange: { scaledContentHeight = $0 }
                )
            },
            exportContent: { FootprintArchiveShareCard(archive: archive, category: category) },
            onSaved: onSaved
        )
        .presentationDetents(
            [
                .height(FootprintPageSharePreviewLayout.sheetHeight(for: scaledContentHeight)),
                .large
            ],
            selection: $selectedDetent
        )
    }
}

enum FootprintArchiveShareExportLayout {
    static let width: CGFloat = 360
    static let size = CGSize(width: width, height: 1100 / scale)
    static let scale: CGFloat = 3
}

private struct FootprintArchiveSharePreview: View {
    let archive: FootprintArchiveSnapshot
    let category: FootprintCategory
    var onScaledContentHeightChange: ((CGFloat) -> Void)? = nil
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / FootprintArchiveShareExportLayout.width
            ScrollView {
                FootprintArchiveShareCard(archive: archive, category: category)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        contentHeight = size.height
                        onScaledContentHeightChange?(size.height * scale)
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(
                        width: geometry.size.width,
                        height: contentHeight * scale,
                        alignment: .topLeading
                    )
            }
        }
    }
}

struct FootprintArchiveShareCard: View {
    let archive: FootprintArchiveSnapshot
    let category: FootprintCategory

    private var accent: Color {
        switch category {
        case .overview, .artist: return BSColor.Stage.accent
        case .city: return Color(red: 0.60, green: 0.72, blue: 0.91)
        case .venue: return Color(red: 0.72, green: 0.64, blue: 0.79)
        }
    }

    private var rankings: [FootprintRankItem] { archive.ranking(for: category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("BEFORESHOW · LIVE ARCHIVE")
                    .font(.system(size: 9.5, weight: .medium)).tracking(1.65).foregroundColor(accent)
                Spacer()
                Text(FootprintArchiveShareCopy.chip(for: category))
                    .font(.system(size: 9.5)).foregroundColor(BSColor.Stage.muted)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.045), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.10)))
            }

            Text(FootprintArchiveShareCopy.kicker(for: category))
                .font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundColor(accent)
                .padding(.top, 23)

            if category == .overview {
                overviewContent
            } else {
                categoryContent
            }

            HStack {
                Text(BSLocalization.text("开场前"))
                Spacer()
                Text(footprintFullDateText(Date(), calendar: Calendar.current))
            }
            .font(.system(size: 9.5)).foregroundColor(BSColor.Stage.dim)
            .padding(.top, 18)
        }
        .padding(20)
        .frame(width: FootprintArchiveShareExportLayout.width, alignment: .leading)
        .background {
            ZStack {
                Color(red: 0.035, green: 0.047, blue: 0.078)
                RadialGradient(
                    colors: [accent.opacity(0.24), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: FootprintArchiveShareExportLayout.width * 0.85
                )
                RadialGradient(
                    colors: [accent.opacity(0.08), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: FootprintArchiveShareExportLayout.width * 0.72
                )
            }
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(archive.shows.count)")
                .font(.system(size: 61, weight: .ultraLight))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.89), accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(BSLocalization.text("场现场")).font(.system(size: 14)).foregroundColor(BSColor.Stage.muted)
        }
        .padding(.top, 6)

        Text(BSLocalization.format("走过 %lld 座城市，留下 %lld 位艺人的现场记忆", archive.cities.count, archive.artists.count))
            .font(.system(size: 11)).foregroundColor(BSColor.Stage.muted).lineSpacing(1.55)
            .padding(.top, 7)

        HStack(spacing: 7) {
            shareMetric(archive.artists.count, BSLocalization.text("艺人"))
            shareMetric(archive.cities.count, BSLocalization.text("城市"))
            shareMetric(archive.venues.count, BSLocalization.text("场馆"))
            shareMetric(ShowDurationFormatter.aggregate(totalMinutes: archive.totalDurationMinutes), BSLocalization.text("现场时长"))
        }
        .padding(.top, 14)

        VStack(spacing: 7) {
            shareFocus(BSLocalization.text("最常看"), item: archive.artists.first)
            shareFocus(BSLocalization.text("最多去"), item: archive.cities.first)
            shareFocus(BSLocalization.text("最熟悉"), item: archive.venues.first)
        }
        .padding(.top, 13)
    }

    private var categoryContent: some View {
        let top = rankings.first
        let label: String
        let count: Int
        let unit: String
        switch category {
        case .artist:
            label = BSLocalization.text("你最常看的艺人"); count = archive.artists.count; unit = BSLocalization.text("位艺人")
        case .city:
            label = BSLocalization.text("你去过最多的城市"); count = archive.cities.count; unit = BSLocalization.text("座城市")
        case .venue:
            label = BSLocalization.text("你最熟悉的场馆"); count = archive.venues.count; unit = BSLocalization.text("个场馆")
        case .overview:
            label = ""; count = 0; unit = ""
        }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label).font(.system(size: 10)).foregroundColor(BSColor.Stage.dim)
                    Text(top?.name ?? BSLocalization.text("还没有记录"))
                        .font(.system(size: 24, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                if let top {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(top.count)").font(.system(size: 42, weight: .ultraLight)).foregroundColor(accent)
                        Text(BSLocalization.text("场")).font(.system(size: 10)).foregroundColor(BSColor.Stage.muted)
                    }
                }
            }
            .padding(.top, 6)

            VStack(spacing: 10) {
                ForEach(Array(rankings.prefix(3).enumerated()), id: \.element.id) { index, item in
                    shareRank(index: index, item: item, maximum: rankings.first?.count ?? 1)
                }
            }
            .padding(.top, rankings.isEmpty ? 0 : 18)

            HStack {
                Text(BSLocalization.format("共记录 %lld %@", count, unit))
                Spacer()
                Text(BSLocalization.format("%lld 场现场", archive.shows.count))
            }
            .font(.system(size: 10)).foregroundColor(BSColor.Stage.dim)
            .padding(.top, 16).padding(.bottom, 4)
        }
    }

    private func shareMetric(_ value: Int, _ label: String) -> some View {
        shareMetric("\(value)", label)
    }

    private func shareMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundColor(BSColor.Stage.foreground).lineLimit(1).minimumScaleFactor(0.72)
            Text(label).font(.system(size: 9.5)).foregroundColor(BSColor.Stage.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.075)))
    }

    private func shareFocus(_ label: String, item: FootprintRankItem?) -> some View {
        HStack(spacing: 9) {
            Text(label).font(.system(size: 9.5)).foregroundColor(BSColor.Stage.dim).frame(width: 45, alignment: .leading)
            Text(item?.name ?? BSLocalization.text("还没有记录")).font(.system(size: 11.5, weight: .medium)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
            Spacer(minLength: 0)
            if let item { Text(BSLocalization.format("%lld 场", item.count)).font(.system(size: 10.5)).foregroundColor(BSColor.Stage.muted) }
        }
    }

    private func shareRank(index: Int, item: FootprintRankItem, maximum: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(.system(size: 9.5)).foregroundColor(BSColor.Stage.dim).frame(width: 17, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.name).font(.system(size: 11.5, weight: .medium)).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(BSLocalization.format("%lld 场", item.count)).font(.system(size: 10)).foregroundColor(BSColor.Stage.muted)
                }
                GeometryReader { geometry in
                    Capsule().fill(Color.white.opacity(0.065)).overlay(alignment: .leading) {
                        Capsule().fill(accent.opacity(0.86)).frame(width: geometry.size.width * CGFloat(item.count) / CGFloat(max(maximum, 1)))
                    }
                }
                .frame(height: 3)
            }
        }
    }
}
