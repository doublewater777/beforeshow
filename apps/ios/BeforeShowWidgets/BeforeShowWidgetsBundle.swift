import SwiftUI
import WidgetKit

@main
struct BeforeShowWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
        ShowLiveActivity()
    }
}
