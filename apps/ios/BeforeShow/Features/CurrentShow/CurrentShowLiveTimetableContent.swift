import SwiftUI

struct CurrentShowLiveTimetableContent<Content: View>: View {
    let show: Show
    let isActive: Bool
    @ViewBuilder let content: (Date, LiveModeState?) -> Content

    @AppStorage(LiveModeFocusStore.key, store: LiveModeFocusStore.defaults) private var focusedPerformanceID: String?

    var body: some View {
        TimelineView(CurrentShowTimelineSchedule(isActive: isActive)) { context in
            content(
                context.date,
                CurrentShowLiveTimetablePolicy.resolve(
                    for: show,
                    now: context.date,
                    focusedPerformanceID: focusedPerformanceID.flatMap(UUID.init(uuidString:))
                )
            )
        }
    }
}
