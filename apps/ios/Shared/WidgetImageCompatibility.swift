import SwiftUI
import WidgetKit

extension Image {
    @ViewBuilder
    func bsFullColorWidgetImage() -> some View {
        if #available(iOS 18, *) {
            widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}
