import SwiftUI
import WidgetKit

@main
struct BeforeShowWidgetsBundle: WidgetBundle {
    init() {
        WidgetLanguage.applyAppLanguageSelection()
    }

    var body: some Widget {
        CountdownWidget()
        LockScreenCountdownWidget()
        ShowLiveActivity()
    }
}
