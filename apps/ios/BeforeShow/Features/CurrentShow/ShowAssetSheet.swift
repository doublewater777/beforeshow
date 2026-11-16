import Foundation
import SwiftData
import SwiftUI

/// Presents one ticket/timetable asset in a drawer sheet.
///
/// The entry view remains inside a navigation stack so its existing upload,
/// replacement, viewer, and delete flows work from both the current-show home
/// and a historical/canceled/ended show detail page.

struct ShowAssetSheet: View {
    let showID: UUID
    let showName: String
    let kind: ShowAssetKind

    @Environment(\.dismiss) private var dismiss
    @Query private var assets: [ShowAsset]

    init(
        showID: UUID,
        showName: String,
        kind: ShowAssetKind
    ) {
        self.showID = showID
        self.showName = showName
        self.kind = kind
        let kindRaw = kind.rawValue
        _assets = Query(
            filter: #Predicate<ShowAsset> { asset in
                asset.showID == showID && asset.kindRawValue == kindRaw
            }
        )
    }

    var body: some View {
        Group {
            if kind == .timetable {
                TimetableSheet(
                    showID: showID,
                    showName: showName
                )
            } else if let asset = assets.first {
                NavigationStack {
                    ShowAssetViewerView(
                        showID: showID,
                        showName: showName,
                        kind: kind,
                        asset: asset
                    )
                    .toolbar {
                        BSChromeToolbarCloseButton(accessibilityLabel: "取消") { dismiss() }
                    }
                    .bsClearNavigationContainer()
                }
                .bsSystemGlassSheet(detents: [.large])
            } else {
                BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
                    ShowAssetUploadView(
                        showID: showID,
                        showName: showName,
                        kind: kind
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
