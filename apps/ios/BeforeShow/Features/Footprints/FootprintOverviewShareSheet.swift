import SwiftUI

// MARK: - Footprint Overview Share

struct FootprintShareSheet: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onSaved: () -> Void

    var body: some View {
        FootprintShareActionSheet(
            title: BSLocalization.text("分享完整足迹"),
            subtitle: BSLocalization.text("整张长图包含你的完整足迹档案，可直接保存或分享。"),
            previewHeight: 368,
            exportSize: CGSize(width: FootprintDashboardExportView.layoutWidth, height: 0),
            usesIntrinsicHeight: true,
            exportScale: FootprintDashboardExportView.exportScale,
            beforeExport: {
                await FootprintCoverExportWarmup.warm(covers: covers)
                await FootprintCoverExportWarmup.warm(artists: archive.artistArchiveItems)
                _ = await FootprintCityCoordinateResolver.shared.coordinates(
                    for: archive.cityArchiveItems.map(\.name)
                )
            },
            flexiblePreviewHeight: true,
            preview: { FootprintDashboardExportPreview(archive: archive, covers: covers) },
            exportContent: { FootprintDashboardExportView(archive: archive, covers: covers) },
            onSaved: onSaved
        )
    }
}
