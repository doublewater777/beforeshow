import SwiftUI

struct RootTabView: View {
    @Binding var selectedTab: BeforeShowTab
    @State private var mountedTabs: Set<BeforeShowTab> = [.current]

    var body: some View {
        ZStack {
            CurrentShowFeatureRootView(isPlaybackActive: selectedTab == .current)
                .opacity(selectedTab == .current ? 1 : 0)
                .allowsHitTesting(selectedTab == .current)
                .accessibilityHidden(selectedTab != .current)

            if mountedTabs.contains(.listen) || selectedTab == .listen {
                ListeningFeatureRootView(isActive: selectedTab == .listen)
                    .opacity(selectedTab == .listen ? 1 : 0)
                    .allowsHitTesting(selectedTab == .listen)
                    .accessibilityHidden(selectedTab != .listen)
            }

            if mountedTabs.contains(.footprints) || selectedTab == .footprints {
                FootprintsView()
                    .opacity(selectedTab == .footprints ? 1 : 0)
                    .allowsHitTesting(selectedTab == .footprints)
                    .accessibilityHidden(selectedTab != .footprints)
            }
        }
        .onChange(of: selectedTab) { _, tab in mountedTabs.insert(tab) }
        .task {
            // Spread first construction across idle turns, before a tab tap needs it.
            // Listen remains inactive, so music authorization/catalog loading waits.
            for tab in [BeforeShowTab.listen, .footprints] {
                do { try await Task.sleep(for: .milliseconds(600)) }
                catch { return }
                mountedTabs.insert(tab)
            }
        }
        .modifier(ListeningRootChromeModifier(selectedTab: $selectedTab))
        .modifier(FeedbackShakeShortcutModifier())
        // Keep system nav chrome neutral so tint does not leak into child controls.
        .tint(BSColor.Stage.foreground)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}
