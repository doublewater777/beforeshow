import SwiftUI

// MARK: - Current Show Route Presentation

struct MapChooserSheet: View {
    let hasDestination: Bool
    let destinationLabel: String
    let apps: [ExternalMapApp]
    let onSelect: (ExternalMapApp) -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            VStack(spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: "map",
                    title: MapChooserPresentation.title(hasDestination: hasDestination),
                    subtitle: MapChooserPresentation.message(
                        hasDestination: hasDestination,
                        destinationLabel: destinationLabel,
                        installed: apps
                    )
                )

                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    if index == 0 {
                        Button { onSelect(app) } label: {
                            Label(app.title, systemImage: app.iconName)
                        }
                        .buttonStyle(BSPrimaryButtonStyle())
                    } else {
                        Button { onSelect(app) } label: {
                            Label(app.title, systemImage: app.iconName)
                        }
                        .buttonStyle(BSSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}
