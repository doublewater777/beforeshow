import SwiftUI

struct ListeningTransportPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? ListeningStageTokens.pressTravel : 0)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: BSListeningTokens.pressDuration),
                       value: configuration.isPressed)
    }
}
