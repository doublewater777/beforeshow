import SwiftUI

// MARK: - Footprint Presentation Support

func sectionTitle(_ title: String, _ subtitle: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundColor(BSColor.Stage.muted)
        Text(subtitle).font(.system(size: 11)).foregroundColor(BSColor.Stage.dim)
    }
}
