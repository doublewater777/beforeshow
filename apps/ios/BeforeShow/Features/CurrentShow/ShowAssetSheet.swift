import Foundation
import SwiftData
import SwiftUI

enum DetailVisibilityEvent {
    case assetSheetPresented
    case assetSheetDismissed
}

enum DetailVisibilityHandoff {
    static func tabBarHidden(after event: DetailVisibilityEvent) -> Bool {
        switch event {
        case .assetSheetPresented:
            return true
        case .assetSheetDismissed:
            return false
        }
    }
}

/// Presents one ticket/timetable asset in a drawer sheet.
///
/// The entry view remains inside a navigation stack so its existing upload,
/// replacement, viewer, and delete flows work from both the current-show home
/// and a historical/canceled/ended show detail page.

struct ShowAssetSheet: View {
    let showID: UUID
    let showName: String
    let kind: ShowAssetKind
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    var keepsParentDetailHidden = false

    @Environment(\.dismiss) private var dismiss
    @Query private var assets: [ShowAsset]

    init(
        showID: UUID,
        showName: String,
        kind: ShowAssetKind,
        onDetailVisibilityChange: @escaping (Bool) -> Void = { _ in },
        keepsParentDetailHidden: Bool = false
    ) {
        self.showID = showID
        self.showName = showName
        self.kind = kind
        self.onDetailVisibilityChange = onDetailVisibilityChange
        self.keepsParentDetailHidden = keepsParentDetailHidden
        let kindRaw = kind.rawValue
        _assets = Query(
            filter: #Predicate<ShowAsset> { asset in
                asset.showID == showID && asset.kindRawValue == kindRaw
            }
        )
    }

    var body: some View {
        Group {
            if let asset = assets.first {
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
                .bsSystemGlassSheet()
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
        .onAppear {
            setDetailVisibility(for: .assetSheetPresented)
        }
        .onDisappear {
            if keepsParentDetailHidden {
                onDetailVisibilityChange(true)
            } else {
                setDetailVisibility(for: .assetSheetDismissed)
            }
        }
    }

    private func setDetailVisibility(for event: DetailVisibilityEvent) {
        let hidden = DetailVisibilityHandoff.tabBarHidden(after: event)
        onDetailVisibilityChange(hidden)
    }
}
