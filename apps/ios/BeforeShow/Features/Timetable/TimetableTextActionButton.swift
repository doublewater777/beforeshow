import SwiftUI

struct TimetableTextActionButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(TimetableStyle.background)
                } else {
                    Text(title)
                }
            }
            .font(BSFont.body.weight(.bold))
            .foregroundStyle(TimetableStyle.background)
            .padding(.horizontal, BSSpacing.compact)
            .frame(minHeight: BSLayout.minTouchTarget)
            .background(Capsule().fill(TimetableStyle.foreground))
        }
        .buttonStyle(TimetablePressStyle())
        .disabled(isLoading)
    }
}
