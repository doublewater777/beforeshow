import SwiftUI
import WidgetKit

@main
struct BeforeShowWidgetsBundle: WidgetBundle {
    init() {
    }

    var body: some Widget {
        CountdownWidget()
        LockScreenCountdownWidget()
        ListeningWidget()
        ShowLiveActivity()
    }
}
